//! Ticketkauf ueber den Kaufablauf des Servers (v3/flow, befund-konto-flow.md).
//!
//! * `POST v3/flow` mit den Startdaten aus dem Angebot ("Ticket kaufen" in
//!   v3/offers) -> 303 auf `/v3/flow/<id>` -> Flow mit genau einem
//!   Bildschirm: `summary`, `pending`, `success`, `error` (und andere, die
//!   fuer Tickets nicht vorkommen).
//! * Jede Aenderung schickt den ganzen Flow mit dem geaenderten Feld an
//!   `POST v3/flow/{id}` und bekommt ihn neu berechnet zurueck (409: neu
//!   laden). Voraussetzungen (Konto, Name, Zahlungsmittel ...) nimmt der
//!   Server aus `summary.prerequisites`, sobald sie erfuellt sind.
//! * Buchen: `POST v3/flow/{id}/continue` mit dem ganzen Flow -> `pending`,
//!   dann alle 2 s `GET v3/flow/{id}`, bis `success` oder `error`.
//!
//! Der Dienst haelt den Flow im Speicher; die Oberflaeche bekommt eine
//! knappe Ansicht und schickt nur Aenderungswuensche. Gebucht wird nur mit
//! `bestaetigt: true` -- das setzt allein der Bestaetigungsdialog.

use crate::ablage::Ablage;
use crate::format::s;
use crate::imob::{serverfehler, Imob};
use crate::tickets::text;
use crate::{protokoll, zeit};
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::sync::Mutex;

static FLUSS: Mutex<Option<HashMap<String, Value>>> = Mutex::new(None);

fn merken(f: &Value) {
    let id = s(f, "id");
    if id.is_empty() {
        return;
    }
    let mut g = FLUSS.lock().unwrap_or_else(|e| e.into_inner());
    g.get_or_insert_with(HashMap::new).insert(id, f.clone());
}

fn holen(id: &str) -> Result<Value, String> {
    let g = FLUSS.lock().unwrap_or_else(|e| e.into_inner());
    g.as_ref()
        .and_then(|m| m.get(id).cloned())
        .ok_or_else(|| "Der Kauf ist nicht mehr im Speicher – bitte neu beginnen.".to_string())
}

fn id_pruefen(id: &str) -> Result<String, String> {
    if id.is_empty() || !id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_') {
        return Err("Ungültiger Kauf".into());
    }
    Ok(id.to_string())
}

fn texte(v: &Value) -> Vec<String> {
    let mut aus = Vec::new();
    fn sammeln(v: &Value, aus: &mut Vec<String>, tiefe: usize) {
        if tiefe > 6 {
            return;
        }
        match v {
            Value::String(t) if !t.trim().is_empty() => aus.push(t.trim().to_string()),
            Value::Array(a) => a.iter().for_each(|x| sammeln(x, aus, tiefe + 1)),
            Value::Object(o) => {
                let mut gefunden = false;
                for k in ["title", "headline", "text", "message", "description", "subtitle", "markdown"] {
                    if let Some(x) = o.get(k) {
                        let t = text(x);
                        if !t.trim().is_empty() {
                            aus.push(t.trim().to_string());
                            gefunden = true;
                        }
                    }
                }
                if !gefunden {
                    for (k, x) in o {
                        if k != "action" && k != "actions" && k != "tracking_name" {
                            sammeln(x, aus, tiefe + 1);
                        }
                    }
                }
            }
            _ => {}
        }
    }
    sammeln(v, &mut aus, 0);
    aus
}

/// Markdown-Links "[Text](url)" -> "Text", \n wie im Server-Text
fn klartext(t: &str) -> String {
    let mut aus = String::new();
    let mut rest = t.replace("\\n", "\n");
    while let Some(a) = rest.find('[') {
        let (vor, nach) = rest.split_at(a);
        aus.push_str(vor);
        match (nach.find("]("), nach.find(')')) {
            (Some(m), Some(e)) if m < e => {
                aus.push_str(&nach[1..m]);
                rest = nach[e + 1..].to_string();
            }
            _ => {
                aus.push('[');
                rest = nach[1..].to_string();
            }
        }
    }
    aus.push_str(&rest);
    aus.replace("**", "")
}

