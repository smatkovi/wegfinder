//! Gekaufte Tickets: Liste, Barcode, PDF -- auch ohne Netz.
//!
//! So macht es die Android-App (befund-tickets.md):
//! * `GET v4/tickets` -> `{payment_options, tickets: [Ticket]}`, nur Metadaten.
//! * Der Barcode steckt in den Buchungsdetails (`booking_details_url`):
//!   `partner|aggregator|group` -> `ticket_preview.groups[].tickets[]`, je
//!   Eintrag `barcode` = fertiges Bild als Base64. Kein Rendern auf dem
//!   Geraet, keine wechselnden Codes.
//! * Fuer gueltige Tickets haelt die App Details und PDF vor und zeigt sie bei
//!   Netzfehlern aus dem Speicher.
//!
//! Hier genauso: Liste und Details liegen unter
//! ~/.local/share/<ordner>/tickets/, die Barcodes als Bilddateien daneben.

use crate::ablage::Ablage;
use crate::format::s;
use crate::imob::{Imob, BASIS};
use crate::{protokoll, zeit};
use serde_json::{json, Map, Value};
use std::path::PathBuf;

fn ordner(a: &Ablage) -> PathBuf {
    a.daten.join("tickets")
}

/// Text des Servers: Zeichenkette oder {"text"} | {"markdown"} | {"styled": {text}}.
pub fn text(v: &Value) -> String {
    match v {
        Value::String(t) => t.clone(),
        Value::Object(o) => {
            if let Some(t) = o.get("text").and_then(|x| x.as_str()) {
                return t.to_string();
            }
            if let Some(t) = o.get("markdown").and_then(|x| x.as_str()) {
                return t.replace("**", "").replace("__", "");
            }
            if let Some(st) = o.get("styled") {
                return s(st, "text").replace("**", "");
            }
            String::new()
        }
        _ => String::new(),
    }
}

fn base64(t: &str) -> Option<Vec<u8>> {
    const A: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let t = t.trim();
    let t = match t.find("base64,") {
        Some(i) if t.starts_with("data:") => &t[i + 7..],
        _ => t,
    };
    let mut aus = Vec::with_capacity(t.len() * 3 / 4);
    let (mut puffer, mut bits) = (0u32, 0);
    for c in t.bytes() {
        if c == b'=' || c.is_ascii_whitespace() {
            continue;
        }
        let c = if c == b'-' { b'+' } else if c == b'_' { b'/' } else { c };
        let w = A.iter().position(|&x| x == c)? as u32;
        puffer = (puffer << 6) | w;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            aus.push((puffer >> bits) as u8);
            puffer &= (1 << bits) - 1;
        }
    }
    Some(aus)
}

/// Bildart aus den ersten Bytes
fn endung(b: &[u8]) -> &'static str {
    if b.starts_with(b"\x89PNG") {
        "png"
    } else if b.starts_with(&[0xff, 0xd8]) {
        "jpg"
    } else if b.starts_with(b"GIF8") {
        "gif"
    } else if b.starts_with(b"RIFF") && b.len() > 12 && &b[8..12] == b"WEBP" {
        "webp"
    } else {
        "svg"
    }
}

fn zeitpunkt(v: &Value, k: &str) -> i64 {
    v.get(k).and_then(|x| x.as_str()).and_then(zeit::iso_lesen).unwrap_or(0)
}

/// Ein Ticket der Liste fuer die Oberflaeche.
fn eintrag(t: &Value) -> Value {
    let gueltig = t.get("validity").cloned().unwrap_or(Value::Null);
    let datum = t.get("date").cloned().unwrap_or(Value::Null);
    let zustand = t.get("state").cloned().unwrap_or(Value::Null);
    let felder: Vec<String> = t["fields"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|f| text(&f["text"]))
        .filter(|x| !x.is_empty())
        .collect();
    let bilder: Vec<String> = t["images"].as_array().into_iter().flatten().map(|b| s(b, "url")).collect();
    json!({
        "id": s(t, "id"),
        "typ": s(t, "type"),
        "status": s(t, "status"),
        "name": text(t.get("name").unwrap_or(&Value::Null)),
        "preis": text(t.get("price").unwrap_or(&Value::Null)),
        "email": s(t, "email"),
        "von": zeitpunkt(&gueltig, "from").max(0),
        "bis": zeitpunkt(&gueltig, "to"),
        "gueltig_text": s(&gueltig, "subtitle"),
        "datum_von": zeitpunkt(&datum, "from"),
        "datum_bis": zeitpunkt(&datum, "to"),
        "zustand": text(zustand.get("text").unwrap_or(&Value::Null)),
        "zustand_farbe": s(&zustand, "color_set"),
        "felder": felder,
        "bilder": bilder,
        "pdf": !s(t, "pdf_url").is_empty(),
        "details": !s(t, "booking_details_url").is_empty(),
    })
}

/// Liste der Tickets; ohne Netz die zuletzt geladene.
pub fn liste(a: &Ablage, imob: &Imob) -> Result<Value, String> {
    let datei = ordner(a).join("liste.json");
    let (roh, offline, fehler) = match imob.api(a, "GET", "v4/tickets") {
        Ok(v) => {
            let _ = std::fs::create_dir_all(ordner(a));
            let _ = a.schreiben_geheim(&datei, &v);
            (v, false, String::new())
        }
        Err(e) => match a.lesen(&datei) {
            Some(v) => (v, true, e),
            None => return Err(e),
        },
    };
    let mut tickets: Vec<Value> = roh["tickets"].as_array().into_iter().flatten().map(eintrag).collect();
    // gueltige zuerst, dann nach Beginn absteigend
    tickets.sort_by_key(|t| {
        let aktiv = matches!(t["status"].as_str(), Some("active") | Some("current"));
        (if aktiv { 0 } else { 1 }, -t["von"].as_i64().unwrap_or(0))
    });
    Ok(json!({"tickets": tickets, "offline": offline, "fehler": fehler}))
}

