//! Die Befehle der Oberflaeche. Beschrieben in api.md; jeder Befehl nimmt
//! ein JSON-Objekt und gibt eines zurueck.

use crate::ablage::Ablage;
use crate::format::{self, s};
use crate::imob::{self, Imob};
use crate::{kacheln, orte, polylinie, protokoll, zeit};
use serde_json::{json, Value};
use std::collections::{HashMap, VecDeque};
use std::sync::Mutex;

/// Wie viele Routen fuer die Karte vorgehalten werden (je Suche bis zu 15).
const ROUTEN_MAX: usize = 120;
/// Eine Abfahrtstafel kostet im 2G-Netz einige Sekunden: so lange gilt sie.
const ABFAHRTEN_SEK: i64 = 30;

pub struct Kontext {
    pub ablage: Ablage,
    imob: Imob,
    routen: Mutex<(VecDeque<String>, HashMap<String, Value>)>,
    abfahrten: Mutex<HashMap<String, (i64, Value)>>,
    plattform: String,
}

impl Kontext {
    pub fn neu(ablage: Ablage) -> Kontext {
        let imob = Imob::neu(&ablage);
        Kontext {
            ablage,
            imob,
            routen: Mutex::new((VecDeque::new(), HashMap::new())),
            abfahrten: Mutex::new(HashMap::new()),
            plattform: imob::plattform(),
        }
    }

    pub fn plattform(&self) -> &str {
        &self.plattform
    }

    fn meego(&self) -> bool {
        self.plattform.starts_with("meego")
    }

    fn api(&self, pfad: &str) -> Result<Value, String> {
        self.imob.api(&self.ablage, "GET", pfad)
    }

    /// Haelt die Rohdaten der Routen fuer die Karte vor.
    fn routen_merken(&self, v: &Value) {
        let mut g = self.routen.lock().unwrap_or_else(|e| e.into_inner());
        for gruppe in v["transportation_groups"].as_array().into_iter().flatten() {
            for r in gruppe["routes"].as_array().into_iter().flatten() {
                let id = s(r, "id");
                if id.is_empty() {
                    continue;
                }
                let roh = json!({"map_markers": r["map_markers"], "sections": r["sections"]});
                if g.1.insert(id.clone(), roh).is_none() {
                    g.0.push_back(id);
                }
            }
        }
        while g.0.len() > ROUTEN_MAX {
            if let Some(alt) = g.0.pop_front() {
                g.1.remove(&alt);
            }
        }
    }

    fn einstellungen(&self) -> Value {
        let mut v = self.ablage.lesen(&self.ablage.einstellungen()).unwrap_or_else(|| json!({}));
        // Am N9 ist das Netz oft 2G: dort sparsam voreingestellt.
        let (weitere, karte) = if self.meego() { ("wlan", "sparsam") } else { ("immer", "voll") };
        if !v["weitere_laden"].is_string() {
            v["weitere_laden"] = json!(weitere);
        }
        if !v["karte_mobil"].is_string() {
            v["karte_mobil"] = json!(karte);
        }
        if !v["umgebung_filter"].is_string() {
            v["umgebung_filter"] = json!("public");
        }
        if !v["abfahrten_max"].is_i64() {
            v["abfahrten_max"] = json!(if self.meego() { 30 } else { 60 });
        }
        v
    }
}

/// Haengt am Netz ein WLAN? Dann darf mehr geladen werden.
fn wlan() -> bool {
    let lesen = |p: String| std::fs::read_to_string(p).map(|t| t.trim().to_string()).unwrap_or_default();
    if let Ok(it) = std::fs::read_dir("/sys/class/net") {
        for e in it.flatten() {
            let name = e.file_name().to_string_lossy().into_owned();
            if !name.starts_with("wlan") && !name.starts_with("wl") {
                continue;
            }
            let zustand = lesen(format!("/sys/class/net/{}/operstate", name));
            let traeger = lesen(format!("/sys/class/net/{}/carrier", name));
            if zustand == "up" || (zustand == "unknown" && traeger == "1") {
                return true;
            }
        }
    }
    false
}

