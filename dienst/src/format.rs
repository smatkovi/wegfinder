//! Formt die Antworten des Servers in kleine, fertig beschriftete Objekte
//! fuer beide Oberflaechen um. Was hier steht, muss das QML nicht mehr
//! rechnen: Uhrzeiten in Wiener Zeit, Verspaetung in Minuten, Dauer und
//! Strecke als Text, Farbe und Sinnbild je Verkehrsmittel.
//!
//! Die Schluessel sind deutsch und knapp; beschrieben in api.md.

use crate::arten::{ARTEN, GRUPPEN};
use crate::zeit;
use serde_json::{json, Map, Value};

pub fn s(v: &Value, k: &str) -> String {
    match v.get(k) {
        Some(Value::String(t)) => t.clone(),
        Some(Value::Number(n)) => n.to_string(),
        _ => String::new(),
    }
}

fn f(v: &Value, k: &str) -> Option<f64> {
    v.get(k).and_then(|x| x.as_f64())
}

fn liste(v: &Value, k: &str) -> Vec<Value> {
    v.get(k).and_then(|x| x.as_array()).cloned().unwrap_or_default()
}

fn typen(v: &Value) -> Vec<String> {
    match v {
        Value::Array(a) => a.iter().filter_map(|x| x.as_str().map(|s| s.to_string())).collect(),
        Value::String(t) => vec![t.clone()],
        _ => Vec::new(),
    }
}

/// Grobe Art fuers Sinnbild: zug, sbahn, ubahn, tram, bus, schiff,
/// seilbahn, fuss, rad, scooter, auto, taxi, sonst.
pub fn kategorie(typen: &[String]) -> &'static str {
    for t in typen {
        let t = t.as_str();
        let k = match t {
            "public" | "personal" | "shared" | "" => continue,
            "walk" => "fuss",
            "metro" => "ubahn",
            "s_bahn" | "sbahn" | "city_train" => "sbahn",
            "train" | "oebb" | "westbahn" | "regiojet" | "cat" | "cartrain" | "oebb_transfer" => "zug",
            "tram" | "tram_vienna" => "tram",
            "bus" | "city_bus" | "regional_bus" | "express_bus" | "long_distance_bus" | "sev"
            | "cat_bus" | "val" | "postbus" | "digibus" | "dialaride" | "trolleybus" | "obus" => "bus",
            "ship" => "schiff",
            "cable_car" => "seilbahn",
            "escooter" | "escooters" | "escooter_sharing" | "scooter" | "scooter_sharing"
            | "motor_scooters" | "lime" | "dott" | "bird" | "kiwi" => "scooter",
            "bike" | "bike_sharing" | "citybike" | "nextbike" | "wienmobil_rad" => "rad",
            "car" | "car_sharing" | "car_rental" | "rail_and_drive" | "gourban" | "sharenow"
            | "free2move" | "getaround" | "caruso" | "parken_at" | "park_and_ride" | "parking" => "auto",
            "taxi" | "taxi_rank" | "uber" => "taxi",
            _ if t.starts_with("metro_") => "ubahn",
            _ if t.starts_with("taxi") => "taxi",
            _ if t.starts_with("salzburg_obus") => "bus",
            _ if t.contains("bike") || t.contains("rad") => "rad",
            _ => continue,
        };
        return k;
    }
    // Innsbrucker Linien u.a.: ueber die Bezeichnung der Tabelle
    for t in typen.iter().rev() {
        if let Some((_, _, name)) = ARTEN.iter().find(|(id, _, _)| id == t) {
            match *name {
                "Straßenbahn" => return "tram",
                "Bus" | "Obus" | "Rufbus" => return "bus",
                _ => {}
            }
        }
    }
    "sonst"
}

fn standardfarbe(k: &str) -> &'static str {
    match k {
        "fuss" => "#525c69",
        "ubahn" => "#156ab8",
        "sbahn" => "#00aeef",
        "zug" => "#e2002a",
        "tram" => "#467da8",
        "bus" => "#24c2f9",
        "schiff" | "seilbahn" => "#3e466b",
        "rad" => "#1f8970",
        "scooter" => "#07d183",
        "auto" => "#eb7815",
        "taxi" => "#f4a81a",
        _ => "#6d6d6d",
    }
}