/// Knappe Ansicht eines Flows fuer die Oberflaeche.
fn ansicht(f: &Value) -> Value {
    let id = s(f, "id");
    let bildschirm = ["summary", "pending", "success", "error", "verify_locked", "active_ride", "damages", "scanner"]
        .iter()
        .find(|k| f.get(**k).map(|x| !x.is_null()).unwrap_or(false))
        .map(|k| k.to_string())
        .unwrap_or_default();
    let mut aus = Map::new();
    aus.insert("id".into(), json!(id));
    aus.insert("bildschirm".into(), json!(bildschirm));

    if let Some(su) = f.get("summary").filter(|x| !x.is_null()) {
        let item = su.get("item").cloned().unwrap_or(Value::Null);
        let mut preis = String::new();
        let angebote: Vec<Value> = item["offers"].as_array().into_iter().flatten().map(|o| {
            let merkmale: Vec<String> = o["features"]["summary"].as_array().into_iter().flatten()
                .map(|x| s(x, "text").trim().to_string()).filter(|x| !x.is_empty()).collect();
            let gewaehlt = o["selected"].as_bool().unwrap_or(false);
            if gewaehlt {
                preis = s(o, "price");
            }
            json!({"id": s(o, "id"), "name": s(o, "name"), "preis": s(o, "price"), "gewaehlt": gewaehlt, "merkmale": merkmale})
        }).collect();
        let mut meldungen = texte(item.get("messages").unwrap_or(&Value::Null));
        meldungen.extend(texte(su.get("messages").unwrap_or(&Value::Null)));
        let voraus: Vec<String> = su["prerequisites"].as_array().into_iter().flatten()
            .filter_map(|x| x.as_str().map(String::from))
            .filter(|x| !["discounts", "push_notifications", "gps", "bluetooth", "confirmations"].contains(&x.as_str()))
            .collect();
        let route = su.get("route").cloned().unwrap_or(Value::Null);
        let uhr = |k: &str| route.get(k).and_then(|x| x.as_str()).and_then(zeit::iso_lesen).map(zeit::uhrzeit).unwrap_or_default();
        let reisende: Vec<Value> = su["passengers"]["default"]["people"].as_array().into_iter().flatten().map(|p| json!({
            "id": s(p, "id"), "vorname": s(p, "first_name"), "nachname": s(p, "last_name"),
            "geburtstag": s(p, "birthday"), "reist": p["travelling"].as_bool().unwrap_or(true),
        })).collect();
        let zahlung = su.get("payment").filter(|x| !x.is_null()).and_then(|p| p.get("primary")).filter(|x| !x.is_null())
            .map(|p| json!({"id": s(p, "id"), "titel": s(p, "title"), "typ": s(p, "type"), "fehler": text(p.get("error").unwrap_or(&Value::Null))}))
            .unwrap_or(Value::Null);
        let bestaetigungen: Vec<Value> = su["confirmation"].as_object().into_iter().flatten().map(|(k, v)| json!({
            "schluessel": k, "text": texte(v).join(" "), "bestaetigt": v["confirmed"].as_bool().unwrap_or(false),
        })).collect();
        aus.insert("summary".into(), json!({
            "titel": s(su, "title"),
            "route": {"von": s(&route, "from"), "nach": s(&route, "to"), "ab": uhr("departure"), "an": uhr("arrival"), "datum": s(&route, "label")},
            "angebote": angebote,
            "preis": preis,
            "meldungen": meldungen,
            "voraussetzungen": voraus,
            "email": s(&su["email"], "value"),
            "email_hinweis": s(&su["email"], "subline"),
            "reisende": reisende,
            "zahlung": zahlung,
            "zahlungsliste": s(&su["payment"], "payment_options"),
            "erlaubt": su.get("allow_payment_types").cloned().unwrap_or(Value::Null),
            "bestaetigungen": bestaetigungen,
            "details": texte(su.get("details").unwrap_or(&Value::Null)),
            "hinweis": klartext(&s(su, "disclaimer")),
            "weiter": s(su, "next_step"),
            "weiter_aktiv": su["next_step_enabled"].as_bool().unwrap_or(false),
            "weiter_warnung": texte(su.get("next_step_warning").unwrap_or(&Value::Null)).join(" "),
        }));
    }
    if let Some(p) = f.get("pending").filter(|x| !x.is_null()) {
        aus.insert("pending".into(), json!({
            "text": texte(p.get("message").unwrap_or(&Value::Null)).join(" "),
            "abgebrochen": p["cancelled"].as_bool().unwrap_or(false),
            "fehler": texte(p.get("error").unwrap_or(&Value::Null)).join(" "),
            "bestellnummer": s(&p["support"], "short_order_id"),
            "hilfe": texte(p.get("support").unwrap_or(&Value::Null)).join(" "),
        }));
    }
    if let Some(p) = f.get("success").filter(|x| !x.is_null()) {
        aus.insert("success".into(), json!({
            "ticket_id": s(p, "ticket_id"),
            "text": texte(p.get("ui").unwrap_or(&Value::Null)).join("\n"),
            "warnung": texte(p.get("warning").unwrap_or(&Value::Null)).join(" "),
        }));
    }
    if let Some(p) = f.get("error").filter(|x| !x.is_null()) {
        let t = texte(p);
        aus.insert("error".into(), json!({
            "titel": t.first().cloned().unwrap_or_else(|| "Fehler".into()),
            "text": t.iter().skip(1).cloned().collect::<Vec<_>>().join("\n"),
        }));
    }
    Value::Object(aus)
}

