//! Linienzuege des Servers: Googles "Encoded Polyline" (5 Nachkommastellen).
//!
//! Fuer die Karte werden sie ausgeduennt (Douglas-Peucker): am N9 zeichnet
//! QML 1 jede Teilstrecke als eigenes gedrehtes Rechteck, da zaehlt jeder
//! Punkt. Eine U-Bahn-Fahrt hat 200 Punkte, eine Zugfahrt Wien-Salzburg
//! mehrere tausend.

/// Entschluesselt einen Linienzug zu (Breite, Laenge).
pub fn lesen(text: &str) -> Vec<(f64, f64)> {
    let b = text.as_bytes();
    let mut i = 0;
    let (mut lat, mut lon) = (0i64, 0i64);
    let mut punkte = Vec::new();
    let zahl = |i: &mut usize| -> Option<i64> {
        let mut ergebnis: i64 = 0;
        let mut schub = 0;
        loop {
            let c = *b.get(*i)? as i64 - 63;
            *i += 1;
            ergebnis |= (c & 0x1f) << schub;
            schub += 5;
            if c < 0x20 {
                break;
            }
            if schub > 60 {
                return None;
            }
        }
        Some(if ergebnis & 1 != 0 { !(ergebnis >> 1) } else { ergebnis >> 1 })
    };
    while i < b.len() {
        let (d1, d2) = match (zahl(&mut i), zahl(&mut i)) {
            (Some(a), Some(c)) => (a, c),
            _ => break,
        };
        lat += d1;
        lon += d2;
        punkte.push((lat as f64 / 1e5, lon as f64 / 1e5));
    }
    punkte
}

/// Abstand von p zur Strecke a-b in Metern (flach genaehert, reicht fuer
/// Oesterreich).
fn abstand(p: (f64, f64), a: (f64, f64), b: (f64, f64)) -> f64 {
    let k = (a.0.to_radians()).cos();
    let (px, py) = (p.1 * k * 111_320.0, p.0 * 110_540.0);
    let (ax, ay) = (a.1 * k * 111_320.0, a.0 * 110_540.0);
    let (bx, by) = (b.1 * k * 111_320.0, b.0 * 110_540.0);
    let (dx, dy) = (bx - ax, by - ay);
    let l2 = dx * dx + dy * dy;
    let t = if l2 > 0.0 { (((px - ax) * dx + (py - ay) * dy) / l2).clamp(0.0, 1.0) } else { 0.0 };
    let (qx, qy) = (ax + t * dx, ay + t * dy);
    ((px - qx).powi(2) + (py - qy).powi(2)).sqrt()
}

/// Douglas-Peucker mit Toleranz in Metern, ohne Rekursion.
pub fn duennen(punkte: &[(f64, f64)], toleranz: f64) -> Vec<(f64, f64)> {
    if punkte.len() < 3 {
        return punkte.to_vec();
    }
    let mut behalten = vec![false; punkte.len()];
    behalten[0] = true;
    behalten[punkte.len() - 1] = true;
    let mut stapel = vec![(0usize, punkte.len() - 1)];
    while let Some((a, b)) = stapel.pop() {
        if b <= a + 1 {
            continue;
        }
        let (mut weit, mut idx) = (0.0, a);
        for i in a + 1..b {
            let d = abstand(punkte[i], punkte[a], punkte[b]);
            if d > weit {
                weit = d;
                idx = i;
            }
        }
        if weit > toleranz {
            behalten[idx] = true;
            stapel.push((a, idx));
            stapel.push((idx, b));
        }
    }
    punkte.iter().zip(behalten).filter(|(_, k)| *k).map(|(p, _)| *p).collect()
}

/// Duennt mehrere Linien gemeinsam aus, bis zusammen hoechstens `max`
/// Punkte bleiben.
pub fn auf_hoechstens(linien: &[Vec<(f64, f64)>], max: usize) -> Vec<Vec<(f64, f64)>> {
    let mut toleranz = 2.0;
    loop {
        let neu: Vec<Vec<(f64, f64)>> = linien.iter().map(|l| duennen(l, toleranz)).collect();
        let summe: usize = neu.iter().map(|l| l.len()).sum();
        if summe <= max || toleranz > 20_000.0 {
            return neu;
        }
        toleranz *= 1.8;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn google_beispiel() {
        // Beispiel aus Googles Beschreibung des Formats
        let p = lesen("_p~iF~ps|U_ulLnnqC_mqNvxq`@");
        assert_eq!(p.len(), 3);
        assert!((p[0].0 - 38.5).abs() < 1e-9 && (p[0].1 + 120.2).abs() < 1e-9);
        assert!((p[2].0 - 43.252).abs() < 1e-9 && (p[2].1 + 126.453).abs() < 1e-9);
    }

    #[test]
    fn gerade_wird_zwei_punkte() {
        let l: Vec<(f64, f64)> = (0..50).map(|i| (48.0 + i as f64 * 0.001, 16.0)).collect();
        assert_eq!(duennen(&l, 1.0).len(), 2);
    }
}
