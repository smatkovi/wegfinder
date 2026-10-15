import QtQuick 1.1
import "wf.js" as W

// Schiebekarte (Web-Mercator, 256-px-Kacheln von OpenStreetMap) mit
// Linien, Markern und Punkten darauf -- ohne Kartenbibliothek, nach dem
// Muster der Karte in Fahrplan AT.
//
// Am N9 ist einiges anders:
// * Kacheln kommen ueber den Dienst (127.0.0.1, siehe dienst/src/kacheln.rs),
//   das Qt 4.7 kann den Kachelserver selbst nicht erreichen.
// * Kein Canvas: jede Teilstrecke ist ein gedrehtes Rechteck.
// * Alles liegt in einer Ebene relativ zu einem Bezugspunkt. Beim Schieben
//   aendert sich nur deren Lage, nicht jedes Element -- und die Zahlen
//   bleiben klein (qreal ist auf ARM float, bei Weltpixeln um 2*10^7 waere
//   das pixelungenau).
// * sparsam: Kacheln eine Stufe tiefer, doppelt so gross gezeigt -- ein
//   Viertel der Daten, fuers 2G-Netz.
Item {
    id: karte
    clip: true

    property int zoom: 14
    property real mitteX: 0          // Weltpixel der Zoomstufe
    property real mitteY: 0
    property int minZoom: 5
    property int maxZoom: 18
    property string kachelBasis: ""  // "http://127.0.0.1:<port>", leer = keine Kacheln
    property bool sparsam: false
    property variant linien: []      // [{farbe, art, punkte: [[lat, lon], ...]}]
    property variant marker: []      // [{lat, lon, farbe, rolle, name}]
    property variant punkte: []      // [{lat, lon, farbe, art, ...}] (Umgebung)
    property int gewaehlt: -1
    property bool standortSichtbar: false
    property real standortLat: 0
    property real standortLon: 0

    signal punktAngetippt(int index)
    signal leerAngetippt()
    signal gehalten(real lat, real lon)
    signal bewegt()

    // abgeleitet
    property real ursprungX: mitteX - width / 2
    property real ursprungY: mitteY - height / 2
    property int kachelZoom: sparsam && zoom > minZoom ? zoom - 1 : zoom
    property int kachelGroesse: kachelZoom < zoom ? 512 : 256
    property int ersteX: Math.floor(ursprungX / kachelGroesse)
    property int ersteY: Math.floor(ursprungY / kachelGroesse)
    property int spalten: Math.ceil(width / kachelGroesse) + 1
    property int zeilen: Math.ceil(height / kachelGroesse) + 1
    property int kachelnJeAchse: Math.pow(2, kachelZoom)
    property real bezugX: 0
    property real bezugY: 0
    property variant strecken: []

    function mitteLat() { return W.yZuLat(mitteY, zoom) }
    function mitteLon() { return W.xZuLon(mitteX, zoom) }

    function neuBezug() {
        bezugX = Math.round(mitteX)
        bezugY = Math.round(mitteY)
        var s = W.strecken(linien, zoom)
        for (var i = 0; i < s.length; ++i) {
            s[i].x -= bezugX
            s[i].y -= bezugY
        }
        strecken = s
    }
    onLinienChanged: neuBezug()

    function zentrieren(lat, lon, z) {
        zoom = Math.max(minZoom, Math.min(maxZoom, z))
        mitteX = W.lonZuX(lon, zoom)
        mitteY = W.latZuY(lat, zoom)
        neuBezug()
    }

    function einpassen(r) {
        if (!r || r.n < r.s || r.o < r.w || width <= 0)
            return false
        var z = W.zoomFuer(r, width - 60, height - 90, minZoom, maxZoom - 1)
        zoom = z
        mitteX = (W.lonZuX(r.w, z) + W.lonZuX(r.o, z)) / 2
        mitteY = (W.latZuY(r.n, z) + W.latZuY(r.s, z)) / 2
        neuBezug()
        return true
    }

    function zoomen(neu, ax, ay) {
        neu = Math.max(minZoom, Math.min(maxZoom, neu))
        if (neu === zoom)
            return
        var wx = ursprungX + ax, wy = ursprungY + ay
        var f = Math.pow(2, neu - zoom)
        mitteX = wx * f - (ax - width / 2)
        mitteY = wy * f - (ay - height / 2)
        zoom = neu
        neuBezug()
        bewegt()
    }

    // sichtbarer Ausschnitt {n, s, w, o}
    function rahmen() {
        return { n: W.yZuLat(ursprungY, zoom), s: W.yZuLat(ursprungY + height, zoom),
                 w: W.xZuLon(ursprungX, zoom), o: W.xZuLon(ursprungX + width, zoom) }
    }

    function punktX(lon) { return W.lonZuX(lon, zoom) - bezugX }
    function punktY(lat) { return W.latZuY(lat, zoom) - bezugY }

    Rectangle {
        anchors.fill: parent
        color: karte.kachelBasis !== "" ? "#e8e6e1" : "#dcdcd6"
    }

    Item {
        id: ebene
        x: karte.bezugX - karte.ursprungX
        y: karte.bezugY - karte.ursprungY
        transform: Scale { id: zwick; origin.x: 0; origin.y: 0; xScale: 1; yScale: 1 }

        Repeater {
            model: karte.kachelBasis !== "" ? karte.spalten * karte.zeilen : 0
            Image {
                property int tx: karte.ersteX + (index % karte.spalten)
                property int ty: karte.ersteY + Math.floor(index / karte.spalten)
                property int wx: ((tx % karte.kachelnJeAchse) + karte.kachelnJeAchse) % karte.kachelnJeAchse
                x: tx * karte.kachelGroesse - karte.bezugX
                y: ty * karte.kachelGroesse - karte.bezugY
                width: karte.kachelGroesse
                height: karte.kachelGroesse
                visible: ty >= 0 && ty < karte.kachelnJeAchse
                asynchronous: true
                smooth: karte.kachelGroesse > 256
                source: visible ? karte.kachelBasis + "/" + karte.kachelZoom + "/" + wx + "/" + ty + ".png" : ""
            }
        }

        // Linien: erst ein weisser Rand, dann die Farbe
        Repeater {
            model: karte.strecken
            Rectangle {
                x: modelData.x
                y: modelData.y - height / 2
                width: modelData.laenge
                height: modelData.fuss ? 8 : 12
                radius: height / 2
                color: "#ffffff"
                opacity: 0.85
                smooth: true
                transformOrigin: Item.Left
                rotation: modelData.winkel
            }
        }
        Repeater {
            model: karte.strecken
            Rectangle {
                x: modelData.x
                y: modelData.y - height / 2
                width: modelData.laenge
                height: modelData.fuss ? 4 : 7
                radius: height / 2
                color: modelData.farbe
                smooth: true
                transformOrigin: Item.Left
                rotation: modelData.winkel
            }
        }

        // Halte, Umstiege, Start und Ziel
        Repeater {
            model: karte.marker
            Rectangle {
                property bool klein: modelData.rolle === "halt"
                width: klein ? 10 : (modelData.rolle === "umstieg" ? 16 : 22)
                height: width
                radius: width / 2
                x: karte.punktX(modelData.lon) - width / 2
                y: karte.punktY(modelData.lat) - height / 2
                color: modelData.rolle === "ziel" ? W.ROSA : (klein ? modelData.farbe : "white")
                border.width: klein ? 2 : 4
                border.color: modelData.rolle === "start" ? W.BLAU
                            : (modelData.rolle === "ziel" ? "white" : (klein ? "white" : modelData.farbe))
                smooth: true
            }
        }

        // Punkte der Umgebung
        Repeater {
            model: karte.punkte
            Rectangle {
                property bool gross: karte.zoom >= 15 || index === karte.gewaehlt
                property bool gew: index === karte.gewaehlt
                width: gew ? 40 : (gross ? 30 : 14)
                height: width
                radius: width / 2
                x: karte.punktX(modelData.lon) - width / 2
                y: karte.punktY(modelData.lat) - height / 2
                z: gew ? 2 : (modelData.punktart === "station" ? 1 : 0)
                color: modelData.farbe
                opacity: modelData.verfuegbar === false ? 0.5 : 1
                border.width: gew ? 3 : 2
                border.color: "white"
                smooth: true
                Image {
                    anchors.centerIn: parent
                    visible: parent.gross
                    width: parent.width - 10
                    height: width
                    smooth: true
                    source: W.sinnbild(modelData.punktart === "station" ? W.artAusTypen(modelData.arten) : modelData.art)
                }
            }
        }

        // eigener Standort
        Rectangle {
            visible: karte.standortSichtbar
            width: 22
            height: 22
            radius: 11
            x: karte.punktX(karte.standortLon) - 11
            y: karte.punktY(karte.standortLat) - 11
            color: W.BLAU
            border.width: 4
            border.color: "white"
            smooth: true
            z: 3
        }
    }

    PinchArea {
        id: zwicken
        anchors.fill: parent
        property bool laeuft: false
        onPinchStarted: {
            laeuft = true
            zwick.origin.x = pinch.center.x - ebene.x
            zwick.origin.y = pinch.center.y - ebene.y
        }
        onPinchUpdated: {
            var s = Math.max(0.5, Math.min(2.0, pinch.scale))
            zwick.xScale = s
            zwick.yScale = s
        }
        onPinchFinished: {
            var s = zwick.xScale
            zwick.xScale = 1
            zwick.yScale = 1
            laeuft = false
            if (s > 1.35)
                karte.zoomen(karte.zoom + (s > 1.8 ? 2 : 1), pinch.center.x, pinch.center.y)
            else if (s < 0.75)
                karte.zoomen(karte.zoom - (s < 0.55 ? 2 : 1), pinch.center.x, pinch.center.y)
        }

        MouseArea {
            id: maus
            anchors.fill: parent
            property real letzteX
            property real letzteY
            property real weg: 0
            onPressed: { letzteX = mouse.x; letzteY = mouse.y; weg = 0 }
            onPositionChanged: {
                if (zwicken.laeuft) {
                    letzteX = mouse.x
                    letzteY = mouse.y
                    return
                }
                var dx = mouse.x - letzteX, dy = mouse.y - letzteY
                weg += Math.abs(dx) + Math.abs(dy)
                karte.mitteX -= dx
                karte.mitteY -= dy
                letzteX = mouse.x
                letzteY = mouse.y
            }
            onReleased: if (weg > 12) karte.bewegt()
            onClicked: {
                if (weg > 12)
                    return
                // naechster Punkt im Umkreis von 36 px
                var beste = -1, abst = 36 * 36
                for (var i = 0; i < karte.punkte.length; ++i) {
                    var p = karte.punkte[i]
                    var px = W.lonZuX(p.lon, karte.zoom) - karte.ursprungX
                    var py = W.latZuY(p.lat, karte.zoom) - karte.ursprungY
                    var d = (px - mouse.x) * (px - mouse.x) + (py - mouse.y) * (py - mouse.y)
                    if (d < abst) { abst = d; beste = i }
                }
                if (beste >= 0)
                    karte.punktAngetippt(beste)
                else
                    karte.leerAngetippt()
            }
            onDoubleClicked: karte.zoomen(karte.zoom + 1, mouse.x, mouse.y)
            onPressAndHold: {
                if (weg > 12)
                    return
                karte.gehalten(W.yZuLat(karte.ursprungY + mouse.y, karte.zoom),
                               W.xZuLon(karte.ursprungX + mouse.x, karte.zoom))
            }
        }
    }

    Text {
        anchors { left: parent.left; bottom: parent.bottom; margins: 4 }
        visible: karte.kachelBasis !== ""
        text: "© OpenStreetMap-Mitwirkende"
        color: "#555555"
        font.pixelSize: 14
        Rectangle { anchors.fill: parent; anchors.margins: -2; z: -1; color: "#b3ffffff" }
    }
}
