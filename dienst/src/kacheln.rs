//! Kartenkacheln fuer die Oberflaeche, ueber 127.0.0.1.
//!
//! Das Qt 4.7 des N9 kann die Kachelserver (nur TLS 1.2) nicht selbst
//! erreichen. Deshalb laeuft hier ein winziger HTTP-Server nur fuer die
//! eigene App: `GET /<z>/<x>/<y>.png` liefert die Kachel aus
//! ~/.cache/wegfinder/kacheln oder holt sie einmal von OpenStreetMap. QML
//! laedt sie dann wie jedes andere Bild, asynchron und mit eigenem
//! Zwischenspeicher.
//!
//! Fuers 2G-Netz:
//! * jede Kachel geht nur einmal uebers Netz (30 Tage behalten, danach
//!   neu, und wenn das scheitert, gilt die alte weiter);
//! * hoechstens zwei Downloads gleichzeitig -- mehr verstopft die Leitung
//!   nur, und die Route soll vor den Kacheln ankommen;
//! * der Sparmodus der Oberflaeche fragt eine Zoomstufe tiefer und zeigt
//!   doppelt so gross: ein Viertel der Kacheln.

use crate::netz::Netz;
use crate::protokoll;
use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::sync::{Arc, Condvar, Mutex, OnceLock};
use std::time::{Duration, SystemTime};

const QUELLE: &str = "https://tile.openstreetmap.org";
const GUELTIG: Duration = Duration::from_secs(30 * 86400);
const GLEICHZEITIG: usize = 2;

static PORT: OnceLock<u16> = OnceLock::new();

struct Schranke {
    frei: Mutex<usize>,
    signal: Condvar,
}

impl Schranke {
    fn betreten(&self) {
        let mut f = self.frei.lock().unwrap_or_else(|e| e.into_inner());
        while *f == 0 {
            f = self.signal.wait(f).unwrap_or_else(|e| e.into_inner());
        }
        *f -= 1;
    }
    fn verlassen(&self) {
        let mut f = self.frei.lock().unwrap_or_else(|e| e.into_inner());
        *f += 1;
        self.signal.notify_one();
    }
}

/// Startet den Server beim ersten Aufruf und gibt seinen Port zurueck.
pub fn port(ordner: PathBuf, netz: Arc<Netz>) -> Result<u16, String> {
    if let Some(p) = PORT.get() {
        return Ok(*p);
    }
    let lauscher = TcpListener::bind("127.0.0.1:0").map_err(|e| format!("Kachelserver: {}", e))?;
    let port = lauscher.local_addr().map_err(|e| e.to_string())?.port();
    if PORT.set(port).is_err() {
        // ein anderer Faden war schneller
        return Ok(*PORT.get().unwrap());
    }
    let schranke = Arc::new(Schranke { frei: Mutex::new(GLEICHZEITIG), signal: Condvar::new() });
    std::thread::spawn(move || {
        for strom in lauscher.incoming() {
            let strom = match strom {
                Ok(s) => s,
                Err(_) => continue,
            };
            let (ordner, netz, schranke) = (ordner.clone(), netz.clone(), schranke.clone());
            std::thread::spawn(move || bedienen(strom, &ordner, &netz, &schranke));
        }
    });
    protokoll(&format!("kacheln: lausche auf 127.0.0.1:{}", port));
    Ok(port)
}

fn antworten(mut strom: TcpStream, status: &str, art: &str, inhalt: &[u8]) {
    let kopf = format!(
        "HTTP/1.0 {}\r\nContent-Type: {}\r\nContent-Length: {}\r\nCache-Control: max-age=86400\r\nConnection: close\r\n\r\n",
        status, art, inhalt.len()
    );
    let _ = strom.write_all(kopf.as_bytes());
    let _ = strom.write_all(inhalt);
    let _ = strom.flush();
}