fn enc(t: &str) -> String {
    url::form_urlencoded::byte_serialize(t.as_bytes()).collect()
}

/// Start/Ziel als Abfrageteil: Kennung des Servers oder Koordinate.
fn ort_param(o: &Value, wer: &str) -> Result<String, String> {
    let id = s(o, "id");
    let typ = s(o, "typ");
    if !id.is_empty() && typ != "standort" && typ != "koordinate" {
        return Ok(format!("{}_location_id={}", wer, enc(&id)));
    }
    match (o["lat"].as_f64(), o["lon"].as_f64()) {
        (Some(lat), Some(lon)) if lat != 0.0 || lon != 0.0 => {
            Ok(format!("{w}_latitude={:.6}&{w}_longitude={:.6}", lat, lon, w = wer))
        }
        _ => Err(format!("{} ohne Ort", if wer == "start" { "Start" } else { "Ziel" })),
    }
}

fn routen(k: &Kontext, w: &Value) -> Result<Value, String> {
    let von = ort_param(&w["von"], "start")?;
    let nach = ort_param(&w["nach"], "destination")?;
    let wann = match (w["datum"].as_str(), w["zeit"].as_str()) {
        (Some(d), Some(z)) if !d.is_empty() && !z.is_empty() => {
            zeit::wien_lesen(d, z).ok_or("Ungültige Zeit")?
        }
        _ => zeit::jetzt_utc(),
    };
    let feld = if w["ankunft"].as_bool().unwrap_or(false) { "arrival" } else { "departure" };
    let pfad = format!("v3/routes?{}&{}&{}={}&old_groups=false", von, nach, feld, enc(&zeit::iso_utc(wann)));
    let v = k.api(&pfad)?;
    k.routen_merken(&v);
    Ok(format::routen(&v))
}

fn routen_url(k: &Kontext, w: &Value) -> Result<Value, String> {
    let url = s(w, "url");
    if !url.starts_with(imob::BASIS) || !url.contains("/routes") {
        return Err("Ungültige Adresse".into());
    }
    let v = k.api(&url)?;
    k.routen_merken(&v);
    Ok(format::routen(&v))
}

/// Preise einer Routenantwort (deren preise_url, v3/offers).
fn preise(k: &Kontext, w: &Value) -> Result<Value, String> {
    let url = s(w, "url");
    if !url.starts_with(imob::BASIS) || !url.contains("/offers") {
        return Err("Ungültige Adresse".into());
    }
    let v = k.api(&url)?;
    Ok(format::preise(&v))
}

fn punkte_json(p: &[(f64, f64)]) -> Value {
    Value::Array(p.iter().map(|(a, b)| json!([(a * 1e5).round() / 1e5, (b * 1e5).round() / 1e5])).collect())
}