fn roh_ticket(a: &Ablage, id: &str) -> Option<Value> {
    let l = a.lesen(&ordner(a).join("liste.json"))?;
    l["tickets"].as_array()?.iter().find(|t| s(t, "id") == id).cloned()
}

/// GET auf eine Adresse des Servers; auf dem API-Rechner mit Anmeldung.
fn holen(a: &Ablage, imob: &Imob, url: &str) -> Result<Value, String> {
    if url.starts_with(BASIS) {
        imob.api(a, "GET", url)
    } else if url.starts_with("https://") {
        imob.ohne_anmeldung(url)
    } else {
        Err("Ungültige Adresse".into())
    }
}

/// Barcodes und Angaben eines Tickets (Buchungsdetails), mit Bilddateien.
pub fn details(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = s(w, "id");
    let t = roh_ticket(a, &id).ok_or("Ticket nicht gefunden – bitte Liste neu laden.")?;
    let url = s(&t, "booking_details_url");
    if url.is_empty() {
        return Err("Zu diesem Ticket gibt es keine Detailansicht (nur PDF).".into());
    }
    let sicher = id.chars().filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_').collect::<String>();
    let datei = ordner(a).join(format!("{}.json", sicher));
    let (roh, offline) = match holen(a, imob, &url) {
        Ok(v) => {
            let _ = a.schreiben_geheim(&datei, &v);
            (v, false)
        }
        Err(e) => match a.lesen(&datei) {
            Some(v) => {
                protokoll(&format!("tickets: {} aus dem Speicher ({})", sicher, e));
                (v, true)
            }
            None => return Err(e),
        },
    };
    let blip = ["partner", "aggregator", "group"].iter().find_map(|k| roh.get(*k)).cloned().unwrap_or(roh.clone());
    let vorschau = blip.get("ticket_preview").cloned().unwrap_or(Value::Null);
    let mut aus = Vec::new();
    let mut n = 0;
    for g in vorschau["groups"].as_array().into_iter().flatten() {
        let gruppe_route = text(g.get("route_info").unwrap_or(&Value::Null));
        for e in g["tickets"].as_array().into_iter().flatten() {
            let mut bild = String::new();
            if let Some(b64) = e.get("barcode").and_then(|x| x.as_str()) {
                if let Some(b) = base64(b64) {
                    let pfad = ordner(a).join(format!("{}-{}.{}", sicher, n, endung(&b)));
                    if std::fs::write(&pfad, &b).is_ok() {
                        bild = pfad.to_string_lossy().into_owned();
                    }
                }
            }
            let gueltig = e.get("validity").cloned().unwrap_or(Value::Null);
            let mut o = Map::new();
            o.insert("titel".into(), json!(text(e.get("title").unwrap_or(&Value::Null))));
            o.insert("bild".into(), json!(bild));
            o.insert("abgelaufen".into(), json!(e["expired"].as_bool().unwrap_or(false)));
            o.insert("storniert".into(), json!(e["cancelled"].as_bool().unwrap_or(false)));
            let r = text(e.get("route_info").unwrap_or(&Value::Null));
            o.insert("route".into(), json!(if r.is_empty() { gruppe_route.clone() } else { r }));
            o.insert("von".into(), json!(zeitpunkt(&gueltig, "from")));
            o.insert("bis".into(), json!(zeitpunkt(&gueltig, "to")));
            aus.push(Value::Object(o));
            n += 1;
        }
    }
    Ok(json!({"ticket": eintrag(&t), "eintraege": aus, "offline": offline}))
}

/// PDF eines Tickets nach ~/Downloads (Berechtigung "Downloads"), Pfad zurueck.
pub fn pdf(a: &Ablage, imob: &Imob, w: &Value) -> Result<Value, String> {
    let id = s(w, "id");
    let t = roh_ticket(a, &id).ok_or("Ticket nicht gefunden – bitte Liste neu laden.")?;
    let url = s(&t, "pdf_url");
    if url.is_empty() {
        return Err("Zu diesem Ticket gibt es kein PDF.".into());
    }
    let sicher = id.chars().filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_').collect::<String>();
    let heim = std::env::var("HOME").unwrap_or_else(|_| "/home/defaultuser".into());
    let ziel = PathBuf::from(heim).join("Downloads").join(format!("wegfinder-ticket-{}.pdf", sicher));
    let kopie = ordner(a).join(format!("{}.pdf", sicher));
    match imob.roh(a, &url) {
        Ok(b) if b.starts_with(b"%PDF") => {
            let _ = std::fs::write(&kopie, &b);
            std::fs::write(&ziel, &b).map_err(|e| format!("PDF nicht gespeichert: {}", e))?;
        }
        Ok(_) => return Err("Der Server hat kein PDF geliefert.".into()),
        Err(e) => {
            let b = std::fs::read(&kopie).map_err(|_| e)?;
            std::fs::write(&ziel, &b).map_err(|e| format!("PDF nicht gespeichert: {}", e))?;
        }
    }
    Ok(json!({"datei": ziel.to_string_lossy()}))
}