/// (Kategorie, Farbe, Bezeichnung, genaueste Kennung) zu einer Typenliste
/// des Servers wie ["public","metro","metro_u3"].
pub fn art(typen: &[String]) -> (&'static str, String, String, String) {
    let k = kategorie(typen);
    let mut farbe = String::new();
    let mut name = String::new();
    let mut genau = String::new();
    for t in typen.iter().rev() {
        if let Some((id, fa, na)) = ARTEN.iter().find(|(id, _, _)| id == t) {
            if farbe.is_empty() {
                farbe = fa.to_string();
                genau = id.to_string();
            }
            if name.is_empty() && !na.is_empty() {
                name = na.to_string();
            }
        }
        if !farbe.is_empty() && !name.is_empty() {
            break;
        }
    }
    if name.is_empty() {
        for t in typen.iter().rev() {
            if let Some((_, g)) = GRUPPEN.iter().find(|(id, _)| id == t) {
                name = g.to_string();
                break;
            }
        }
    }
    if farbe.is_empty() {
        farbe = standardfarbe(k).to_string();
    }
    if genau.is_empty() {
        genau = typen.last().cloned().unwrap_or_default();
    }
    (k, farbe, name, genau)
}

pub fn dauer_text(min: i64) -> String {
    if min < 60 {
        format!("{} min", min.max(0))
    } else if min % 60 == 0 {
        format!("{} h", min / 60)
    } else {
        format!("{} h {} min", min / 60, min % 60)
    }
}

pub fn strecke_text(meter: f64) -> String {
    if meter <= 0.0 {
        String::new()
    } else if meter < 1000.0 {
        format!("{} m", ((meter / 10.0).round() * 10.0) as i64)
    } else if meter < 10_000.0 {
        format!("{:.1} km", meter / 1000.0).replace('.', ",")
    } else {
        format!("{} km", (meter / 1000.0).round() as i64)
    }
}

/// {"planned": iso, "live": iso} -> (geplant, live)
fn zeitpunkt(v: Option<&Value>) -> (Option<i64>, Option<i64>) {
    match v {
        Some(Value::Object(o)) => {
            let p = o.get("planned").and_then(|x| x.as_str()).and_then(zeit::iso_lesen);
            let l = o.get("live").and_then(|x| x.as_str()).and_then(zeit::iso_lesen);
            (p, l)
        }
        Some(Value::String(t)) => (zeit::iso_lesen(t), None),
        _ => (None, None),
    }
}

/// Zeitfelder fuer die Oberflaeche: zeit, live, verspaetung, echtzeit.
fn zeitfelder(o: &mut Map<String, Value>, geplant: Option<i64>, live: Option<i64>) {
    let g = geplant.or(live);
    o.insert("zeit".into(), json!(g.map(zeit::uhrzeit).unwrap_or_default()));
    o.insert("tag".into(), json!(g.map(zeit::tag_hinweis).unwrap_or_default()));
    o.insert("t".into(), json!(g.unwrap_or(0)));
    match (geplant, live) {
        (Some(p), Some(l)) => {
            let v = ((l - p) as f64 / 60.0).round() as i64;
            o.insert("live".into(), json!(zeit::uhrzeit(l)));
            o.insert("verspaetung".into(), json!(v));
            o.insert("echtzeit".into(), json!(true));
        }
        _ => {
            o.insert("live".into(), json!(""));
            o.insert("verspaetung".into(), json!(0));
            o.insert("echtzeit".into(), json!(false));
        }
    }
}

fn gleis(v: &Value) -> (String, String) {
    match v {
        Value::Object(o) => (
            o.get("planned").and_then(|x| x.as_str()).unwrap_or("").to_string(),
            o.get("live").and_then(|x| x.as_str()).unwrap_or("").to_string(),
        ),
        Value::String(t) => (t.clone(), String::new()),
        _ => (String::new(), String::new()),
    }
}