/// Linien und Marker einer Route fuer die Karte.
fn karte(k: &Kontext, w: &Value) -> Result<Value, String> {
    let id = s(w, "route");
    let max = w["max"].as_u64().unwrap_or(if k.meego() { 500 } else { 2000 }) as usize;
    let roh = {
        let g = k.routen.lock().unwrap_or_else(|e| e.into_inner());
        g.1.get(&id).cloned()
    }
    .ok_or("Route nicht mehr im Speicher – bitte neu suchen.")?;

    let mut linien_roh = Vec::new();
    let mut farben = Vec::new();
    for m in roh["map_markers"].as_array().into_iter().flatten() {
        let pl = s(m, "polyline");
        if pl.is_empty() {
            continue;
        }
        let ty: Vec<String> = m["type"].as_array().into_iter().flatten().filter_map(|x| x.as_str().map(String::from)).collect();
        let (art, farbe, _, _) = format::art(&ty);
        linien_roh.push(polylinie::lesen(&pl));
        farben.push((art, farbe));
    }
    let abschnitte: Vec<Value> = roh["sections"].as_array().cloned().unwrap_or_default();
    // Ohne Linienzug (kommt vor): gerade Linien zwischen den Halten.
    if linien_roh.is_empty() {
        for a in &abschnitte {
            let ty: Vec<String> = a["type"].as_array().into_iter().flatten().filter_map(|x| x.as_str().map(String::from)).collect();
            let (art, farbe, _, _) = format::art(&ty);
            let p: Vec<(f64, f64)> = a["stops"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|h| format::koordinate(&h["location"]["coordinate"]))
                .filter(|(la, lo)| *la != 0.0 || *lo != 0.0)
                .collect();
            if p.len() >= 2 {
                linien_roh.push(p);
                farben.push((art, farbe));
            }
        }
    }
    let linien = polylinie::auf_hoechstens(&linien_roh, max);

    let mut marker = Vec::new();
    for (i, a) in abschnitte.iter().enumerate() {
        let halte = a["stops"].as_array().cloned().unwrap_or_default();
        let ty: Vec<String> = a["type"].as_array().into_iter().flatten().filter_map(|x| x.as_str().map(String::from)).collect();
        let (art, farbe, _, _) = format::art(&ty);
        for (j, h) in halte.iter().enumerate() {
            let (lat, lon) = format::koordinate(&h["location"]["coordinate"]);
            if lat == 0.0 && lon == 0.0 {
                continue;
            }
            let rolle = if i == 0 && j == 0 {
                "start"
            } else if i == abschnitte.len() - 1 && j == halte.len() - 1 {
                "ziel"
            } else if j == 0 {
                "umstieg"
            } else if j < halte.len() - 1 && art != "fuss" {
                "halt"
            } else {
                continue;
            };
            marker.push(json!({"lat": lat, "lon": lon, "name": s(&h["location"], "name"), "rolle": rolle, "farbe": farbe}));
        }
    }
    let (mut n, mut sd, mut wd, mut o) = (-90.0f64, 90.0f64, 180.0f64, -180.0f64);
    for p in linien.iter().flatten() {
        n = n.max(p.0);
        sd = sd.min(p.0);
        o = o.max(p.1);
        wd = wd.min(p.1);
    }
    for m in &marker {
        let (la, lo) = (m["lat"].as_f64().unwrap_or(0.0), m["lon"].as_f64().unwrap_or(0.0));
        n = n.max(la);
        sd = sd.min(la);
        o = o.max(lo);
        wd = wd.min(lo);
    }
    let linien_json: Vec<Value> = linien
        .iter()
        .zip(farben.iter())
        .map(|(p, (art, farbe))| json!({"art": art, "farbe": farbe, "punkte": punkte_json(p)}))
        .collect();
    Ok(json!({"linien": linien_json, "marker": marker, "rahmen": {"n": n, "s": sd, "w": wd, "o": o}}))
}

fn abfahrten(k: &Kontext, w: &Value) -> Result<Value, String> {
    let station = s(w, "station");
    if station.is_empty() {
        return Err("Keine Station".into());
    }
    let max = w["max"].as_u64().map(|x| x as usize).unwrap_or_else(|| {
        k.einstellungen()["abfahrten_max"].as_u64().unwrap_or(40) as usize
    });
    let jetzt = zeit::jetzt_utc();
    let neu = w["neu"].as_bool().unwrap_or(false);
    let zwischen = {
        let g = k.abfahrten.lock().unwrap_or_else(|e| e.into_inner());
        g.get(&station).filter(|(t, _)| neu == false && jetzt - *t < ABFAHRTEN_SEK).map(|(_, v)| v.clone())
    };
    let roh = match zwischen {
        Some(v) => v,
        None => {
            let v = k.api(&format!("routing/api/v2/departures?stations={}&include_previous_stops=false", enc(&station)))?;
            let mut g = k.abfahrten.lock().unwrap_or_else(|e| e.into_inner());
            g.retain(|_, (t, _)| jetzt - *t < 600);
            g.insert(station.clone(), (jetzt, v.clone()));
            v
        }
    };
    let mut aus = format::abfahrten(&roh, max);
    aus["station"] = json!(station);
    aus["stand"] = json!(zeit::uhrzeit(jetzt));
    Ok(aus)
}

