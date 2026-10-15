//! HTTP ueber einen einzigen ureq-Agenten.
//!
//! Ein Agent fuer die ganze Laufzeit heisst: die TLS-Verbindungen zum
//! Server und zu den Kacheln bleiben offen und werden wiederverwendet. Im
//! 2G-Netz kostet ein TLS-Handschlag mehrere Rundreisen, also Sekunden.
//! gzip handelt ureq selbst aus (Accept-Encoding) und entpackt.

use crate::protokoll;
use serde_json::Value;
use std::io::Read;
use std::sync::Arc;
use std::time::Duration;

/// Eine eigene Kennung, keine geliehene: der Server soll sehen, wer fragt.
pub const UA: &str = concat!(
    "wegfinder-sfos-meego/",
    env!("CARGO_PKG_VERSION"),
    " (inoffizieller Client; MeeGo Harmattan / Sailfish OS; https://github.com/smatkovi/wegfinder)"
);

pub struct Netz {
    agent: ureq::Agent,
}

#[derive(Debug)]
pub struct Antwort {
    pub status: u16,
    pub text: String,
    /// Location-Kopf bei Weiterleitungen
    pub ort: Option<String>,
}

pub enum Rumpf<'a> {
    Keiner,
    Json(&'a Value),
    Form(String),
}

impl Antwort {
    pub fn json(&self) -> Result<Value, String> {
        if self.text.trim().is_empty() {
            return Ok(Value::Null);
        }
        serde_json::from_str(&self.text).map_err(|e| {
            format!("Unerwartete Antwort vom Server ({}): {:.120}", e, self.text)
        })
    }
}

impl Netz {
    pub fn neu() -> Netz {
        let agent = ureq::AgentBuilder::new()
            .tls_connector(Arc::new(tls_einrichten()))
            .user_agent(UA)
            // 2G: der Verbindungsaufbau allein kann zehn Sekunden dauern.
            .timeout_connect(Duration::from_secs(30))
            .timeout(Duration::from_secs(60))
            .max_idle_connections_per_host(4)
            // Weiterleitungen selbst: ureq liesse dabei den
            // Authorization-Kopf fallen (POST v3/flow antwortet mit 303).
            .redirects(0)
            .build();
        Netz { agent }
    }

    /// Fuehrt eine Anfrage aus. HTTP-Fehlerstatus sind hier kein Fehler: der
    /// Aufrufer bekommt Status und Rumpf und entscheidet. Fehler ist nur,
    /// wenn gar keine Antwort kam.
    ///
    /// `geheim`: Anmeldeaufrufe. Deren Rumpf (Client-Geheimnis, Tokens)
    /// kommt nie ins Protokoll, auch nicht die Antwort.
    pub fn senden(
        &self,
        methode: &str,
        url: &str,
        kopf: &[(String, String)],
        rumpf: Rumpf,
        geheim: bool,
    ) -> Result<Antwort, String> {
        let mut anfrage = self.agent.request(methode, url).set("Accept", "application/json");
        for (k, v) in kopf {
            anfrage = anfrage.set(k, v);
        }
        let ergebnis = match rumpf {
            Rumpf::Keiner => {
                if methode == "POST" {
                    anfrage.set("Content-Length", "0").call()
                } else {
                    anfrage.call()
                }
            }
            Rumpf::Json(r) => anfrage
                .set("Content-Type", "application/json; charset=UTF-8")
                .send_string(&r.to_string()),
            Rumpf::Form(f) => anfrage
                .set("Content-Type", "application/x-www-form-urlencoded")
                .send_string(&f),
        };
        let pfad = kurz(url);
        let antwort = match ergebnis {
            Ok(a) => a,
            Err(ureq::Error::Status(_, a)) => a,
            Err(ureq::Error::Transport(t)) => {
                protokoll(&format!("netz: {} {} -> {}", methode, pfad, t));
                return Err(transportfehler(&t));
            }
        };
        let status = antwort.status();
        let ort = antwort.header("location").map(|s| s.to_string());
        let mut roh = Vec::new();
        antwort
            .into_reader()
            .take(16 * 1024 * 1024)
            .read_to_end(&mut roh)
            .map_err(|e| format!("Antwort abgebrochen: {}", e))?;
        let text = String::from_utf8_lossy(&roh).into_owned();
        if geheim {
            protokoll(&format!("netz: {} {} -> {} ({} B)", methode, pfad, status, roh.len()));
        } else {
            let anfang: String = text.chars().take(160).collect();
            protokoll(&format!(
                "netz: {} {} -> {} ({} B) {}",
                methode, pfad, status, roh.len(), anfang.replace('\n', " ")
            ));
        }
        Ok(Antwort { status, text, ort })
    }

