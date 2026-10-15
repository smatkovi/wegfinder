//! Die Schnittstelle api.i-mobility.at und ihre anonyme Sitzung.
//!
//! So macht es die Android-App (abgelesen aus 26.20.0, siehe api.md):
//!
//! 1. `POST v1/register_client` ohne Rumpf -> `client_id`, `client_secret`.
//!    Der Server verlangt dabei den Kopf `x-imob-identity`
//!    ("wegfinder/<version>;<plattform>/<version>") -- ohne ihn scheitert
//!    das Anlegen an einer leeren Spalte "platform".
//! 2. `POST v2/register` mit `{client_id, client_secret}` -> Zugangstoken
//!    (Bearer, 300 s gueltig) und Erneuerungstoken.
//! 3. `POST v2/token` (Formular, grant_type=refresh_token) erneuert.
//!
//! Ein Konto braucht es fuer Suche, Routen, Abfahrten und Umgebung nicht.
//! Die Sitzung liegt in ~/.config/wegfinder/sitzung.json (0600), damit nicht
//! jeder Start zwei zusaetzliche Rundreisen kostet.

use crate::ablage::Ablage;
use crate::netz::{Netz, Rumpf};
use crate::{protokoll, zeit};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};

pub const BASIS: &str = "https://api.i-mobility.at/";
/// Die App-Fassung, deren Schnittstelle dieser Client spricht. Der Server
/// prueft den Namen vor dem Schraegstrich ("wegfinder"), anderes lehnt er
/// mit 418 ab.
const APP: &str = "wegfinder/26.20.0";

#[derive(Default, Clone)]
struct Sitzung {
    client_id: String,
    client_secret: String,
    geraet: String,
    zugang: String,
    erneuern: String,
    ablauf: i64,
}

impl Sitzung {
    fn aus(v: &Value) -> Sitzung {
        let s = |k: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string();
        Sitzung {
            client_id: s("client_id"),
            client_secret: s("client_secret"),
            geraet: s("geraet"),
            zugang: s("zugang"),
            erneuern: s("erneuern"),
            ablauf: v.get("ablauf").and_then(|x| x.as_i64()).unwrap_or(0),
        }
    }
    fn json(&self) -> Value {
        json!({
            "client_id": self.client_id, "client_secret": self.client_secret,
            "geraet": self.geraet, "zugang": self.zugang,
            "erneuern": self.erneuern, "ablauf": self.ablauf,
        })
    }
}

pub struct Imob {
    netz: Arc<Netz>,
    sitzung: Mutex<Sitzung>,
    kennung: String,
    sprache: String,
}

/// Plattform fuer x-imob-identity: ehrlich, was hier laeuft.
pub fn plattform() -> String {
    if let Ok(t) = std::fs::read_to_string("/etc/sailfish-release") {
        for z in t.lines() {
            if let Some(v) = z.strip_prefix("VERSION_ID=") {
                return format!("sailfish/{}", v.trim_matches('"'));
            }
        }
        return "sailfish/5".into();
    }
    if std::path::Path::new("/etc/meego-release").exists()
        || std::path::Path::new("/usr/bin/aegis-exec").exists()
    {
        return "meego/1.2".into();
    }
    "linux/1".into()
}

fn zufall_hex(n: usize) -> String {
    let mut roh = vec![0u8; n];
    if let Ok(mut f) = std::fs::File::open("/dev/urandom") {
        use std::io::Read;
        let _ = f.read_exact(&mut roh);
    }
    roh.iter().map(|b| format!("{:02x}", b)).collect()
}

fn enc(s: &str) -> String {
    url::form_urlencoded::byte_serialize(s.as_bytes()).collect()
}

/// Fehlertext aus {"error": {...}} des Servers.
pub fn serverfehler(status: u16, v: &Value) -> String {
    let e = v.get("error").unwrap_or(v);
    for k in ["message", "title", "description"] {
        if let Some(t) = e.get(k).and_then(|x| x.as_str()) {
            if !t.trim().is_empty() {
                return format!("{} (HTTP {})", t.trim(), status);
            }
        }
    }
    match status {
        400 => "Der Server versteht die Anfrage nicht (HTTP 400).".into(),
        404 => "Nicht gefunden (HTTP 404).".into(),
        429 => "Zu viele Anfragen – bitte kurz warten (HTTP 429).".into(),
        500..=599 => format!("Der wegfinder-Server hat ein Problem (HTTP {}).", status),
        _ => format!("Fehler vom Server (HTTP {}).", status),
    }
}

impl Imob {
    pub fn neu(ablage: &Ablage) -> Imob {
        let mut s = ablage.lesen(&ablage.sitzung()).map(|v| Sitzung::aus(&v)).unwrap_or_default();
        if s.geraet.is_empty() {
            s.geraet = zufall_hex(8);
        }
        let sprache = std::env::var("LANG").unwrap_or_default();
        let sprache = if sprache.starts_with("en") { "en" } else { "de" }.to_string();
        Imob {
            netz: Arc::new(Netz::neu()),
            sitzung: Mutex::new(s),
            kennung: format!("{};{}", APP, plattform()),
            sprache,
        }
    }

    pub fn netz(&self) -> Arc<Netz> {
        self.netz.clone()
    }

    fn kopf(&self) -> Vec<(String, String)> {
        vec![
            ("x-imob-identity".into(), self.kennung.clone()),
            ("x-imob-app-state".into(), "foreground".into()),
            ("x-imob-feature-overrides".into(), "accessible-image-urls".into()),
            ("Accept-Language".into(), self.sprache.clone()),
        ]
    }

