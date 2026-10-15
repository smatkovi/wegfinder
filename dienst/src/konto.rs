//! wegfinder-Konto (befund-konto-flow.md): Anmelden mit E-Mail und
//! Kennwort, Konto anlegen, E-Mail bestaetigen, Name, Abmelden. Fuer Routen
//! braucht es keins, zum Ticketkauf verlangt der Server eines.

use crate::ablage::Ablage;
use crate::format::s;
use crate::imob::Imob;
use serde_json::{json, Value};

fn wahr(v: &Value) -> bool {
    match v {
        Value::Bool(b) => *b,
        Value::String(t) => !t.is_empty(),
        Value::Null => false,
        _ => true,
    }
}

/// {angemeldet, email, vorname, nachname, email_offen, konto_typ}
pub fn status(a: &Ablage, imob: &Imob) -> Result<Value, String> {
    let email = imob.konto();
    if email.is_empty() {
        return Ok(json!({"angemeldet": false}));
    }
    match imob.api(a, "GET", "user/api/v1/me") {
        Ok(v) => {
            let d = v.get("data").cloned().unwrap_or(v);
            let typ = s(&d, "account_type");
            if typ == "anonymous" {
                // Server sieht keine Anmeldung mehr
                return Ok(json!({"angemeldet": false}));
            }
            let mail = s(&d, "email");
            Ok(json!({
                "angemeldet": true,
                "email": if mail.is_empty() { email } else { mail },
                "vorname": s(&d, "first_name"),
                "nachname": s(&d, "last_name"),
                "email_offen": wahr(d.get("email_pending_validation").unwrap_or(&Value::Null))
                               || typ == "pending_registration",
                "konto_typ": typ,
            }))
        }
        Err(e) => Ok(json!({"angemeldet": true, "email": email, "offline": true, "fehler": e})),
    }
}

fn zugang(w: &Value) -> Result<(String, String), String> {
    let email = s(w, "email").trim().to_string();
    let kennwort = s(w, "kennwort");
    if !email.contains('@') || kennwort.len() < 6 {
        return Err("Bitte E-Mail und Kennwort (mindestens 6 Zeichen) angeben.".into());
    }
    Ok((email, kennwort))
}

pub fn anmelden(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let (email, kennwort) = zugang(w)?;
    imob.anmelden(a, &email, &kennwort)?;
    status(a, imob)
}

pub fn registrieren(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let (email, kennwort) = zugang(w)?;
    imob.konto_anlegen(a, &email, &kennwort)?;
    status(a, imob)
}

pub fn abmelden(a: &Ablage, imob: &Imob) -> Result<Value, String> {
    imob.abmelden(a);
    Ok(json!({"angemeldet": false}))
}

/// Code aus der Bestaetigungs-E-Mail
pub fn email_code(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let code = s(w, "code").trim().to_string();
    if code.is_empty() {
        return Err("Bitte den Code aus der E-Mail eingeben.".into());
    }
    imob.api_mit(a, "POST", "user/api/v1/me/validate-confirmation", Some(&json!({"code": code})))?;
    // Wie die App: das Token gilt danach als abgelaufen und wird erneuert.
    imob.token_veraltet();
    status(a, imob)
}

pub fn email_code_senden(a: &Ablage, imob: &Imob) -> Result<Value, String> {
    let email = imob.konto();
    imob.api_mit(a, "POST", "user/api/v1/me/request-confirmation", Some(&json!({"email": email, "revalidate": true})))?;
    Ok(json!({"gesendet": true}))
}

pub fn name_setzen(a: &Ablage, imob: &Imob, vorname: &str, nachname: &str) -> Result<(), String> {
    imob.api_mit(a, "PATCH", "user/api/v1/me", Some(&json!({"first_name": vorname, "last_name": nachname})))?;
    Ok(())
}