/// Ein Ort aus der Suche oder einer Route.
pub fn ort(l: &Value) -> Value {
    let k = l.get("coordinate").cloned().unwrap_or(Value::Null);
    let (lat, lon) = koordinate(&k);
    let typ = s(l, "type");
    let name = s(l, "name");
    let kurz = s(l, "short_name");
    json!({
        "id": s(l, "id"),
        "name": if name.is_empty() { kurz.clone() } else { name },
        "unter": s(l, "description"),
        "typ": typ,
        "lat": lat,
        "lon": lon,
        "arten": typen(l.get("transport_types").unwrap_or(&Value::Null)),
    })
}

/// {latitude, longitude} oder [lon, lat] -> (lat, lon)
pub fn koordinate(k: &Value) -> (f64, f64) {
    match k {
        Value::Object(_) => (f(k, "latitude").unwrap_or(0.0), f(k, "longitude").unwrap_or(0.0)),
        Value::Array(a) if a.len() >= 2 => (a[1].as_f64().unwrap_or(0.0), a[0].as_f64().unwrap_or(0.0)),
        _ => (0.0, 0.0),
    }
}

/// Ein Halt eines Abschnitts.
fn halt(st: &Value, ankunft: bool) -> Value {
    let loc = st.get("location").cloned().unwrap_or(Value::Null);
    let (lat, lon) = koordinate(loc.get("coordinate").unwrap_or(&Value::Null));
    let feld = if ankunft { "arrival" } else { "departure" };
    let anders = if ankunft { "departure" } else { "arrival" };
    let z = st.get(feld).filter(|x| !x.is_null()).or_else(|| st.get(anders));
    let (g, l) = zeitpunkt(z);
    let (gp, gl) = gleis(st.get("platform").unwrap_or(&Value::Null));
    let mut o = Map::new();
    o.insert("name".into(), json!(s(&loc, "name")));
    o.insert("id".into(), json!(s(&loc, "id")));
    o.insert("lat".into(), json!(lat));
    o.insert("lon".into(), json!(lon));
    zeitfelder(&mut o, g, l);
    o.insert("gleis".into(), json!(if gl.is_empty() { gp.clone() } else { gl.clone() }));
    o.insert("gleiswechsel".into(), json!(!gl.is_empty() && !gp.is_empty() && gl != gp));
    o.insert("ausgefallen".into(), json!(st.get("cancelled").and_then(|x| x.as_bool()).unwrap_or(false)));
    Value::Object(o)
}

/// Sammelt lesbare Texte aus Meldungen unbekannter Form: Titel und Text,
/// wo immer sie stehen.
fn texte(v: &Value, aus: &mut Vec<Value>, tiefe: usize) {
    if tiefe > 5 {
        return;
    }
    match v {
        Value::Array(a) => a.iter().for_each(|x| texte(x, aus, tiefe + 1)),
        Value::Object(o) => {
            let titel = ["title", "headline", "heading"]
                .iter()
                .find_map(|k| o.get(*k).and_then(|x| x.as_str()))
                .unwrap_or("");
            let text = ["text", "message", "description", "body", "subtitle"]
                .iter()
                .find_map(|k| o.get(*k).and_then(|x| x.as_str()))
                .unwrap_or("");
            if !titel.is_empty() || !text.is_empty() {
                aus.push(json!({"titel": titel.trim(), "text": text.trim()}));
                return;
            }
            o.values().for_each(|x| texte(x, aus, tiefe + 1));
        }
        Value::String(t) if !t.trim().is_empty() => aus.push(json!({"titel": "", "text": t.trim()})),
        _ => {}
    }
}

fn meldungen(m: &Value) -> Vec<Value> {
    let mut aus = Vec::new();
    for k in ["top", "bottom"] {
        if let Some(x) = m.get(k) {
            texte(x, &mut aus, 0);
        }
    }
    if m.is_array() {
        texte(m, &mut aus, 0);
    }
    aus
}

/// "Niederflurfahrzeug", "Rollstuhlstellplatz" ... aus den Aktionen einer
/// Route (die App zeigt sie unter "Ausstattung").
fn ausstattung(v: &Value, aus: &mut Vec<String>, tiefe: usize) {
    if tiefe > 8 {
        return;
    }
    match v {
        Value::Array(a) => a.iter().for_each(|x| ausstattung(x, aus, tiefe + 1)),
        Value::Object(o) => {
            if let Some(b) = o.get("big_feature") {
                let t = s(b, "text");
                if !t.is_empty() && !aus.contains(&t) {
                    aus.push(t);
                }
            }
            o.values().for_each(|x| ausstattung(x, aus, tiefe + 1));
        }
        _ => {}
    }
}

