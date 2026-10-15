//! Zahlungsmittel des wegfinder-Kontos: Kreditkarte (auch Debitkarte) und
//! PayPal. Google Pay gibt es ohne Play-Dienste nicht.
//!
//! Wie die Android-App (befund-zahlung.md), ohne WebView:
//!
//! Kreditkarte
//! 1. `POST v2/payment_options` `{source, set_default, set_fallback,
//!    payment_type: "credit_card"}` -> Kopf `Location`, im Rumpf
//!    `credit_card.api_key`.
//! 2. `POST https://mpay24.com/app/bin/tokenizer/api/v1/cc`, Kopf `Api-Key`,
//!    `{brand, identifier (Kartennummer), expiry (JJMM), cvc}` -> Karte
//!    `{brand, identifier, expiry, redirect?: {title, initial, final}}`.
//!    Die Kartendaten gehen nur dorthin: nie in eine Datei, nie ins
//!    Protokoll (netz::senden mit geheim).
//! 3. `PATCH <Location>` `{"credit_card": <Antwort von mpay24>}`.
//! 4. Hat die Karte `redirect.initial`: 3-D Secure im Browser, dann
//!    `GET v2/payment_options/{id}` bis `initialized && !verification_failed`.
//!
//! PayPal: `POST v2/payment_options` mit `payment_type: "paypal"` ->
//! `approve_url` im Browser freigeben, dann `PATCH v2/payment_options/{id}`
//! `{"payment_type": "paypal"}` und wieder abfragen.

use crate::ablage::Ablage;
use crate::format::s;
use crate::imob::{serverfehler, Imob, BASIS};
use crate::netz::Rumpf;
use serde_json::{json, Value};

const MPAY24: &str = "https://mpay24.com/app/bin/tokenizer/api/v1/cc";

/// Ein Zahlungsmittel fuer die Oberflaeche.
pub fn eintrag(p: &Value) -> Value {
    let typ = s(p, "payment_type");
    let karte = p.get("credit_card").cloned().unwrap_or(Value::Null);
    let nummer = s(&karte, "identifier");
    let letzte: String = nummer.chars().filter(|c| c.is_ascii_digit()).rev().take(4).collect::<Vec<_>>().into_iter().rev().collect();
    let titel = if typ == "paypal" {
        let n = s(p, "name");
        if n.is_empty() { "PayPal".to_string() } else { n }
    } else if !letzte.is_empty() {
        format!("{} •••• {}", s(&karte, "brand"), letzte)
    } else {
        s(p, "name")
    };
    let ablauf = s(&karte, "expiry");
    let ablauf = if ablauf.len() == 4 { format!("{}/{}", &ablauf[2..4], &ablauf[0..2]) } else { ablauf };
    let fertig = p["initialized"].as_bool().unwrap_or(true) && !p["verification_failed"].as_bool().unwrap_or(false);
    let hinweis = ["error", "warning", "info"]
        .iter()
        .map(|k| crate::tickets::text(p.get(*k).unwrap_or(&Value::Null)))
        .filter(|t| !t.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
    json!({
        "id": s(p, "id"),
        "typ": typ,
        "titel": titel,
        "beschreibung": s(p, "description"),
        "ablauf": ablauf,
        "ablauf_roh": s(&karte, "expiry"),
        "marke": s(&karte, "brand"),
        "standard": p["default"].as_bool().unwrap_or(false),
        "fertig": fertig,
        "fehlgeschlagen": p["failed"].as_bool().unwrap_or(false) || p["verification_failed"].as_bool().unwrap_or(false),
        "hinweis": hinweis,
        "freigabe": s(p, "approve_url"),
        "redirect": s(&karte["redirect"], "initial"),
    })
}

pub fn liste(a: &Ablage, imob: &Imob) -> Result<Value, String> {
    let v = imob.api(a, "GET", "v2/payment_options")?;
    let l: Vec<Value> = v.as_array().into_iter().flatten().map(eintrag).collect();
    Ok(Value::Array(l))
}

fn id_pruefen(id: &str) -> Result<String, String> {
    if id.is_empty() || !id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_') {
        return Err("Ungültiges Zahlungsmittel".into());
    }
    Ok(id.to_string())
}

pub fn status(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = id_pruefen(&s(w, "id"))?;
    Ok(eintrag(&imob.api(a, "GET", &format!("v2/payment_options/{}", id))?))
}

pub fn standard(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = id_pruefen(&s(w, "id"))?;
    imob.api_mit(a, "PATCH", &format!("v2/payment_options/{}", id), Some(&json!({"default": true})))?;
    liste(a, imob)
}

pub fn loeschen(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = id_pruefen(&s(w, "id"))?;
    imob.api(a, "DELETE", &format!("v2/payment_options/{}", id))?;
    liste(a, imob)
}

fn quelle(w: &Value) -> String {
    let q = s(w, "quelle");
    if q.starts_with("flow/") && q[5..].chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
        q
    } else {
        "profile".into()
    }
}

