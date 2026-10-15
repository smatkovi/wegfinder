//! Favoriten, zuletzt benutzte Orte und Verbindungen -- nur auf dem Geraet
//! (~/.local/share/wegfinder/orte.json). Die Android-App hebt Favoriten am
//! Server auf, dafuer braucht sie ein Konto; hier geht es ohne.

use crate::ablage::Ablage;
use serde_json::{json, Value};
use std::sync::Mutex;

const VERLAUF_MAX: usize = 20;
const VERBINDUNGEN_MAX: usize = 8;

static SCHLOSS: Mutex<()> = Mutex::new(());

fn laden(a: &Ablage) -> Value {
    let mut v = a.lesen(&a.orte()).unwrap_or_else(|| json!({}));
    for k in ["favoriten", "verlauf", "verbindungen"] {
        if !v.get(k).map(|x| x.is_array()).unwrap_or(false) {
            v[k] = json!([]);
        }
    }
    v
}

/// Gleich ist ein Ort mit derselben Kennung, ohne Kennung (Koordinate) mit
/// demselben Namen an fast derselben Stelle.
fn gleich(a: &Value, b: &Value) -> bool {
    let (ia, ib) = (a["id"].as_str().unwrap_or(""), b["id"].as_str().unwrap_or(""));
    if !ia.is_empty() || !ib.is_empty() {
        return ia == ib;
    }
    let d = |k: &str| (a[k].as_f64().unwrap_or(0.0) - b[k].as_f64().unwrap_or(0.0)).abs();
    a["name"] == b["name"] && d("lat") < 1e-4 && d("lon") < 1e-4
}

/// Nur was die Oberflaeche braucht, um den Ort wieder zu verwenden.
fn schlank(o: &Value) -> Value {
    json!({
        "id": o["id"].as_str().unwrap_or(""),
        "name": o["name"].as_str().unwrap_or(""),
        "unter": o["unter"].as_str().unwrap_or(""),
        "typ": o["typ"].as_str().unwrap_or(""),
        "lat": o["lat"].as_f64().unwrap_or(0.0),
        "lon": o["lon"].as_f64().unwrap_or(0.0),
        "bezeichnung": o["bezeichnung"].as_str().unwrap_or(""),
    })
}

pub fn alle(a: &Ablage) -> Value {
    let _s = SCHLOSS.lock();
    laden(a)
}

/// {ort} -> vorne in den Verlauf; {ort, favorit: true, bezeichnung} ->
/// Favorit (bzw. Bezeichnung aendern).
pub fn merken(a: &Ablage, w: &Value) -> Result<Value, String> {
    let _s = SCHLOSS.lock();
    let ort = w.get("ort").ok_or("Ort fehlt")?;
    if ort["name"].as_str().unwrap_or("").is_empty() {
        return Err("Ort ohne Namen".into());
    }
    if ort["typ"] == "standort" {
        // "Mein Standort" aendert sich staendig: nicht merken.
        return Ok(laden(a));
    }
    let mut v = laden(a);
    let mut neu = schlank(ort);
    let liste = if w["favorit"].as_bool().unwrap_or(false) { "favoriten" } else { "verlauf" };
    if let Some(b) = w.get("bezeichnung").and_then(|x| x.as_str()) {
        neu["bezeichnung"] = json!(b);
    }
    let arr = v[liste].as_array_mut().unwrap();
    if let Some(pos) = arr.iter().position(|x| gleich(x, &neu)) {
        let alt = arr.remove(pos);
        if neu["bezeichnung"] == "" {
            neu["bezeichnung"] = alt["bezeichnung"].clone();
        }
    }
    if liste == "favoriten" {
        arr.push(neu);
    } else {
        arr.insert(0, neu);
        arr.truncate(VERLAUF_MAX);
    }
    a.schreiben(&a.orte(), &v).map_err(|e| e.to_string())?;
    Ok(v)
}

/// {ort, favorit} -> aus Favoriten bzw. Verlauf entfernen.
pub fn entfernen(a: &Ablage, w: &Value) -> Result<Value, String> {
    let _s = SCHLOSS.lock();
    let ort = w.get("ort").ok_or("Ort fehlt")?;
    let liste = if w["favorit"].as_bool().unwrap_or(false) { "favoriten" } else { "verlauf" };
    let mut v = laden(a);
    v[liste].as_array_mut().unwrap().retain(|x| !gleich(x, ort));
    a.schreiben(&a.orte(), &v).map_err(|e| e.to_string())?;
    Ok(v)
}

/// {von, nach} -> vorne in die zuletzt gesuchten Verbindungen.
pub fn verbindung_merken(a: &Ablage, w: &Value) -> Result<Value, String> {
    let _s = SCHLOSS.lock();
    let (von, nach) = match (w.get("von"), w.get("nach")) {
        (Some(v), Some(n)) => (schlank(v), schlank(n)),
        _ => return Err("von/nach fehlt".into()),
    };
    if von["typ"] == "standort" || nach["typ"] == "standort" || von["name"] == "" || nach["name"] == "" {
        return Ok(laden(a));
    }
    let mut v = laden(a);
    let arr = v["verbindungen"].as_array_mut().unwrap();
    arr.retain(|x| !(gleich(&x["von"], &von) && gleich(&x["nach"], &nach)));
    arr.insert(0, json!({"von": von, "nach": nach}));
    arr.truncate(VERBINDUNGEN_MAX);
    a.schreiben(&a.orte(), &v).map_err(|e| e.to_string())?;
    Ok(v)
}

pub fn verlauf_leeren(a: &Ablage) -> Result<Value, String> {
    let _s = SCHLOSS.lock();
    let mut v = laden(a);
    v["verlauf"] = json!([]);
    v["verbindungen"] = json!([]);
    a.schreiben(&a.orte(), &v).map_err(|e| e.to_string())?;
    Ok(v)
}