fn infos(i: &Value) -> Vec<Value> {
    let mut aus = Vec::new();
    for sek in liste(i, "sections") {
        for fe in liste(&sek, "fields") {
            let (l, w) = (s(&fe, "label"), s(&fe, "value"));
            if !l.is_empty() || !w.is_empty() {
                aus.push(json!({"label": l, "wert": w}));
            }
        }
    }
    aus
}

fn abschnitt(sek: &Value) -> Value {
    let ty = typen(sek.get("type").unwrap_or(&Value::Null));
    let (k, farbe, name, genau) = art(&ty);
    let tr = sek.get("transport").cloned().unwrap_or(Value::Null);
    let halte = liste(sek, "stops");
    let von = halte.first().map(|h| halt(h, false)).unwrap_or(Value::Null);
    let nach = halte.last().map(|h| halt(h, true)).unwrap_or(Value::Null);
    let zwischen: Vec<Value> = if halte.len() > 2 {
        halte[1..halte.len() - 1].iter().map(|h| halt(h, false)).collect()
    } else {
        Vec::new()
    };
    let dauer = sek.get("duration").and_then(|x| x.as_i64()).unwrap_or(0);
    let linie = s(&tr, "line");
    let label = s(sek, "label");
    json!({
        "art": k,
        "typ": genau,
        "farbe": farbe,
        "linie": linie,
        "kurz": s(&tr, "line_short"),
        "richtung": s(&tr, "direction"),
        "bezeichnung": if !label.is_empty() { label } else { name },
        "dauer": dauer_text(dauer),
        "dauer_min": dauer,
        "strecke": strecke_text(f(sek, "distance").unwrap_or(0.0)),
        "von": von,
        "nach": nach,
        "halte": zwischen,
        "infos": infos(sek.get("information").unwrap_or(&Value::Null)),
        "ausgefallen": sek.get("cancelled").and_then(|x| x.as_bool()).unwrap_or(false),
        "erreichbar": sek.get("reachable").and_then(|x| x.as_bool()).unwrap_or(true),
    })
}

pub fn route(r: &Value, gruppe: &str) -> Value {
    let ty = typen(r.get("type").unwrap_or(&Value::Null));
    let (k, farbe, name, genau) = art(&ty);
    let abschnitte: Vec<Value> = liste(r, "sections").iter().map(abschnitt).collect();
    let dauer = r.get("duration").and_then(|x| x.as_i64()).unwrap_or(0);

    // Abfahrt: erster Abschnitt; bei oeffentlichen Routen zaehlt aber die
    // erste Fahrt, nicht der Fussweg davor -- die steht extra.
    let mut ab = abschnitte.first().map(|a| a["von"].clone()).unwrap_or(Value::Null);
    let an = abschnitte.last().map(|a| a["nach"].clone()).unwrap_or(Value::Null);
    let erste_fahrt = abschnitte.iter().find(|a| a["art"] != "fuss").map(|a| a["von"].clone());
    if ab.is_null() {
        ab = erste_fahrt.clone().unwrap_or(Value::Null);
    }

    let mut linien = Vec::new();
    for a in &abschnitte {
        if a["art"] == "fuss" {
            continue;
        }
        let mut text = a["linie"].as_str().unwrap_or("").to_string();
        if text.is_empty() {
            text = a["bezeichnung"].as_str().unwrap_or("").to_string();
        }
        linien.push(json!({"text": text, "farbe": a["farbe"], "art": a["art"]}));
    }
    let mut titel = s(r, "title");
    if titel.is_empty() {
        titel = linien.iter().filter_map(|l| l["text"].as_str()).collect::<Vec<_>>().join(" › ");
    }
    if titel.is_empty() {
        titel = name.clone();
    }
    let ausgefallen = abschnitte.iter().any(|a| a["ausgefallen"] == true)
        || abschnitte.iter().any(|a| a["von"]["ausgefallen"] == true || a["nach"]["ausgefallen"] == true);
    let verspaetung = abschnitte
        .iter()
        .filter(|a| a["art"] != "fuss")
        .map(|a| a["von"]["verspaetung"].as_i64().unwrap_or(0))
        .max()
        .unwrap_or(0);
    let mut aus = Vec::new();
    ausstattung(r.get("actions").unwrap_or(&Value::Null), &mut aus, 0);
    let mut labels = Vec::new();
    for l in liste(r, "labels") {
        match &l {
            Value::String(t) => labels.push(t.clone()),
            _ => {
                let t = s(&l, "text");
                if !t.is_empty() {
                    labels.push(t);
                }
            }
        }
    }
    json!({
        "id": s(r, "id"),
        "gruppe": gruppe,
        "art": k,
        "typ": genau,
        "farbe": farbe,
        "titel": titel,
        "untertitel": s(r, "subtitle"),
        "anbieter": s(r, "label"),
        "labels": labels,
        "ab": ab,
        "an": an,
        "erste_fahrt": erste_fahrt.unwrap_or(Value::Null),
        "dauer": dauer_text(dauer),
        "dauer_min": dauer,
        "umstiege": r.get("transfers").and_then(|x| x.as_i64()).unwrap_or(0),
        "strecke": strecke_text(f(r, "distance").unwrap_or(0.0)),
        "linien": linien,
        "abschnitte": abschnitte,
        "meldungen": meldungen(r.get("messages").unwrap_or(&Value::Null)),
        "ausstattung": aus,
        "ausgefallen": ausgefallen,
        "verspaetung": verspaetung,
    })
}