fn fahrt(k: &Kontext, w: &Value) -> Result<Value, String> {
    let url = s(w, "url");
    if !url.starts_with(imob::BASIS) {
        return Err("Ungültige Adresse".into());
    }
    let v = k.api(&url)?;
    let mut aus = format::fahrt(&v);
    let pl = s(&v, "polyline");
    let max = if k.meego() { 300 } else { 1500 };
    let punkte = if pl.is_empty() {
        aus["halte"].as_array().into_iter().flatten()
            .map(|h| (h["lat"].as_f64().unwrap_or(0.0), h["lon"].as_f64().unwrap_or(0.0)))
            .filter(|(a, b)| *a != 0.0 || *b != 0.0)
            .collect()
    } else {
        polylinie::lesen(&pl)
    };
    let linie = polylinie::auf_hoechstens(&[punkte], max).pop().unwrap_or_default();
    aus["linie"] = punkte_json(&linie);
    Ok(aus)
}

fn umgebung(k: &Kontext, w: &Value) -> Result<Value, String> {
    let g = |n: &str| w[n].as_f64().ok_or(format!("{} fehlt", n));
    let (n, sd, wd, o) = (g("n")?, g("s")?, g("w")?, g("o")?);
    let zoom = w["zoom"].as_i64().unwrap_or(16).clamp(3, 20);
    let span = (o - wd).abs();
    // Wie die App: Genauigkeit nach Breite des Ausschnitts, ab 0,17 Grad keine.
    let genau = match span {
        x if x <= 0.005 => Some(3),
        x if x <= 0.009 => Some(4),
        x if x <= 0.068 => Some(5),
        x if x <= 0.13 => Some(6),
        x if x <= 0.17 => Some(7),
        _ => None,
    };
    let (mlat, mlon) = ((n + sd) / 2.0, (wd + o) / 2.0);
    let mut pfad = format!(
        "v7/radar?bbox={:.6},{:.6},{:.6},{:.6}&zoom={}&filter={}&location={:.6},{:.6}&map_width={}&map_height={}",
        wd, n, o, sd, zoom, enc(&s(w, "filter")), mlon, mlat,
        w["breite"].as_i64().unwrap_or(360), w["hoehe"].as_i64().unwrap_or(640)
    );
    if let Some(p) = genau {
        pfad.push_str(&format!("&precision={}", p));
    }
    let v = k.api(&pfad)?;
    let mut aus = format::umgebung(&v);
    // Nur die naechsten Punkte: in der Wiener Innenstadt meldet der Server
    // leicht 300 (Scooter!), das ist am N9 zu viel fuer die Karte.
    let max = w["max"].as_u64().unwrap_or(if k.meego() { 80 } else { 200 }) as usize;
    if let Some(p) = aus["punkte"].as_array_mut() {
        let k_lon = mlat.to_radians().cos();
        let abstand = |x: &Value| {
            let dy = x["lat"].as_f64().unwrap_or(0.0) - mlat;
            let dx = (x["lon"].as_f64().unwrap_or(0.0) - mlon) * k_lon;
            // Haltestellen zaehlen naeher: sie sollen nicht hinter Scootern verschwinden
            let f = if x["punktart"] == "station" { 0.5 } else { 1.0 };
            (dx * dx + dy * dy).sqrt() * f
        };
        let gesamt = p.len();
        p.sort_by(|a, b| abstand(a).partial_cmp(&abstand(b)).unwrap_or(std::cmp::Ordering::Equal));
        p.truncate(max);
        aus["gesamt"] = json!(gesamt);
    }
    Ok(aus)
}

