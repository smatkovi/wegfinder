//! Uhrzeiten in Wiener Ortszeit, ohne Zeitzonen-Bibliothek.
//!
//! Der Server schickt Zeiten teils mit +02:00, teils in UTC (+00:00, etwa
//! bei Auto und Fahrrad). Gezeigt wird immer Wiener Zeit; gerechnet wird
//! fest mit MEZ/MESZ nach der EU-Regel (Sommerzeit vom letzten Sonntag im
//! Maerz bis zum letzten Sonntag im Oktober, Wechsel um 01:00 UTC) -- das
//! statisch gegen musl gebundene Binary findet die Zeitzone des Geraets
//! nicht zuverlaessig, und wegfinder faehrt ohnehin nur in Oesterreich.

use std::time::{SystemTime, UNIX_EPOCH};

/// Tage seit 1970-01-01 (proleptisch gregorianisch).
pub fn tage(jahr: i32, monat: u32, tag: u32) -> i64 {
    let y = if monat <= 2 { jahr as i64 - 1 } else { jahr as i64 };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let m = monat as i64;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + tag as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

pub fn datum_aus_tagen(t: i64) -> (i32, u32, u32) {
    let z = t + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    ((if m <= 2 { y + 1 } else { y }) as i32, m, d)
}

/// 0 = Montag ... 6 = Sonntag. Der 1.1.1970 war ein Donnerstag.
fn wochentag(t: i64) -> i64 {
    (t + 3).rem_euclid(7)
}

fn letzter_sonntag(jahr: i32, monat: u32) -> i64 {
    let ende = tage(jahr, monat, 31);
    ende - (wochentag(ende) + 1) % 7
}

pub fn jetzt_utc() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

/// Versatz Wien gegen UTC in Sekunden zum Zeitpunkt `utc` (Unix-Sekunden).
pub fn wien_versatz(utc: i64) -> i64 {
    let (jahr, _, _) = datum_aus_tagen(utc.div_euclid(86400));
    let beginn = letzter_sonntag(jahr, 3) * 86400 + 3600;
    let ende = letzter_sonntag(jahr, 10) * 86400 + 3600;
    if utc >= beginn && utc < ende {
        7200
    } else {
        3600
    }
}

pub fn datum_text(t: i64) -> String {
    let (j, m, d) = datum_aus_tagen(t);
    format!("{:04}-{:02}-{:02}", j, m, d)
}

/// Ortszeit fuers Protokoll.
pub fn jetzt_text() -> String {
    let utc = jetzt_utc();
    let ort = utc + wien_versatz(utc);
    let sek = ort.rem_euclid(86400);
    format!("{} {:02}:{:02}:{:02}", datum_text(ort.div_euclid(86400)), sek / 3600, sek / 60 % 60, sek % 60)
}

/// "2026-10-15T09:26:00+02:00" (auch ...Z, mit Sekundenbruchteilen) ->
/// Unix-Sekunden.
pub fn iso_lesen(s: &str) -> Option<i64> {
    let s = s.trim();
    let b = s.as_bytes();
    if b.len() < 16 || b[4] != b'-' || b[7] != b'-' || (b[10] != b'T' && b[10] != b' ') {
        return None;
    }
    let jahr: i32 = s.get(0..4)?.parse().ok()?;
    let monat: u32 = s.get(5..7)?.parse().ok()?;
    let tag: u32 = s.get(8..10)?.parse().ok()?;
    let stunde: i64 = s.get(11..13)?.parse().ok()?;
    let minute: i64 = s.get(14..16)?.parse().ok()?;
    let mut rest = &s[16..];
    let mut sekunde = 0i64;
    if rest.starts_with(':') && rest.len() >= 3 {
        sekunde = rest.get(1..3)?.parse().ok()?;
        rest = &rest[3..];
    }
    if rest.starts_with('.') {
        let ende = rest[1..].find(|c: char| !c.is_ascii_digit()).map(|i| i + 1).unwrap_or(rest.len());
        rest = &rest[ende..];
    }
    let versatz = if rest.is_empty() || rest == "Z" {
        0
    } else {
        let vz = if rest.starts_with('-') { -1 } else { 1 };
        let h: i64 = rest.get(1..3)?.parse().ok()?;
        let m: i64 = rest.get(4..6).and_then(|x| x.parse().ok()).unwrap_or(0);
        vz * (h * 3600 + m * 60)
    };
    Some(tage(jahr, monat, tag) * 86400 + stunde * 3600 + minute * 60 + sekunde - versatz)
}

/// Unix-Sekunden -> "09:26" in Wien.
pub fn uhrzeit(utc: i64) -> String {
    let ort = utc + wien_versatz(utc);
    let sek = ort.rem_euclid(86400);
    format!("{:02}:{:02}", sek / 3600, sek / 60 % 60)
}

/// Unix-Sekunden -> Kalendertag in Wien (Tage seit 1970).
pub fn wien_tag(utc: i64) -> i64 {
    (utc + wien_versatz(utc)).div_euclid(86400)
}

/// "Do. 16.10." fuer Zeiten, die nicht heute sind; sonst leer.
pub fn tag_hinweis(utc: i64) -> String {
    let heute = wien_tag(jetzt_utc());
    let tag = wien_tag(utc);
    if tag == heute {
        return String::new();
    }
    if tag == heute + 1 {
        return "morgen".into();
    }
    const NAMEN: [&str; 7] = ["Mo.", "Di.", "Mi.", "Do.", "Fr.", "Sa.", "So."];
    let (_, m, d) = datum_aus_tagen(tag);
    format!("{} {}.{}.", NAMEN[wochentag(tag) as usize], d, m)
}

/// Unix-Sekunden -> "2026-10-15T07:30:00+00:00", wie der Server es annimmt.
pub fn iso_utc(utc: i64) -> String {
    let (j, m, d) = datum_aus_tagen(utc.div_euclid(86400));
    let s = utc.rem_euclid(86400);
    format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}+00:00", j, m, d, s / 3600, s / 60 % 60, s % 60)
}