/// Gruppenschluessel und Ueberschrift der Oberflaeche. Die buchbaren
/// Gruppen des Servers (schnell/langsam/noch langsamer) sind fuer uns eine:
/// gebucht wird hier nichts.
pub fn gruppe_name(g: &str) -> (&'static str, &'static str, i64) {
    match g {
        "public" => ("oeffi", "Öffentlich", 0),
        "individual" => ("selbst", "Selbst unterwegs", 1),
        "not_bookable" => ("weitere", "Weitere Angebote", 3),
        _ if g.contains("bookable") => ("teilen", "Sharing & Taxi", 2),
        _ => ("weitere", "Weitere Angebote", 3),
    }
}

/// Antwort von v3/routes -> {gruppen, offen, start, ziel}
pub fn routen(v: &Value) -> Value {
    let mut gruppen = Vec::new();
    for g in liste(v, "transportation_groups") {
        let name = s(&g, "group");
        let (schluessel, titel, rang) = gruppe_name(&name);
        let routen: Vec<Value> = liste(&g, "routes").iter().map(|r| route(r, schluessel)).collect();
        let hinweis = {
            let mut t = Vec::new();
            texte(g.get("hint").unwrap_or(&Value::Null), &mut t, 0);
            t.first().map(|x| {
                let ti = x["titel"].as_str().unwrap_or("");
                let te = x["text"].as_str().unwrap_or("");
                if ti.is_empty() { te.to_string() } else if te.is_empty() { ti.to_string() } else { format!("{}: {}", ti, te) }
            }).unwrap_or_default()
        };
        gruppen.push(json!({
            "schluessel": schluessel,
            "titel": titel,
            "rang": rang,
            "routen": routen,
            "frueher": s(&g, "earlier_url"),
            "spaeter": s(&g, "later_url"),
            "hinweis": hinweis,
        }));
    }
    let offen: Vec<Value> = liste(v, "unresolved_urls");
    json!({
        "gruppen": gruppen,
        "offen": offen,
        // Preise kommen getrennt (v3/offers), damit die Routen nicht auf sie warten
        "preise_url": s(v, "offers_ref"),
        "start": v.get("start_location").map(ort).unwrap_or(Value::Null),
        "ziel": v.get("destination_location").map(ort).unwrap_or(Value::Null),
        "meldungen": meldungen(v.get("messages").unwrap_or(&Value::Null)),
    })
}