/// Ganzen Flow an POST v3/flow/{id} (oder .../continue); 409 -> neu laden.
fn senden(a: &Ablage, imob: &Imob, id: &str, flow: &Value, weiter: bool) -> Result<Value, String> {
    let pfad = if weiter { format!("v3/flow/{}/continue", id) } else { format!("v3/flow/{}", id) };
    let (status, v, ort) = imob.api_roh(a, "POST", &pfad, Some(flow))?;
    let neu = if status == 409 {
        protokoll("kauf: 409, lade neu");
        imob.api(a, "GET", &format!("v3/flow/{}", id))?
    } else if (300..400).contains(&status) {
        let ziel = ort.unwrap_or_else(|| format!("/v3/flow/{}", id));
        imob.api(a, "GET", &ziel.trim_start_matches('/').to_string())?
    } else if status >= 400 {
        return Err(serverfehler(status, &v));
    } else {
        v
    };
    merken(&neu);
    Ok(ansicht(&neu))
}

pub fn start(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let daten = w.get("daten").filter(|d| d.is_object()).ok_or("Für diese Route gibt es keinen Ticketkauf.")?;
    let f = imob.api_mit(a, "POST", "v3/flow", Some(daten))?;
    merken(&f);
    Ok(ansicht(&f))
}

pub fn laden(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = id_pruefen(&s(w, "id"))?;
    let f = imob.api(a, "GET", &format!("v3/flow/{}", id))?;
    merken(&f);
    Ok(ansicht(&f))
}

/// Nach erfuellten Voraussetzungen (Konto angelegt, E-Mail bestaetigt) den
/// unveraenderten Flow schicken, wie die App.
pub fn abgleichen(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = id_pruefen(&s(w, "id"))?;
    let f = holen(&id)?;
    senden(a, imob, &id, &f, false)
}

/// Nach dem Anmelden mit einem bestehenden Konto: neuer Flow aus
/// summary.launch_data (so macht es die App).
pub fn neu_starten(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = id_pruefen(&s(w, "id"))?;
    let f = holen(&id)?;
    let daten = f["summary"]["launch_data"].clone();
    if !daten.is_object() {
        return Err("Der Kauf lässt sich nicht neu beginnen.".into());
    }
    let neu = imob.api_mit(a, "POST", "v3/flow", Some(&daten))?;
    merken(&neu);
    Ok(ansicht(&neu))
}

pub fn angebot(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = id_pruefen(&s(w, "id"))?;
    let wahl = s(w, "angebot");
    let mut f = holen(&id)?;
    if let Some(offers) = f["summary"]["item"]["offers"].as_array_mut() {
        if !offers.iter().any(|o| s(o, "id") == wahl) {
            return Err("Dieses Angebot gibt es nicht mehr.".into());
        }
        for o in offers.iter_mut() {
            let gew = s(o, "id") == wahl;
            o["selected"] = json!(gew);
        }
    }
    senden(a, imob, &id, &f, false)
}

/// Zahlungsmittel fuer diesen Kauf: summary.payment.primary (bzw. fallback)
pub fn zahlung(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = id_pruefen(&s(w, "id"))?;
    let z = w.get("zahlungsmittel").ok_or("Zahlungsmittel fehlt")?;
    let mut f = holen(&id)?;
    let eintrag = json!({
        "id": s(z, "id"), "type": s(z, "typ"), "brand": s(z, "marke"), "title": s(z, "titel"),
        "error": Value::Null, "expiry": s(z, "ablauf_roh"), "company": Value::Null, "info": Value::Null,
    });
    let su = f.get_mut("summary").ok_or("Kein Kauf offen")?;
    if su.get("payment").map(|p| p.is_null()).unwrap_or(true) {
        su["payment"] = json!({"fallback_required": false, "failed": false, "alternatives": false, "subtitle": "",
                               "primary": Value::Null, "fallback": Value::Null, "editable": true});
    }
    let feld = if z["ersatz"].as_bool().unwrap_or(false) { "fallback" } else { "primary" };
    su["payment"][feld] = eintrag;
    senden(a, imob, &id, &f, false)
}

