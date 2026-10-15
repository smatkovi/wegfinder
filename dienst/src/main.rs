//! wf-dienst: die Netzseite von wegfinder fuer N9/N950 und Sailfish OS.
//!
//! Liest Anfragen zeilenweise von stdin, je Zeile `id TAB befehl TAB json`,
//! und schreibt je Anfrage genau eine Antwort `id TAB 1|0 TAB json` nach
//! stdout. Jede Anfrage laeuft in einem eigenen Faden; die Oberflaeche ordnet
//! die Antworten ueber die Nummer zu. Endet stdin, endet der Dienst -- dann
//! ist die App zu.
//!
//! Der Dienst formt die Antworten des Servers vorab in kleine, fertig
//! beschriftete Objekte um (Uhrzeiten, Dauer, Farben). So hat das QML am N9
//! wenig zu zerlegen: eine Abfahrtstafel kommt mit 230 KB JSON vom Server,
//! bei der Oberflaeche kommen davon 10 KB an.
//!
//! Zum Probieren von der Kommandozeile:
//!
//!     printf '1\tsuche\t{"text":"Westbahnhof"}\n' | wf-dienst

mod ablage;
mod api;
mod arten;
mod format;
mod imob;
mod kauf;
mod konto;
mod kacheln;
mod netz;
mod orte;
mod polylinie;
mod tickets;
mod zahlung;
mod zeit;

use serde_json::Value;
use std::io::{BufRead, Write};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

static PROTOKOLL: OnceLock<Mutex<Option<std::fs::File>>> = OnceLock::new();

/// Schreibt eine Zeile nach stderr und nach ~/.cache/wegfinder/dienst.log.
///
/// Die Datei ist fuer den Fall da, dass die App ueber das Symbol gestartet
/// wurde: dann liest niemand stderr. Sie wird beim Start gekuerzt, sobald
/// sie 300 KB uebersteigt. Tokens kommen nie hinein (siehe netz::senden).
pub fn protokoll(zeile: &str) {
    eprintln!("{}", zeile);
    if let Some(m) = PROTOKOLL.get() {
        if let Ok(mut f) = m.lock() {
            if let Some(f) = f.as_mut() {
                let _ = writeln!(f, "{} {}", zeit::jetzt_text(), zeile);
            }
        }
    }
}

fn protokoll_oeffnen(ablage: &ablage::Ablage) {
    let pfad = ablage.cache.join("dienst.log");
    let zu_gross = std::fs::metadata(&pfad).map(|m| m.len() > 300 * 1024).unwrap_or(false);
    let datei = std::fs::OpenOptions::new()
        .create(true)
        .append(!zu_gross)
        .write(true)
        .truncate(zu_gross)
        .open(&pfad)
        .ok();
    let _ = PROTOKOLL.set(Mutex::new(datei));
}

fn schreiben(aus: &Mutex<std::io::Stdout>, id: &str, ergebnis: Result<Value, String>) {
    let (ok, json) = match ergebnis {
        Ok(v) => ("1", v.to_string()),
        Err(e) => ("0", Value::String(e).to_string()),
    };
    let mut aus = aus.lock().unwrap_or_else(|e| e.into_inner());
    // Ein einziges write je Zeile, damit sich zwei Faeden nie mitten in
    // einer Zeile abwechseln.
    let zeile = format!("{}\t{}\t{}\n", id, ok, json);
    let _ = aus.write_all(zeile.as_bytes());
    let _ = aus.flush();
}

fn main() {
    let ablage = ablage::Ablage::neu();
    protokoll_oeffnen(&ablage);
    let kontext = Arc::new(api::Kontext::neu(ablage));
    let aus = Arc::new(Mutex::new(std::io::stdout()));
    let laufend = Arc::new(AtomicUsize::new(0));

    protokoll(&format!("wf-dienst {}: bereit ({})", env!("CARGO_PKG_VERSION"), kontext.plattform()));

    let stdin = std::io::stdin();
    for zeile in stdin.lock().lines() {
        let zeile = match zeile {
            Ok(z) => z,
            Err(_) => break,
        };
        let mut teile = zeile.splitn(3, '\t');
        let (id, befehl, json) = match (teile.next(), teile.next(), teile.next()) {
            (Some(i), Some(b), Some(j)) => (i.to_string(), b.to_string(), j.to_string()),
            _ => {
                // Nur die Laenge: die Zeile kann Kartendaten oder ein Kennwort tragen.
                protokoll(&format!("wf-dienst: unlesbare Anfrage ({} Zeichen)", zeile.len()));
                continue;
            }
        };
        let kontext = kontext.clone();
        let aus = aus.clone();
        let laufend = laufend.clone();
        laufend.fetch_add(1, Ordering::SeqCst);
        std::thread::spawn(move || {
            let werte: Value = serde_json::from_str(&json).unwrap_or(Value::Null);
            let beginn = Instant::now();
            let ergebnis = api::bearbeiten(&kontext, &befehl, &werte);
            match &ergebnis {
                Ok(_) => protokoll(&format!(
                    "wf-dienst: {} ok in {} ms", befehl, beginn.elapsed().as_millis())),
                Err(e) => protokoll(&format!(
                    "wf-dienst: {} FEHLER in {} ms: {}", befehl, beginn.elapsed().as_millis(), e)),
            }
            schreiben(&aus, &id, ergebnis);
            laufend.fetch_sub(1, Ordering::SeqCst);
        });
    }
    // stdin zu: die App ist beendet. Von der Kommandozeile (printf ... |
    // wf-dienst) kaemen sonst gar keine Antworten.
    let ende = Instant::now() + Duration::from_secs(30);
    while laufend.load(Ordering::SeqCst) > 0 && Instant::now() < ende {
        std::thread::sleep(Duration::from_millis(20));
    }
}