/// Abfahrtstafel einer Station, ab jetzt, hoechstens `max` Eintraege.
pub fn abfahrten(v: &Value, max: usize) -> Value {
    let jetzt = zeit::jetzt_utc();
    let mut aus = Vec::new();
    let daten = liste(v, "data");
    for st in &daten {
        for d in liste(st, "departures") {
            let geplant = d.get("departure_time").and_then(|x| x.as_str()).and_then(zeit::iso_lesen);
            let live = match d.get("live") {
                Some(Value::Object(o)) => o.get("departure_time").and_then(|x| x.as_str()).and_then(zeit::iso_lesen),
                Some(Value::String(t)) => zeit::iso_lesen(t),
                _ => None,
            };
            let wann = live.or(geplant).unwrap_or(0);
            if wann + 60 < jetzt {
                continue;
            }
            let linie = d.get("line").cloned().unwrap_or(Value::Null);
            let mut ty = typen(linie.get("type").unwrap_or(&Value::Null));
            if ty.is_empty() {
                ty = vec![s(&linie, "transport_type")];
            }
            let (k, farbe, name, genau) = art(&ty);
            let (gp, gl) = gleis(d.get("platform").unwrap_or(&Value::Null));
            let mut o = Map::new();
            zeitfelder(&mut o, geplant, live);
            o.insert("wann".into(), json!(wann));
            let n = s(&linie, "name");
            o.insert("linie".into(), json!(if n.is_empty() { s(&linie, "short_name") } else { n }));
            o.insert("art".into(), json!(k));
            o.insert("typ".into(), json!(genau));
            o.insert("bezeichnung".into(), json!(name));
            o.insert("farbe".into(), json!(farbe));
            let ri = s(&d, "direction_name");
            o.insert("richtung".into(), json!(if ri.is_empty() { s(&d, "direction") } else { ri }));
            o.insert("gleis".into(), json!(if gl.is_empty() { gp.clone() } else { gl.clone() }));
            o.insert("gleiswechsel".into(), json!(!gl.is_empty() && !gp.is_empty() && gl != gp));
            o.insert("ausgefallen".into(), json!(d.get("cancelled").and_then(|x| x.as_bool()).unwrap_or(false)));
            o.insert("warnung".into(), json!(d.get("warning").and_then(|x| x.as_bool()).unwrap_or(false)));
            o.insert("meldungen".into(), json!(meldungen(d.get("messages").unwrap_or(&Value::Null))));
            o.insert("fahrt".into(), json!(s(&d, "route_request_url")));
            aus.push(Value::Object(o));
        }
    }
    aus.sort_by_key(|x| x["wann"].as_i64().unwrap_or(0));
    let gesamt = aus.len();
    aus.truncate(max);
    json!({"abfahrten": aus, "gesamt": gesamt})
}

/// Fahrtverlauf (routing/api/v1/stops) -> {halte, aktuell}
pub fn fahrt(v: &Value) -> Value {
    let jetzt = zeit::jetzt_utc();
    let mut halte = Vec::new();
    for h in liste(v, "data") {
        let stn = h.get("station").cloned().unwrap_or(Value::Null);
        let (lat, lon) = koordinate(stn.get("coordinate").unwrap_or(&Value::Null));
        let geplant = ["arrival", "departure"]
            .iter()
            .find_map(|k| h.get(*k).and_then(|x| x.as_str()).and_then(zeit::iso_lesen));
        let live = match h.get("live") {
            Some(Value::String(t)) => zeit::iso_lesen(t),
            Some(Value::Object(o)) => o.values().find_map(|x| x.as_str().and_then(zeit::iso_lesen)),
            _ => None,
        };
        let (gp, gl) = gleis(h.get("platform").unwrap_or(&Value::Null));
        let mut o = Map::new();
        o.insert("name".into(), json!(s(&stn, "name")));
        o.insert("id".into(), json!(s(&stn, "id")));
        o.insert("lat".into(), json!(lat));
        o.insert("lon".into(), json!(lon));
        zeitfelder(&mut o, geplant, live);
        o.insert("vorbei".into(), json!(live.or(geplant).map(|t| t + 30 < jetzt).unwrap_or(false)));
        o.insert("gleis".into(), json!(if gl.is_empty() { gp } else { gl }));
        o.insert("ausgefallen".into(), json!(h.get("cancelled").and_then(|x| x.as_bool()).unwrap_or(false)));
        halte.push(Value::Object(o));
    }
    json!({
        "halte": halte,
        "aktuell": v.get("current_station_index").and_then(|x| x.as_i64()).unwrap_or(-1),
        "meldungen": meldungen(v.get("messages").unwrap_or(&Value::Null)),
    })
}