/// Name des Kontos und des Reisenden "me"
pub fn name(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = id_pruefen(&s(w, "id"))?;
    let (vor, nach) = (s(w, "vorname").trim().to_string(), s(w, "nachname").trim().to_string());
    if vor.is_empty() || nach.is_empty() {
        return Err("Bitte Vor- und Nachnamen angeben.".into());
    }
    crate::konto::name_setzen(a, imob, &vor, &nach)?;
    let mut f = holen(&id)?;
    if let Some(leute) = f["summary"]["passengers"]["default"]["people"].as_array_mut() {
        for p in leute.iter_mut() {
            if s(p, "id") == "me" {
                p["first_name"] = json!(vor);
                p["last_name"] = json!(nach);
            }
        }
    }
    senden(a, imob, &id, &f, false)
}

pub fn bestaetigen(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = id_pruefen(&s(w, "id"))?;
    let k = s(w, "schluessel");
    let mut f = holen(&id)?;
    match f["summary"]["confirmation"].get_mut(&k) {
        Some(c) if c.is_object() => c["confirmed"] = json!(w["wert"].as_bool().unwrap_or(true)),
        _ => return Err("Unbekannte Bestätigung".into()),
    }
    senden(a, imob, &id, &f, false)
}

/// Kostenpflichtig buchen. Nur mit bestaetigt: true und dem Preis, den der
/// Dialog gezeigt hat -- stimmt er nicht mehr, wird nicht gebucht.
pub fn buchen(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = id_pruefen(&s(w, "id"))?;
    if w["bestaetigt"].as_bool() != Some(true) {
        return Err("Buchung nicht bestätigt.".into());
    }
    let f = holen(&id)?;
    let jetzt = ansicht(&f);
    let preis = jetzt["summary"]["preis"].as_str().unwrap_or("").to_string();
    if preis != s(w, "preis") {
        return Err(format!("Der Preis hat sich geändert ({}). Bitte noch einmal prüfen.", preis));
    }
    if jetzt["summary"]["weiter_aktiv"] != true {
        return Err("Es fehlt noch etwas, bevor gebucht werden kann.".into());
    }
    // Der Server meldet "weiter" auch bei offenen Voraussetzungen als aktiv;
    // die App bucht in dem Zustand nie -- hier ebenso.
    let offen = jetzt["summary"]["voraussetzungen"].as_array().map(|a| a.len()).unwrap_or(0);
    if offen > 0 || jetzt["summary"]["zahlung"].is_null() {
        return Err("Vor dem Buchen fehlt noch etwas (Konto, Name oder Zahlungsmittel).".into());
    }
    protokoll(&format!("kauf: buche {} ({})", id, preis));
    senden(a, imob, &id, &f, true)
}

/// Stand waehrend "pending" (alle 2 s)
pub fn stand(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    laden(a, imob, w)
}

pub fn wiederholen(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = id_pruefen(&s(w, "id"))?;
    let mut f = holen(&id)?;
    if f["pending"].is_object() {
        f["pending"]["error"] = Value::Null;
    }
    senden(a, imob, &id, &f, false)
}

pub fn abbrechen(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = id_pruefen(&s(w, "id"))?;
    let mut f = holen(&id)?;
    if f["pending"].is_object() {
        f["pending"]["cancelled"] = json!(true);
        return senden(a, imob, &id, &f, false);
    }
    imob.api(a, "DELETE", &format!("v3/flow/{}", id))?;
    Ok(json!({"id": id, "bildschirm": "abgebrochen"}))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn markdown() {
        assert_eq!(klartext("Alle Preise inkl. USt.\\n\n[Datenschutzerklärung](https://x)."), "Alle Preise inkl. USt.\n\nDatenschutzerklärung.");
    }

    #[test]
    fn ansicht_summary() {
        let f = json!({"id": "1", "summary": {"title": "Ticket", "item": {"offers": [
            {"id": "a", "name": "VOR Einzelfahrt Wien", "price": "3€", "selected": true, "features": {"summary": [{"text": "Für eine Fahrt "}]}},
            {"id": "b", "name": "24 Stunden", "price": "9,70€", "selected": false, "features": {}}]},
            "prerequisites": ["registration", "payment", "discounts"], "next_step": "Kostenpflichtig Buchen", "next_step_enabled": true,
            "payment": null, "confirmation": {}, "disclaimer": "x"}});
        let a = ansicht(&f);
        assert_eq!(a["bildschirm"], "summary");
        assert_eq!(a["summary"]["preis"], "3€");
        assert_eq!(a["summary"]["voraussetzungen"], json!(["registration", "payment"]));
        assert_eq!(a["summary"]["angebote"][0]["merkmale"][0], "Für eine Fahrt");
    }
}
