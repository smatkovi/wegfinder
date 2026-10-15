.pragma library

// Hilfen fuer beide Oberflaechen (Harmattan: Qt 4.7, Sailfish: Qt 5). Nur
// ES3: kein let/const, keine Pfeile, kein Array.find.

var ROSA = "#ff4083"      // Markenfarbe, auch Ziel auf der Karte
var BLAU = "#137fd2"      // Start auf der Karte, eigener Standort
var WIEN = { lat: 48.20849, lon: 16.37208 }

function zahl(x, vorgabe) {
    var n = Number(x)
    return isNaN(n) ? vorgabe : n
}

function kopie(o) {
    return o === undefined || o === null ? o : JSON.parse(JSON.stringify(o))
}

// Schrift auf einer Linienfarbe: schwarz auf hellen Farben (gelb, hellblau).
function schriftAuf(farbe) {
    var h = String(farbe || "#666666").replace("#", "")
    if (h.length === 3)
        h = h.charAt(0) + h.charAt(0) + h.charAt(1) + h.charAt(1) + h.charAt(2) + h.charAt(2)
    var r = parseInt(h.substr(0, 2), 16), g = parseInt(h.substr(2, 2), 16), b = parseInt(h.substr(4, 2), 16)
    var l = (0.299 * r + 0.587 * g + 0.114 * b) / 255
    return l > 0.68 ? "#1a1a1a" : "#ffffff"
}

function sinnbild(art) {
    var bekannt = ["zug", "sbahn", "ubahn", "tram", "bus", "schiff", "seilbahn", "fuss", "rad", "scooter", "auto", "taxi"]
    for (var i = 0; i < bekannt.length; ++i)
        if (bekannt[i] === art)
            return "bilder/" + art + ".png"
    return "bilder/sonst.png"
}

// "+3" in Rot, "pünktlich" nur wenn es Echtzeit gibt.
function verspaetungText(h) {
    if (!h || !h.echtzeit)
        return ""
    if (h.verspaetung > 0)
        return "+" + h.verspaetung
    if (h.verspaetung < 0)
        return String(h.verspaetung)
    return ""
}

function ortName(o) {
    if (!o)
        return ""
    if (o.bezeichnung && o.bezeichnung !== "")
        return o.bezeichnung
    return o.name
}

function ortZusatz(o) {
    if (!o)
        return ""
    var teile = []
    if (o.bezeichnung && o.bezeichnung !== "" && o.bezeichnung !== o.name)
        teile.push(o.name)
    if (o.unter && o.unter !== "")
        teile.push(o.unter)
    if (teile.length === 0)
        teile.push(typText(o.typ))
    return teile.join(", ")
}

function typText(t) {
    if (t === "station") return "Haltestelle"
    if (t === "street") return "Straße"
    if (t === "address") return "Adresse"
    if (t === "poi") return "Ort"
    if (t === "standort") return "Aktuelle Position"
    if (t === "koordinate") return "Punkt auf der Karte"
    return ""
}

function standortOrt(lat, lon) {
    return { id: "", name: "Mein Standort", unter: "", typ: "standort", lat: lat, lon: lon, bezeichnung: "" }
}

function kartenOrt(lat, lon, name) {
    return { id: "", name: name || "Punkt auf der Karte", unter: "", typ: "koordinate", lat: lat, lon: lon, bezeichnung: "" }
}

function zweistellig(n) {
    return n < 10 ? "0" + n : String(n)
}

// Datum des Telefons als "2026-10-15" und Uhrzeit "09:30"
function datumText(d) {
    return d.getFullYear() + "-" + zweistellig(d.getMonth() + 1) + "-" + zweistellig(d.getDate())
}
function uhrText(d) {
    return zweistellig(d.getHours()) + ":" + zweistellig(d.getMinutes())
}

var TAGE = ["So.", "Mo.", "Di.", "Mi.", "Do.", "Fr.", "Sa."]

// Anzeige der gewaehlten Zeit: "Abfahrt jetzt", "Ankunft 18:30", "Abfahrt Do. 16.10. 07:15"
function zeitAnzeige(z) {
    if (!z || !z.zeit)
        return "Abfahrt jetzt"
    var art = z.ankunft ? "Ankunft" : "Abfahrt"
    var heute = datumText(new Date())
    if (!z.datum || z.datum === heute)
        return art + " " + z.zeit
    var t = z.datum.split("-")
    var d = new Date(parseInt(t[0], 10), parseInt(t[1], 10) - 1, parseInt(t[2], 10))
    return art + " " + TAGE[d.getDay()] + " " + d.getDate() + "." + (d.getMonth() + 1) + ". " + z.zeit
}

