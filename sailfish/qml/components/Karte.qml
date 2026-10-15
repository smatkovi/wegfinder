import QtQuick 2.6
import Sailfish.Silica 1.0
import "../wf.js" as W

// Schiebekarte (Web-Mercator, 256-px-Kacheln von OpenStreetMap) mit Linien,
// Markern und Punkten -- ohne Kartenbibliothek, wie in Fahrplan AT; die
// Linien zeichnet ein Canvas. Gleiche Schnittstelle wie meego/qml/Karte.qml.
//
// Die Kacheln kommen ueber den Dienst (127.0.0.1): ein Zwischenspeicher
// fuer beide Systeme, 30 Tage, und der Sparmodus (eine Zoomstufe tiefer,
// doppelt so gross) gilt auch hier.
Item {
    id: karte
    clip: true

    property int zoom: 14
    property real mitteX: 0
    property real mitteY: 0
    property int minZoom: 5
    property int maxZoom: 18
    property string kachelBasis: ""
    property bool sparsam: false
    property var linien: []
    property var marker: []
    property var punkte: []
    property int gewaehlt: -1
    property bool standortSichtbar: false
    property real standortLat: 0
    property real standortLon: 0

    signal punktAngetippt(int index)
    signal leerAngetippt()
    signal gehalten(real lat, real lon)
    signal bewegt()

    // Logische Pixel: auf dichten Bildschirmen (Jolla Phone 2026) waeren
    // 256-px-Kacheln 1:1 winzig. Die Kacheln und Marker werden um skala
    // vergroessert, die Linien zeichnet der Canvas im Geraeteraster.
    property real skala: Math.max(1, Math.round(Theme.pixelRatio * 2) / 2)
    readonly property real lb: width / skala
    readonly property real lh: height / skala
    readonly property real e: Theme.paddingLarge / skala     // Masseinheit fuer Marker
    readonly property real ursprungX: mitteX - lb / 2
    readonly property real ursprungY: mitteY - lh / 2
    readonly property int kachelZoom: sparsam && zoom > minZoom ? zoom - 1 : zoom
    readonly property int kachelGroesse: kachelZoom < zoom ? 512 : 256
    readonly property int ersteX: Math.floor(ursprungX / kachelGroesse)
    readonly property int ersteY: Math.floor(ursprungY / kachelGroesse)
    readonly property int spalten: Math.ceil(lb / kachelGroesse) + 1
    readonly property int zeilen: Math.ceil(lh / kachelGroesse) + 1
    readonly property int kachelnJeAchse: Math.pow(2, kachelZoom)

    function mitteLat() { return W.yZuLat(mitteY, zoom) }
    function mitteLon() { return W.xZuLon(mitteX, zoom) }

    function zentrieren(lat, lon, z) {
        zoom = Math.max(minZoom, Math.min(maxZoom, z))
        mitteX = W.lonZuX(lon, zoom)
        mitteY = W.latZuY(lat, zoom)
        linienEbene.requestPaint()
    }
    function einpassen(r) {
        if (!r || r.n < r.s || r.o < r.w || width <= 0)
            return false
        var z = W.zoomFuer(r, (width - Theme.itemSizeMedium) / skala, (height - Theme.itemSizeLarge * 1.5) / skala, minZoom, maxZoom - 1)
        zoom = z
        mitteX = (W.lonZuX(r.w, z) + W.lonZuX(r.o, z)) / 2
        mitteY = (W.latZuY(r.n, z) + W.latZuY(r.s, z)) / 2
        linienEbene.requestPaint()
        return true
    }
    function zoomen(neu, ax, ay) {
        neu = Math.max(minZoom, Math.min(maxZoom, neu))
        if (neu === zoom)
            return
        // ax, ay in Geraetepixeln
        ax = ax / skala
        ay = ay / skala
        var wx = ursprungX + ax, wy = ursprungY + ay
        var f = Math.pow(2, neu - zoom)
        mitteX = wx * f - (ax - lb / 2)
        mitteY = wy * f - (ay - lh / 2)
        zoom = neu
        linienEbene.requestPaint()
        bewegt()
    }
    function rahmen() {
        return { n: W.yZuLat(ursprungY, zoom), s: W.yZuLat(ursprungY + lh, zoom),
                 w: W.xZuLon(ursprungX, zoom), o: W.xZuLon(ursprungX + lb, zoom) }
    }
    function px(lon) { return W.lonZuX(lon, zoom) - ursprungX }
    function py(lat) { return W.latZuY(lat, zoom) - ursprungY }

    onLinienChanged: linienEbene.requestPaint()
    onMitteXChanged: linienEbene.requestPaint()
    onMitteYChanged: linienEbene.requestPaint()

    Rectangle {
        anchors.fill: parent
        color: karte.kachelBasis !== "" ? "#e8e6e1" : "#dcdcd6"
    }

    Item {
        id: zwickEbene
        anchors.fill: parent
        transform: Scale { id: zwick; origin.x: 0; origin.y: 0; xScale: 1; yScale: 1 }

        // Kacheln (logische Pixel, vergroessert)
        Item {
            id: inhalt
            width: karte.lb
            height: karte.lh
            transform: Scale { xScale: karte.skala; yScale: karte.skala }

            Repeater {
                model: karte.kachelBasis !== "" ? karte.spalten * karte.zeilen : 0
                Image {
                    readonly property int tx: karte.ersteX + (index % karte.spalten)
                    readonly property int ty: karte.ersteY + Math.floor(index / karte.spalten)
                    readonly property int wx: ((tx % karte.kachelnJeAchse) + karte.kachelnJeAchse) % karte.kachelnJeAchse
                    x: tx * karte.kachelGroesse - karte.ursprungX
                    y: ty * karte.kachelGroesse - karte.ursprungY
                    width: karte.kachelGroesse
                    height: karte.kachelGroesse
                    visible: ty >= 0 && ty < karte.kachelnJeAchse
                    asynchronous: true
                    smooth: karte.kachelGroesse > 256
                    source: visible ? karte.kachelBasis + "/" + karte.kachelZoom + "/" + wx + "/" + ty + ".png" : ""
                }
            }
        }

        // Linien im Geraeteraster
        Canvas {
            id: linienEbene
            anchors.fill: parent
            renderStrategy: Canvas.Cooperative
            onAvailableChanged: if (available) requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                for (var durchgang = 0; durchgang < 2; ++durchgang) {
                    for (var i = 0; i < karte.linien.length; ++i) {
                        var l = karte.linien[i], p = l.punkte
                        if (!p || p.length < 2)
                            continue
                        ctx.beginPath()
                        for (var j = 0; j < p.length; ++j) {
                            var x = karte.px(p[j][1]) * karte.skala, y = karte.py(p[j][0]) * karte.skala
                            if (j === 0) ctx.moveTo(x, y)
                            else ctx.lineTo(x, y)
                        }
                        var fuss = l.art === "fuss"
                        if (durchgang === 0) {
                            ctx.lineWidth = fuss ? Theme.paddingSmall * 2 : Theme.paddingSmall * 3
                            ctx.strokeStyle = "rgba(255,255,255,0.9)"
                        } else {
                            ctx.lineWidth = fuss ? Theme.paddingSmall : Theme.paddingSmall * 1.8
                            ctx.strokeStyle = l.farbe
                        }
                        ctx.stroke()
                    }
                }
            }
        }

        // Marker und Punkte ueber den Linien
        Item {
            width: karte.lb
            height: karte.lh
            transform: Scale { xScale: karte.skala; yScale: karte.skala }

            Repeater {
                model: karte.marker
                Rectangle {
                    readonly property bool klein: modelData.rolle === "halt"
                    width: klein ? karte.e : (modelData.rolle === "umstieg" ? karte.e * 1.5 : karte.e * 2)
                    height: width
                    radius: width / 2
                    x: karte.px(modelData.lon) - width / 2
                    y: karte.py(modelData.lat) - height / 2
                    color: modelData.rolle === "ziel" ? W.ROSA : (klein ? modelData.farbe : "white")
                    border.width: klein ? karte.e / 6 : karte.e / 3.5
                    border.color: modelData.rolle === "start" ? W.BLAU
                                : (modelData.rolle === "ziel" ? "white" : (klein ? "white" : modelData.farbe))
                }
            }

            Repeater {
                model: karte.punkte
                Rectangle {
                    readonly property bool gew: index === karte.gewaehlt
                    readonly property bool gross: karte.zoom >= 15 || gew
                    width: gew ? karte.e * 3.3 : (gross ? karte.e * 2.4 : karte.e * 1.1)
                    height: width
                    radius: width / 2
                    x: karte.px(modelData.lon) - width / 2
                    y: karte.py(modelData.lat) - height / 2
                    z: gew ? 2 : (modelData.punktart === "station" ? 1 : 0)
                    color: modelData.farbe
                    opacity: modelData.verfuegbar === false ? 0.5 : 1
                    border.width: gew ? karte.e / 4 : karte.e / 8
                    border.color: "white"
                    Image {
                        anchors.centerIn: parent
                        visible: parent.gross
                        width: parent.width * 0.68
                        height: width
                        smooth: true
                        source: "../" + W.sinnbild(modelData.punktart === "station" ? W.artAusTypen(modelData.arten) : modelData.art)
                    }
                }
            }

            Rectangle {
                visible: karte.standortSichtbar
                width: karte.e * 1.6
                height: width
                radius: width / 2
                x: karte.px(karte.standortLon) - width / 2
                y: karte.py(karte.standortLat) - height / 2
                color: W.BLAU
                border.width: karte.e / 3.5
                border.color: "white"
                z: 3
            }
        }
    }

    PinchArea {
        id: zwicken
        anchors.fill: parent
        property bool laeuft: false
        onPinchStarted: {
            laeuft = true
            zwick.origin.x = pinch.center.x
            zwick.origin.y = pinch.center.y
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
            anchors.fill: parent
            property real letzteX
            property real letzteY
            property real weg: 0
            preventStealing: true
            onPressed: { letzteX = mouse.x; letzteY = mouse.y; weg = 0 }
            onPositionChanged: {
                if (zwicken.laeuft) {
                    letzteX = mouse.x
                    letzteY = mouse.y
                    return
                }
                var dx = mouse.x - letzteX, dy = mouse.y - letzteY
                weg += Math.abs(dx) + Math.abs(dy)
                karte.mitteX -= dx / karte.skala
                karte.mitteY -= dy / karte.skala
                letzteX = mouse.x
                letzteY = mouse.y
            }
            onReleased: if (weg > Theme.startDragDistance) karte.bewegt()
            onClicked: {
                if (weg > Theme.startDragDistance)
                    return
                var beste = -1, abst = Theme.itemSizeExtraSmall * Theme.itemSizeExtraSmall * 0.5
                for (var i = 0; i < karte.punkte.length; ++i) {
                    var p = karte.punkte[i]
                    var dx = karte.px(p.lon) * karte.skala - mouse.x, dy = karte.py(p.lat) * karte.skala - mouse.y
                    var d = dx * dx + dy * dy
                    if (d < abst) { abst = d; beste = i }
                }
                if (beste >= 0)
                    karte.punktAngetippt(beste)
                else
                    karte.leerAngetippt()
            }
            onDoubleClicked: karte.zoomen(karte.zoom + 1, mouse.x, mouse.y)
            onPressAndHold: {
                if (weg > Theme.startDragDistance)
                    return
                karte.gehalten(W.yZuLat(karte.ursprungY + mouse.y / karte.skala, karte.zoom),
                               W.xZuLon(karte.ursprungX + mouse.x / karte.skala, karte.zoom))
            }
        }
    }

    Label {
        anchors { left: parent.left; bottom: parent.bottom; margins: Theme.paddingSmall }
        visible: karte.kachelBasis !== ""
        text: "© OpenStreetMap-Mitwirkende"
        color: "#555555"
        font.pixelSize: Theme.fontSizeTiny
        Rectangle { anchors.fill: parent; anchors.margins: -2; z: -1; color: "#b3ffffff" }
    }
}
