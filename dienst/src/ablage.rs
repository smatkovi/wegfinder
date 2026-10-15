//! Wo der Dienst Dinge ablegt.
//!
//!   ~/.config/wegfinder/        Sitzung beim Server (0600), Einstellungen
//!   ~/.local/share/wegfinder/   Favoriten und zuletzt gesuchte Orte
//!   ~/.cache/wegfinder/         Kartenkacheln, Filterliste, Protokoll --
//!                               darf verschwinden
//!
//! Geschrieben wird immer erst in eine Nebendatei und dann umbenannt: ein
//! leerer Akku mitten im Schreiben darf keine halbe Datei hinterlassen.

use serde_json::Value;
use std::fs;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

const NAME: &str = "wegfinder";

pub struct Ablage {
    pub konfig: PathBuf,
    pub cache: PathBuf,
    pub daten: PathBuf,
}

impl Ablage {
    pub fn neu() -> Ablage {
        let heim = std::env::var("HOME").unwrap_or_else(|_| "/home/user".into());
        let heim = Path::new(&heim);
        let a = Ablage {
            konfig: heim.join(".config").join(NAME),
            cache: heim.join(".cache").join(NAME),
            daten: heim.join(".local/share").join(NAME),
        };
        for d in [&a.konfig, &a.cache, &a.daten] {
            let _ = fs::create_dir_all(d);
        }
        a
    }

    pub fn lesen(&self, pfad: &Path) -> Option<Value> {
        let text = fs::read(pfad).ok()?;
        serde_json::from_slice(&text).ok()
    }

    pub fn schreiben(&self, pfad: &Path, wert: &Value) -> std::io::Result<()> {
        self.schreiben_mit(pfad, wert.to_string().as_bytes(), 0o644)
    }

    /// Fuer die Sitzung beim Server: nur der Besitzer darf lesen.
    pub fn schreiben_geheim(&self, pfad: &Path, wert: &Value) -> std::io::Result<()> {
        self.schreiben_mit(pfad, wert.to_string().as_bytes(), 0o600)
    }

    fn schreiben_mit(&self, pfad: &Path, inhalt: &[u8], modus: u32) -> std::io::Result<()> {
        if let Some(eltern) = pfad.parent() {
            fs::create_dir_all(eltern)?;
        }
        // Eine eigene Nebendatei je Schreibvorgang: zwei Faeden, die
        // dieselbe Kachel laden, raeumten sich sonst gegenseitig die
        // Nebendatei weg.
        static ZAEHLER: AtomicUsize = AtomicUsize::new(0);
        let nr = ZAEHLER.fetch_add(1, Ordering::SeqCst);
        let name = pfad.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let neben = pfad.with_file_name(format!(".{}.{}.{}.neu", name, std::process::id(), nr));
        let ergebnis = (|| {
            let mut f = fs::OpenOptions::new()
                .create_new(true)
                .write(true)
                .mode(modus)
                .open(&neben)?;
            f.write_all(inhalt)?;
            f.sync_all()?;
            fs::rename(&neben, pfad)
        })();
        if ergebnis.is_err() {
            let _ = fs::remove_file(&neben);
        }
        ergebnis
    }

    pub fn sitzung(&self) -> PathBuf {
        self.konfig.join("sitzung.json")
    }
    pub fn einstellungen(&self) -> PathBuf {
        self.konfig.join("einstellungen.json")
    }
    pub fn orte(&self) -> PathBuf {
        self.daten.join("orte.json")
    }
    pub fn filter(&self) -> PathBuf {
        self.cache.join("filter.json")
    }
    pub fn kacheln(&self) -> PathBuf {
        self.cache.join("kacheln")
    }
}