function fehlerText(t) {
    var s = String(t || "")
    if (s === "")
        return "Unbekannter Fehler"
    return s
}

// "in 3 min" fuer Abfahrten in naher Zukunft (t: Unix-Sekunden)
function inMinuten(t) {
    var jetzt = Math.floor(new Date().getTime() / 1000)
    var m = Math.round((t - jetzt) / 60)
    if (m <= 0)
        return "jetzt"
    if (m < 60)
        return "in " + m + " min"
    return ""
}

// ---- Karte: Web-Mercator in Weltpixeln einer Zoomstufe -----------------

var KACHEL = 256

function welt(z) {
    return KACHEL * Math.pow(2, z)
}
function lonZuX(lon, z) {
    return (lon + 180) / 360 * welt(z)
}
function latZuY(lat, z) {
    var r = lat * Math.PI / 180
    return (1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2 * welt(z)
}
function xZuLon(x, z) {
    return x / welt(z) * 360 - 180
}
function yZuLat(y, z) {
    var n = Math.PI - 2 * Math.PI * y / welt(z)
    return 180 / Math.PI * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)))
}

// Zoomstufe, bei der der Rahmen {n,s,w,o} in breite x hoehe passt.
function zoomFuer(rahmen, breite, hoehe, minZ, maxZ) {
    for (var z = maxZ; z > minZ; --z) {
        var bx = lonZuX(rahmen.o, z) - lonZuX(rahmen.w, z)
        var by = latZuY(rahmen.s, z) - latZuY(rahmen.n, z)
        if (bx <= breite && by <= hoehe)
            return z
    }
    return minZ
}

// Teilstrecken fuer die Karte am N9: jede wird ein gedrehtes Rechteck.
// Rueckgabe in Weltpixeln der Zoomstufe z.
function strecken(linien, z) {
    var aus = []
    for (var i = 0; i < linien.length; ++i) {
        var l = linien[i], p = l.punkte
        for (var j = 1; j < p.length; ++j) {
            var x1 = lonZuX(p[j - 1][1], z), y1 = latZuY(p[j - 1][0], z)
            var x2 = lonZuX(p[j][1], z), y2 = latZuY(p[j][0], z)
            var dx = x2 - x1, dy = y2 - y1
            var len = Math.sqrt(dx * dx + dy * dy)
            if (len < 0.5)
                continue
            aus.push({ x: x1, y: y1, laenge: len, winkel: Math.atan2(dy, dx) * 180 / Math.PI,
                       farbe: l.farbe, fuss: l.art === "fuss" })
        }
    }
    return aus
}

// Rahmen um eine Liste von {lat, lon}
function rahmenUm(punkte) {
    var r = { n: -90, s: 90, w: 180, o: -180 }
    for (var i = 0; i < punkte.length; ++i) {
        var p = punkte[i]
        if (p.lat === 0 && p.lon === 0)
            continue
        r.n = Math.max(r.n, p.lat); r.s = Math.min(r.s, p.lat)
        r.w = Math.min(r.w, p.lon); r.o = Math.max(r.o, p.lon)
    }
    return r
}

// Sinnbild einer Haltestelle aus ihren Verkehrsmitteln (Suche)
function artAusTypen(arten) {
    if (!arten)
        return "bus"
    var reihe = [["train", "zug"], ["s_bahn", "sbahn"], ["metro", "ubahn"], ["tram", "tram"], ["ship", "schiff"],
                 ["cable_car", "seilbahn"]]
    for (var i = 0; i < reihe.length; ++i)
        for (var j = 0; j < arten.length; ++j)
            if (arten[j] === reihe[i][0])
                return reihe[i][1]
    return "bus"
}

// Nicht-leere Teile verbinden
function verbinden(teile, trenner) {
    var aus = []
    for (var i = 0; i < teile.length; ++i)
        if (teile[i] !== undefined && teile[i] !== null && teile[i] !== "")
            aus.push(teile[i])
    return aus.join(trenner)
}