/// "/14/8936/5681.png" -> (14, 8936, 5681), nur gueltige Kacheln.
fn pfad_lesen(pfad: &str) -> Option<(u32, u32, u32)> {
    let p = pfad.trim_start_matches('/').trim_end_matches(".png");
    let mut t = p.split('/');
    let z: u32 = t.next()?.parse().ok()?;
    let x: u32 = t.next()?.parse().ok()?;
    let y: u32 = t.next()?.parse().ok()?;
    if t.next().is_some() || z > 19 {
        return None;
    }
    let n = 1u32 << z;
    if x >= n || y >= n {
        return None;
    }
    Some((z, x, y))
}

fn bedienen(strom: TcpStream, ordner: &PathBuf, netz: &Netz, schranke: &Schranke) {
    let _ = strom.set_read_timeout(Some(Duration::from_secs(10)));
    let mut leser = BufReader::new(match strom.try_clone() {
        Ok(s) => s,
        Err(_) => return,
    });
    let mut zeile = String::new();
    if leser.read_line(&mut zeile).is_err() {
        return;
    }
    // Kopfzeilen ueberlesen
    let mut rest = String::new();
    while leser.read_line(&mut rest).map(|n| n > 2).unwrap_or(false) {
        rest.clear();
    }
    let mut teile = zeile.split_whitespace();
    let (methode, pfad) = (teile.next().unwrap_or(""), teile.next().unwrap_or(""));
    let kachel = if methode == "GET" { pfad_lesen(pfad) } else { None };
    let (z, x, y) = match kachel {
        Some(k) => k,
        None => return antworten(strom, "404 Not Found", "text/plain", b"nein"),
    };
    let datei = ordner.join(z.to_string()).join(x.to_string()).join(format!("{}.png", y));
    let alt = std::fs::read(&datei).ok();
    let frisch = std::fs::metadata(&datei)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| SystemTime::now().duration_since(t).ok())
        .map(|a| a < GUELTIG)
        .unwrap_or(false);
    if let (Some(daten), true) = (&alt, frisch) {
        return antworten(strom, "200 OK", "image/png", daten);
    }
    schranke.betreten();
    let geholt = netz.holen_roh(&format!("{}/{}/{}/{}.png", QUELLE, z, x, y));
    schranke.verlassen();
    match geholt {
        Ok((200, daten)) if daten.starts_with(b"\x89PNG") => {
            if let Some(eltern) = datei.parent() {
                let _ = std::fs::create_dir_all(eltern);
            }
            let neben = datei.with_extension(format!("{}.neu", std::process::id()));
            if std::fs::write(&neben, &daten).is_ok() {
                let _ = std::fs::rename(&neben, &datei);
            }
            antworten(strom, "200 OK", "image/png", &daten)
        }
        other => {
            if let Some(daten) = alt {
                return antworten(strom, "200 OK", "image/png", &daten);
            }
            let grund = match other {
                Ok((s, _)) => format!("HTTP {}", s),
                Err(e) => e,
            };
            protokoll(&format!("kacheln: {}/{}/{} -> {}", z, x, y, grund));
            antworten(strom, "502 Bad Gateway", "text/plain", grund.as_bytes())
        }
    }
}

/// Belegter Platz der Kacheln in Bytes (fuer die Einstellungen).
pub fn groesse(ordner: &PathBuf) -> u64 {
    fn summe(p: &std::path::Path) -> u64 {
        let mut s = 0;
        if let Ok(it) = std::fs::read_dir(p) {
            for e in it.flatten() {
                let m = match e.metadata() {
                    Ok(m) => m,
                    Err(_) => continue,
                };
                s += if m.is_dir() { summe(&e.path()) } else { m.len() };
            }
        }
        s
    }
    summe(ordner)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pfade() {
        assert_eq!(pfad_lesen("/14/8936/5681.png"), Some((14, 8936, 5681)));
        assert_eq!(pfad_lesen("/1/2/0.png"), None);
        assert_eq!(pfad_lesen("/../../etc/passwd"), None);
        assert_eq!(pfad_lesen("/14/1/2/3.png"), None);
    }
}
