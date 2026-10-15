import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../wf.js" as W

// Karte einer Route (route) oder eines Fahrtverlaufs (fahrt: {titel,
// farbe, halte, linie}). Fusswege lassen sich an Pure Maps uebergeben (wie
// in Fahrplan AT: ShowRoute, sonst GPX und das Ziel als Punkt).
Page {
    id: seite
    property var route: null
    property var fahrt: null
    property string titel: route ? route.ab.zeit + " – " + route.an.zeit : (fahrt ? fahrt.titel : "Karte")
    property string modus: fenster.kartenModus()
    property var rahmen: null
    property bool folgen: false
    property var fussweg: null      // erster Fussweg der Route, fuer Pure Maps
    allowedOrientations: Orientation.All

    function zumStandort() {
        if (!folgen) {
            folgen = true
            fenster.standortAn()
        }
        if (fenster.standortDa)
            karte.zentrieren(fenster.standortLat, fenster.standortLon, Math.max(karte.zoom, 15))
        else
            fenster.meldung("Warte auf den Standort …")
    }
    Connections {
        target: fenster
        onStandortDaChanged: if (seite.folgen && fenster.standortDa) karte.zentrieren(fenster.standortLat, fenster.standortLon, Math.max(karte.zoom, 15))
    }
    onStatusChanged: if (status === PageStatus.Deactivating && folgen) { folgen = false; fenster.standortAus() }

    Component.onCompleted: {
        if (route) {
            laden.senden("karte", { route: route.id })
            for (var i = 0; i < route.abschnitte.length; ++i)
                if (route.abschnitte[i].art === "fuss" && !fussweg) fussweg = route.abschnitte[i]
        } else if (fahrt) {
            var halte = []
            for (var j = 0; j < fahrt.halte.length; ++j) {
                var h = fahrt.halte[j]
                halte.push({ lat: h.lat, lon: h.lon, name: h.name, farbe: fahrt.farbe,
                             rolle: j === 0 ? "start" : (j === fahrt.halte.length - 1 ? "ziel" : "halt") })
            }
            karte.marker = halte
            karte.linien = [{ farbe: fahrt.farbe, art: "zug", punkte: fahrt.linie }]
            rahmen = W.rahmenUm(halte)
            einpassenSpaeter.start()
        }
    }
    Timer { id: einpassenSpaeter; interval: 50; onTriggered: karte.einpassen(seite.rahmen) }

    // Punkte des ersten Fusswegs aus den Kartenlinien (fuer Pure Maps)
    property var fussPunkte: []
    Anfrage {
        id: laden
        onFertig: {
            karte.marker = daten.marker
            karte.linien = daten.linien
            seite.rahmen = daten.rahmen
            for (var i = 0; i < daten.linien.length; ++i)
                if (daten.linien[i].art === "fuss") {
                    var p = [], l = daten.linien[i].punkte
                    for (var j = 0; j < l.length; ++j) p.push({ lat: l[j][0], lon: l[j][1] })
                    seite.fussPunkte = p
                    break
                }
            einpassenSpaeter.start()
        }
        onFehler: fenster.meldung(W.fehlerText(text))
    }

    Karte {
        id: karte
        anchors.fill: parent
        kachelBasis: seite.modus === "aus" ? "" : fenster.kachelBasis
        sparsam: seite.modus === "sparsam"
        standortSichtbar: seite.folgen && fenster.standortDa
        standortLat: fenster.standortLat
        standortLon: fenster.standortLon
        Component.onCompleted: zentrieren(W.WIEN.lat, W.WIEN.lon, 12)
    }

    // Kopf mit Zugmenue (nur der Streifen oben, damit die Karte darunter
    // frei verschiebbar bleibt -- wie in Fahrplan AT)
    SilicaFlickable {
        id: zug
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: kopf.height
        contentHeight: height + 1
        z: 10
        PullDownMenu {
            MenuItem {
                text: "Fußweg in Pure Maps"
                visible: Karten.pureMapsDa && !!seite.fussweg && seite.fussPunkte.length > 1
                onClicked: Karten.zeigeWeg(seite.fussweg.von.name, seite.fussweg.von.lat, seite.fussweg.von.lon,
                                           seite.fussweg.nach.name, seite.fussweg.nach.lat, seite.fussweg.nach.lon,
                                           seite.fussPunkte)
            }
            MenuItem {
                text: "Ziel in Pure Maps"
                visible: Karten.pureMapsDa && !!seite.route
                onClicked: Karten.zeigeOrt(seite.route.an.name, seite.route.an.lat, seite.route.an.lon)
            }
            MenuItem {
                text: seite.modus === "voll" ? "Hintergrund sparsam (¼ der Daten)" : (seite.modus === "sparsam" ? "Ohne Hintergrund" : "Hintergrund voll")
                onClicked: seite.modus = seite.modus === "voll" ? "sparsam" : (seite.modus === "sparsam" ? "aus" : "voll")
            }
        }
        Rectangle {
            id: kopf
            width: parent.width
            height: kopfSpalte.height + Theme.paddingMedium * 2
            color: Theme.rgba(Theme.overlayBackgroundColor, 0.85)
            Column {
                id: kopfSpalte
                anchors { left: parent.left; right: parent.right; margins: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                Label {
                    width: parent.width
                    text: seite.titel
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeLarge
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    visible: text !== ""
                    text: seite.modus === "aus" ? "Ohne Kartenhintergrund" : (seite.modus === "sparsam" ? "Kartenhintergrund sparsam" : "")
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }
            Label {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                text: "▾"
                font.pixelSize: Theme.fontSizeTiny
                color: Theme.secondaryColor
            }
        }
    }

    Column {
        anchors { right: parent.right; rightMargin: Theme.paddingMedium; bottom: parent.bottom; bottomMargin: Theme.itemSizeSmall }
        spacing: Theme.paddingSmall
        z: 10
        Repeater {
            model: [
                { bild: "plus", was: "plus" },
                { bild: "minus", was: "minus" },
                { bild: "einpassen", was: "einpassen" },
                { bild: "standort", was: "standort" }
            ]
            IconButton {
                icon.source: "../bilder/" + modelData.bild + ".png"
                icon.width: Theme.iconSizeMedium
                icon.height: Theme.iconSizeMedium
                Rectangle { anchors.fill: parent; z: -1; radius: width / 2; color: Theme.rgba("#000000", 0.45) }
                onClicked: {
                    if (modelData.was === "plus") karte.zoomen(karte.zoom + 1, karte.width / 2, karte.height / 2)
                    else if (modelData.was === "minus") karte.zoomen(karte.zoom - 1, karte.width / 2, karte.height / 2)
                    else if (modelData.was === "einpassen") karte.einpassen(seite.rahmen)
                    else seite.zumStandort()
                }
            }
        }
    }
    Label {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Theme.paddingLarge; bottomMargin: Theme.itemSizeSmall }
        visible: Karten.meldung !== ""
        text: Karten.meldung
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.highlightColor
        z: 10
        Rectangle { anchors.fill: parent; anchors.margins: -Theme.paddingSmall; z: -1; radius: Theme.paddingSmall; color: Theme.rgba(Theme.overlayBackgroundColor, 0.85) }
    }
}