    /// Laedt eine Datei (Kartenkachel) herunter: (Status, Bytes).
    pub fn holen_roh(&self, url: &str) -> Result<(u16, Vec<u8>), String> {
        self.holen_roh_mit(url, &[])
    }

    /// Wie holen_roh, mit Koepfen (Ticket-PDF mit Anmeldung).
    pub fn holen_roh_mit(&self, url: &str, kopf: &[(String, String)]) -> Result<(u16, Vec<u8>), String> {
        let mut anfrage = self.agent.get(url);
        for (k, v) in kopf {
            anfrage = anfrage.set(k, v);
        }
        let antwort = match anfrage.call() {
            Ok(a) => a,
            Err(ureq::Error::Status(_, a)) => a,
            Err(ureq::Error::Transport(t)) => return Err(transportfehler(&t)),
        };
        let status = antwort.status();
        let mut roh = Vec::new();
        antwort
            .into_reader()
            .take(16 * 1024 * 1024)
            .read_to_end(&mut roh)
            .map_err(|e| format!("Download abgebrochen: {}", e))?;
        Ok((status, roh))
    }
}

/// Die Wurzelzertifikate kommen aus dem Binary, nicht vom Geraet.
///
/// Harmattan fuehrt seine eigene Zertifikatsablage, Stand 2013: die kennt
/// die heutigen Wurzeln nicht. Geprueft wird gegen das Mozilla-Buendel von
/// curl.se (certs/cacert.pem, beim Bauen eingebettet). Aktualisieren: die
/// Datei ersetzen und neu bauen.
fn tls_einrichten() -> native_tls::TlsConnector {
    const BUENDEL: &str = include_str!("../certs/cacert.pem");
    let mut bauer = native_tls::TlsConnector::builder();
    bauer.disable_built_in_roots(true);
    let mut anzahl = 0;
    for block in BUENDEL.split("-----END CERTIFICATE-----") {
        let anfang = match block.find("-----BEGIN CERTIFICATE-----") {
            Some(a) => a,
            None => continue,
        };
        let pem = format!("{}-----END CERTIFICATE-----\n", &block[anfang..]);
        if let Ok(zert) = native_tls::Certificate::from_pem(pem.as_bytes()) {
            bauer.add_root_certificate(zert);
            anzahl += 1;
        }
    }
    protokoll(&format!("netz: {} Wurzelzertifikate geladen", anzahl));
    bauer.build().expect("OpenSSL laesst sich nicht einrichten")
}

/// Adresse ohne Abfrageteil fuers Protokoll.
fn kurz(url: &str) -> String {
    let ohne = url.split('?').next().unwrap_or(url);
    ohne.trim_start_matches("https://").to_string()
}

fn transportfehler(t: &ureq::Transport) -> String {
    let text = t.to_string();
    if text.contains("Dns") || text.contains("resolve") || text.contains("lookup") {
        "Keine Verbindung: der Server ist nicht erreichbar (kein Netz?).".into()
    } else if text.contains("timed out") || text.contains("Timeout") {
        "Zeitüberschreitung: der Server antwortet nicht.".into()
    } else {
        format!("Netzwerkfehler: {}", text)
    }
}