/// Marke wie die App: Visa, Mastercard, sonst UNKNOWN.
fn marke(nummer: &str) -> &'static str {
    // ^4[0-9]{12}(?:[0-9]{0,7})?$ und ^5[1-5][0-9]{12,19}$
    let n = nummer.len();
    let b = nummer.as_bytes();
    if n >= 13 && n <= 20 && b[0] == b'4' {
        "VISA"
    } else if n >= 14 && n <= 21 && b[0] == b'5' && (b'1'..=b'5').contains(&b[1]) {
        "MASTERCARD"
    } else {
        "UNKNOWN"
    }
}

/// "12/27", "1227", "12 / 2027" -> "2712"
fn ablauf_jjmm(t: &str) -> Option<String> {
    let z: String = t.chars().filter(|c| c.is_ascii_digit()).collect();
    let (mm, jj) = match z.len() {
        4 => (&z[0..2], &z[2..4]),
        6 => (&z[0..2], &z[4..6]),
        _ => return None,
    };
    let m: u32 = mm.parse().ok()?;
    if !(1..=12).contains(&m) {
        return None;
    }
    Some(format!("{}{}", jj, mm))
}

/// Kreditkarte anlegen: {nummer, ablauf, cvc, quelle?} -> Zahlungsmittel
/// (mit "redirect", falls 3-D Secure noetig ist).
pub fn karte_anlegen(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let nummer: String = s(w, "nummer").chars().filter(|c| c.is_ascii_digit()).collect();
    if nummer.len() < 12 || nummer.len() > 19 {
        return Err("Die Kartennummer ist zu kurz oder zu lang.".into());
    }
    let ablauf = ablauf_jjmm(&s(w, "ablauf")).ok_or("Ablaufdatum bitte als MM/JJ.")?;
    let cvc: String = s(w, "cvc").chars().filter(|c| c.is_ascii_digit()).collect();
    if cvc.len() < 3 || cvc.len() > 4 {
        return Err("Die Prüfnummer (CVC) hat 3 oder 4 Ziffern.".into());
    }

    // 1. Zahlungsmittel anlegen
    let (status, v, ort) = imob.api_roh(a, "POST", "v2/payment_options", Some(&json!({
        "source": quelle(w), "set_default": false, "set_fallback": false, "payment_type": "credit_card"
    })))?;
    if status >= 300 && status != 303 {
        return Err(serverfehler(status, &v));
    }
    let ort = ort.ok_or("Der Server hat keine Adresse für das neue Zahlungsmittel geliefert.")?;
    let ort = if ort.starts_with('/') { format!("{}{}", BASIS, &ort[1..]) } else { ort };
    if !ort.starts_with(BASIS) {
        return Err("Fremde Adresse abgelehnt.".into());
    }
    let api_key = s(&v["credit_card"], "api_key");
    if api_key.is_empty() {
        return Err("Der Server hat keinen Schlüssel für mpay24 geliefert.".into());
    }

    // 2. Karte bei mpay24 hinterlegen -- nur hier gehen die Kartendaten hin
    let karte = json!({"brand": marke(&nummer), "identifier": nummer, "expiry": ablauf, "cvc": cvc});
    let kopf = vec![("Api-Key".to_string(), api_key)];
    let antwort = imob.netz().senden("POST", MPAY24, &kopf, Rumpf::Json(&karte), true)?;
    drop(karte);
    let mp = antwort.json().unwrap_or(Value::Null);
    if antwort.status >= 300 {
        if s(&mp, "expiry").is_empty() && mp.get("expiry").is_some() {
            return Err("Die Karte ist abgelaufen.".into());
        }
        if s(&mp, "identifier").is_empty() && mp.get("identifier").is_some() {
            return Err("Diese Karte kennt mpay24 nicht (nur Visa und Mastercard).".into());
        }
        return Err(format!("mpay24 hat die Karte abgelehnt (HTTP {}).", antwort.status));
    }

    // 3. Ergebnis an wegfinder
    let p = imob.api_mit(a, "PATCH", &ort, Some(&json!({"credit_card": mp})))?;
    Ok(eintrag(&p))
}

/// PayPal anlegen -> {id, freigabe: approve_url}
pub fn paypal_anlegen(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let (status, v, _) = imob.api_roh(a, "POST", "v2/payment_options", Some(&json!({
        "source": quelle(w), "set_default": false, "set_fallback": false, "payment_type": "paypal"
    })))?;
    if status >= 300 {
        return Err(serverfehler(status, &v));
    }
    Ok(eintrag(&v))
}

/// Nach der Freigabe im Browser.
pub fn paypal_fertig(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = id_pruefen(&s(w, "id"))?;
    let p = imob.api_mit(a, "PATCH", &format!("v2/payment_options/{}", id), Some(&json!({"payment_type": "paypal"})))?;
    Ok(eintrag(&p))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn marken_und_ablauf() {
        assert_eq!(marke("4111111111111111"), "VISA");
        assert_eq!(marke("5555555555554444"), "MASTERCARD");
        assert_eq!(marke("378282246310005"), "UNKNOWN");
        assert_eq!(ablauf_jjmm("12/27").as_deref(), Some("2712"));
        assert_eq!(ablauf_jjmm("03 / 2029").as_deref(), Some("2903"));
        assert_eq!(ablauf_jjmm("13/27"), None);
    }
}