fn felder(v: &Value, k: &str) -> Vec<Value> {
    liste(v, k)
        .iter()
        .filter_map(|fe| {
            let (l, w) = (s(fe, "label"), s(fe, "value"));
            if l.is_empty() && w.is_empty() {
                None
            } else {
                Some(json!({"label": l, "wert": w}))
            }
        })
        .collect()
}

/// v7/radar -> {punkte, gruppen}
pub fn umgebung(v: &Value) -> Value {
    let mut punkte = Vec::new();
    let mut gruppen = Vec::new();
    for g in liste(v, "groups") {
        let mut anzahl = 0;
        for b in liste(&g, "blips") {
            let (art_name, inhalt) = match b.as_object().and_then(|o| o.iter().next()) {
                Some((k, w)) => (k.clone(), w.clone()),
                None => continue,
            };
            if art_name == "area_service" {
                continue;
            }
            let (lat, lon) = koordinate(inhalt.get("coordinate").unwrap_or(&Value::Null));
            if lat == 0.0 && lon == 0.0 {
                continue;
            }
            let mut ty = typen(inhalt.get("transport_types").unwrap_or(&Value::Null));
            let anbieter = s(&inhalt, "provider");
            let gname = s(&inhalt, "group_name");
            if art_name != "station" {
                ty = vec![gname.clone(), anbieter.clone()];
            }
            let (k, farbe, name, _) = art(&ty);
            let farbe = if art_name == "station" { "#137fd2".to_string() } else { farbe };
            let titel = {
                let t = s(&inhalt, "title");
                if t.is_empty() { s(&inhalt, "name") } else { t }
            };
            let mut unter_felder = felder(&inhalt, "subtitle_fields");
            unter_felder.extend(felder(&inhalt, "fields"));
            let zoom = inhalt.get("zoom").cloned().unwrap_or(Value::Null);
            let ab_zoom = zoom
                .get("dot")
                .and_then(|x| x.get(0))
                .or_else(|| zoom.get("marker").and_then(|x| x.get(0)))
                .and_then(|x| x.as_i64())
                .unwrap_or(0);
            let mut gruppen_eintraege = Vec::new();
            for ig in liste(&inhalt, "item_groups") {
                for it in liste(&ig, "items") {
                    let t = s(&it, "title");
                    let u = s(&it, "subtitle");
                    if !t.is_empty() {
                        gruppen_eintraege.push(json!({"label": t, "wert": u}));
                    }
                }
            }
            unter_felder.extend(gruppen_eintraege);
            let kopf = s(&inhalt, "heading");
            let bezeichnung = if art_name == "station" {
                // alle Verkehrsmittel der Haltestelle: "Zug, U-Bahn, Bus"
                let mut namen: Vec<String> = Vec::new();
                for t in typen(inhalt.get("transport_types").unwrap_or(&Value::Null)) {
                    let (_, _, n, _) = art(&[t]);
                    if !n.is_empty() && !namen.contains(&n) {
                        namen.push(n);
                    }
                }
                namen.join(", ")
            } else if kopf.is_empty() {
                name
            } else {
                kopf
            };
            punkte.push(json!({
                "id": s(&inhalt, "id"),
                "punktart": art_name,
                "gruppe": gname,
                "anbieter": anbieter,
                "art": k,
                "farbe": farbe,
                "bezeichnung": bezeichnung,
                "name": titel,
                "unter": s(&inhalt, "subtitle"),
                "adresse": s(&inhalt, "address"),
                "lat": lat,
                "lon": lon,
                "arten": typen(inhalt.get("transport_types").unwrap_or(&Value::Null)),
                "felder": unter_felder,
                "verfuegbar": inhalt.get("available").and_then(|x| x.as_bool()).unwrap_or(true),
                "ab_zoom": ab_zoom,
            }));
            anzahl += 1;
        }
        let t = s(&g, "title");
        if anzahl > 0 && !t.is_empty() {
            gruppen.push(json!({"titel": t, "anzahl": anzahl}));
        }
    }
    json!({"punkte": punkte, "gruppen": gruppen})
}