fn filter(k: &Kontext) -> Result<Value, String> {
    let datei = k.ablage.filter();
    let alt = std::fs::metadata(&datei)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.elapsed().ok())
        .map(|d| d.as_secs() < 86400)
        .unwrap_or(false);
    if alt {
        if let Some(v) = k.ablage.lesen(&datei) {
            return Ok(format::filterliste(&v));
        }
    }
    match k.api("v2/filters") {
        Ok(v) => {
            let _ = k.ablage.schreiben(&datei, &v);
            Ok(format::filterliste(&v))
        }
        Err(e) => match k.ablage.lesen(&datei) {
            Some(v) => Ok(format::filterliste(&v)),
            None => Err(e),
        },
    }
}

fn suche(k: &Kontext, w: &Value) -> Result<Value, String> {
    let text = s(w, "text");
    if text.trim().chars().count() < 2 {
        return Ok(json!([]));
    }
    let mut pfad = format!("v1/locations/search?query={}", enc(text.trim()));
    if let (Some(lat), Some(lon)) = (w["lat"].as_f64(), w["lon"].as_f64()) {
        if lat != 0.0 || lon != 0.0 {
            pfad.push_str(&format!("&latitude={:.5}&longitude={:.5}", lat, lon));
        }
    }
    let v = k.api(&pfad)?;
    let liste: Vec<Value> = v
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|e| e.get("location"))
        .map(format::ort)
        .collect();
    Ok(Value::Array(liste))
}

pub fn bearbeiten(k: &Kontext, befehl: &str, w: &Value) -> Result<Value, String> {
    match befehl {
        "start" => Ok(json!({
            "version": env!("CARGO_PKG_VERSION"),
            "plattform": k.plattform,
            "einstellungen": k.einstellungen(),
            "wlan": wlan(),
        })),
        "netz" => Ok(json!({"wlan": wlan()})),
        "suche" => suche(k, w),
        "routen" => routen(k, w),
        "routen_url" => routen_url(k, w),
        "karte" => karte(k, w),
        "preise" => preise(k, w),
        "abfahrten" => abfahrten(k, w),
        "fahrt" => fahrt(k, w),
        "umgebung" => umgebung(k, w),
        "filter" => filter(k),
        "orte" => Ok(orte::alle(&k.ablage)),
        "ort_merken" => orte::merken(&k.ablage, w),
        "ort_entfernen" => orte::entfernen(&k.ablage, w),
        "verbindung_merken" => orte::verbindung_merken(&k.ablage, w),
        "verlauf_leeren" => orte::verlauf_leeren(&k.ablage),
        "einstellungen" => Ok(k.einstellungen()),
        "einstellungen_setzen" => {
            let mut v = k.einstellungen();
            if let Some(o) = w.as_object() {
                for (sl, wert) in o {
                    v[sl] = wert.clone();
                }
            }
            k.ablage.schreiben(&k.ablage.einstellungen(), &v).map_err(|e| e.to_string())?;
            Ok(v)
        }
        "kacheln" => Ok(json!({"port": kacheln::port(k.ablage.kacheln(), k.imob.netz())?})),
        "speicher" => {
            let b = kacheln::groesse(&k.ablage.kacheln());
            let text = if b < 1048576 {
                format!("{} KB", (b + 1023) / 1024)
            } else {
                format!("{:.1} MB", b as f64 / 1048576.0).replace('.', ",")
            };
            Ok(json!({"kacheln": b, "text": text}))
        }
        "kacheln_leeren" => {
            let _ = std::fs::remove_dir_all(k.ablage.kacheln());
            protokoll("kacheln: Zwischenspeicher geleert");
            Ok(json!({"kacheln": 0, "text": "0 KB"}))
        }
        _ => Err(format!("Unbekannter Befehl: {}", befehl)),
    }
}