    fn sichern(&self, ablage: &Ablage, s: &Sitzung) {
        if let Err(e) = ablage.schreiben_geheim(&ablage.sitzung(), &s.json()) {
            protokoll(&format!("imob: Sitzung nicht gespeichert: {}", e));
        }
    }

    /// Uebernimmt eine Token-Antwort in die Sitzung.
    fn token_uebernehmen(s: &mut Sitzung, v: &Value) -> bool {
        let zugang = v.get("access_token").and_then(|x| x.as_str()).unwrap_or("");
        if zugang.is_empty() {
            return false;
        }
        s.zugang = zugang.to_string();
        if let Some(r) = v.get("refresh_token").and_then(|x| x.as_str()) {
            if !r.is_empty() {
                s.erneuern = r.to_string();
            }
        }
        let dauer = v.get("expires_in").and_then(|x| x.as_i64()).unwrap_or(300);
        s.ablauf = zeit::jetzt_utc() + dauer;
        true
    }

    fn erneuern(&self, s: &mut Sitzung) -> bool {
        if s.erneuern.is_empty() || s.client_id.is_empty() {
            return false;
        }
        let form = format!(
            "grant_type=refresh_token&client_id={}&client_secret={}&refresh_token={}&device={}",
            enc(&s.client_id), enc(&s.client_secret), enc(&s.erneuern), enc(&s.geraet)
        );
        let mut kopf = self.kopf();
        kopf.push(("X-Imob-Originated-From".into(), "refreshing_token".into()));
        match self.netz.senden("POST", &format!("{}v2/token", BASIS), &kopf, Rumpf::Form(form), true) {
            Ok(a) if a.status == 200 => a.json().map(|v| Self::token_uebernehmen(s, &v)).unwrap_or(false),
            Ok(a) => {
                protokoll(&format!("imob: Erneuern abgelehnt (HTTP {})", a.status));
                false
            }
            Err(_) => false,
        }
    }

    fn registrieren(&self, s: &mut Sitzung) -> Result<bool, String> {
        if s.client_id.is_empty() {
            return Ok(false);
        }
        let rumpf = json!({"client_id": s.client_id, "client_secret": s.client_secret});
        let a = self.netz.senden("POST", &format!("{}v2/register", BASIS), &self.kopf(), Rumpf::Json(&rumpf), true)?;
        if a.status == 200 {
            return Ok(Self::token_uebernehmen(s, &a.json()?));
        }
        protokoll(&format!("imob: Registrieren abgelehnt (HTTP {})", a.status));
        Ok(false)
    }

    fn client_anlegen(&self, s: &mut Sitzung) -> Result<(), String> {
        let a = self.netz.senden("POST", &format!("{}v1/register_client", BASIS), &self.kopf(), Rumpf::Keiner, true)?;
        let v = a.json()?;
        if a.status != 200 {
            return Err(serverfehler(a.status, &v));
        }
        s.client_id = v.get("client_id").and_then(|x| x.as_str()).unwrap_or("").to_string();
        s.client_secret = v.get("client_secret").and_then(|x| x.as_str()).unwrap_or("").to_string();
        if s.client_id.is_empty() {
            return Err("Der Server hat keinen Zugang vergeben.".into());
        }
        protokoll("imob: neuer anonymer Client angelegt");
        Ok(())
    }

    /// Ein gueltiges Zugangstoken; legt bei Bedarf alles neu an. Unter dem
    /// Schloss, damit nie zwei Faeden gleichzeitig erneuern.
    fn token(&self, ablage: &Ablage, erzwingen: bool) -> Result<String, String> {
        let mut s = self.sitzung.lock().unwrap_or_else(|e| e.into_inner());
        if !erzwingen && !s.zugang.is_empty() && s.ablauf > zeit::jetzt_utc() + 20 {
            return Ok(s.zugang.clone());
        }
        let mut neu = s.clone();
        let ok = self.erneuern(&mut neu) || self.registrieren(&mut neu)? || {
            self.client_anlegen(&mut neu)?;
            self.registrieren(&mut neu)?
        };
        if !ok {
            return Err("Anmeldung beim wegfinder-Server gescheitert.".into());
        }
        self.sichern(ablage, &neu);
        *s = neu;
        Ok(s.zugang.clone())
    }

    /// GET/POST gegen die Schnittstelle. `pfad` ist relativ zu BASIS oder
    /// eine volle Adresse, die der Server selbst geliefert hat (Blaettern,
    /// weitere Verkehrsmittel) -- dann aber nur auf demselben Server.
    pub fn api(&self, ablage: &Ablage, methode: &str, pfad: &str) -> Result<Value, String> {
        let url = if pfad.starts_with("https://") {
            if !pfad.starts_with(BASIS) {
                return Err("Fremde Adresse abgelehnt.".into());
            }
            pfad.to_string()
        } else {
            format!("{}{}", BASIS, pfad)
        };
        let mut versuch = 0;
        loop {
            let token = self.token(ablage, versuch > 0)?;
            let mut kopf = self.kopf();
            kopf.push(("Authorization".into(), format!("Bearer {}", token)));
            let a = self.netz.senden(methode, &url, &kopf, Rumpf::Keiner, false)?;
            if (a.status == 401 || a.status == 403) && versuch == 0 {
                versuch += 1;
                continue;
            }
            let v = a.json().unwrap_or(Value::Null);
            if a.status >= 300 {
                return Err(serverfehler(a.status, &v));
            }
            return Ok(v);
        }
    }
}