/// Cent -> "66,40 €", geschaetzt -> "ca. 12 €"
pub fn preis_text(cent: i64, geschaetzt: bool) -> String {
    let euro = if geschaetzt && cent % 100 == 0 {
        format!("{} €", cent / 100)
    } else {
        format!("{},{:02} €", cent / 100, (cent % 100).abs())
    };
    if geschaetzt { format!("ca. {}", euro) } else { euro }
}

/// v3/offers -> {route_id: {text, cent, geschaetzt, hinweis, co2}}. Preise
/// sind Vollpreise ohne Ermaessigung (anonyme Sitzung, kein Profil).
pub fn preise(v: &Value) -> Value {
    let mut aus = Map::new();
    for o in v.as_array().into_iter().flatten() {
        let id = s(o, "route_id");
        let p = match o.get("price") {
            Some(p) if p.is_object() => p,
            _ => continue,
        };
        let cent = match p.get("amount").and_then(|x| x.as_i64()) {
            Some(c) => c,
            None => continue,
        };
        let geschaetzt = p.get("estimated").and_then(|x| x.as_bool()).unwrap_or(false);
        let mut hinweis = Vec::new();
        texte(o.get("messages").unwrap_or(&Value::Null), &mut hinweis, 0);
        let hinweis: Vec<String> = hinweis
            .iter()
            .map(|h| h["text"].as_str().unwrap_or("").to_string())
            .filter(|t| !t.is_empty())
            .collect();
        // "Du sparst 642 g CO2 im Vergleich zum PKW" (Aktion ohne Wirkung)
        let mut co2 = String::new();
        // "Ticket kaufen": die Startdaten des Kaufablaufs (POST v3/flow)
        let mut kauf = Value::Null;
        let mut kauf_titel = String::new();
        for a in liste(o, "actions") {
            if let Some(n) = a.get("noop") {
                let t = s(n, "left_text");
                if !t.is_empty() {
                    co2 = t;
                }
            }
            if let Some(f) = a.get("flow") {
                if f.get("data").map(|d| d.is_object()).unwrap_or(false) {
                    kauf = f["data"].clone();
                    kauf_titel = s(f, "title");
                }
            }
        }
        aus.insert(id, json!({
            "text": preis_text(cent, geschaetzt),
            "cent": cent,
            "geschaetzt": geschaetzt,
            "hinweis": hinweis.join(" "),
            "co2": co2,
            "kauf": kauf,
            "kauf_titel": kauf_titel,
        }));
    }
    Value::Object(aus)
}

pub fn filterliste(v: &Value) -> Value {
    let liste: Vec<Value> = v
        .as_array()
        .cloned()
        .unwrap_or_default()
        .iter()
        .map(|x| json!({"id": s(x, "id"), "titel": s(x, "title"), "kurz": s(x, "short_title"), "leer": s(x, "empty")}))
        .filter(|x| x["id"] != "nearby")
        .collect();
    Value::Array(liste)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn arten() {
        let t = |v: &[&str]| v.iter().map(|x| x.to_string()).collect::<Vec<_>>();
        let (k, farbe, name, _) = art(&t(&["public", "metro", "metro_u3"]));
        assert_eq!((k, farbe.as_str(), name.as_str()), ("ubahn", "#f48221", "U-Bahn"));
        assert_eq!(art(&t(&["walk"])).0, "fuss");
        assert_eq!(art(&t(&["escooter", "shared", "lime"])).0, "scooter");
        assert_eq!(art(&t(&["bike", "personal"])).2, "Eigenes Fahrrad");
        assert_eq!(art(&t(&["taxi_40100"])).0, "taxi");
        assert_eq!(art(&t(&["public", "train", "oebb"])).0, "zug");
    }

    #[test]
    fn texte_formen() {
        assert_eq!(dauer_text(9), "9 min");
        assert_eq!(dauer_text(65), "1 h 5 min");
        assert_eq!(strecke_text(3456.0), "3,5 km");
        assert_eq!(strecke_text(184.0), "180 m");
        assert_eq!(preis_text(6640, false), "66,40 €");
        assert_eq!(preis_text(1200, true), "ca. 12 €");
        assert_eq!(preis_text(300, false), "3,00 €");
    }
}