/// Wiener Ortszeit ("2026-10-15", "09:30") -> Unix-Sekunden.
pub fn wien_lesen(datum: &str, uhrzeit: &str) -> Option<i64> {
    let d = datum.trim();
    if d.len() < 10 {
        return None;
    }
    let jahr: i32 = d.get(0..4)?.parse().ok()?;
    let monat: u32 = d.get(5..7)?.parse().ok()?;
    let tag: u32 = d.get(8..10)?.parse().ok()?;
    let mut t = uhrzeit.trim().split(':');
    let h: i64 = t.next()?.parse().ok()?;
    let min: i64 = t.next().unwrap_or("0").parse().ok()?;
    let lokal = tage(jahr, monat, tag) * 86400 + h * 3600 + min * 60;
    // Versatz am ungefaehren Zeitpunkt; an den zwei Umstellungsnaechten
    // kann eine Stunde danebenliegen, das reicht fuer eine Fahrplanabfrage.
    Some(lokal - wien_versatz(lokal - 3600))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn iso() {
        let a = iso_lesen("2026-10-15T09:26:00+02:00").unwrap();
        let b = iso_lesen("2026-10-15T07:26:00+00:00").unwrap();
        let c = iso_lesen("2026-10-15T07:26:00.123Z").unwrap();
        assert_eq!(a, b);
        assert_eq!(a, c);
        assert_eq!(uhrzeit(a), "09:26");
        assert_eq!(iso_utc(a), "2026-10-15T07:26:00+00:00");
        assert_eq!(wien_lesen("2026-10-15", "09:26"), Some(a));
        // Winter: +01:00
        let w = iso_lesen("2026-12-01T08:00:00+01:00").unwrap();
        assert_eq!(uhrzeit(w), "08:00");
        assert_eq!(wien_lesen("2026-12-01", "08:00"), Some(w));
    }

    #[test]
    fn sommerzeit() {
        assert_eq!(datum_aus_tagen(letzter_sonntag(2026, 3)), (2026, 3, 29));
        assert_eq!(datum_aus_tagen(letzter_sonntag(2026, 10)), (2026, 10, 25));
    }
}
