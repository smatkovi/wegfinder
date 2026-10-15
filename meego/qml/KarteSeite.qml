import QtQuick 1.1
import com.nokia.meego 1.1
import "wf.js" as W

// Karte einer Route (route) oder eines Fahrtverlaufs (fahrt: {linie,
// halte, farbe}). Die Linien kommen sofort -- auch ohne Kartenhintergrund,
// der im 2G-Netz lange braucht und sich hier abschalten laesst.
Page {
    id: seite
    property variant route: null
    property variant fahrt: null
    property string titel: route ? route.ab.zeit + " – " + route.an.zeit : (fahrt ? fahrt.titel : "Karte")
    property string modus: fenster.kartenModus()   // voll | sparsam | aus
    property variant rahmen: null
    property bool folgen: false

    tools: ToolBarLayout {
        ToolIcon { iconId: "toolbar-back"; onClicked: pageStack.pop() }
        ToolIcon { iconSource: "bilder/minus.png"; onClicked: karte.zoomen(karte.zoom - 1, karte.width / 2, karte.height / 2) }
        ToolIcon { iconSource: "bilder/plus.png"; onClicked: karte.zoomen(karte.zoom + 1, karte.width / 2, karte.height / 2) }
        ToolIcon { iconSource: "bilder/einpassen.png"; onClicked: karte.einpassen(seite.rahmen) }
        ToolIcon { iconSource: "bilder/standort.png"; onClicked: seite.zumStandort() }
        ToolIcon { iconId: "toolbar-view-menu"; onClicked: menue.open() }
    }

    Menu {
        id: menue
        MenuLayout {
            MenuItem { text: "Hintergrund voll"; onClicked: seite.modus = "voll" }
            MenuItem { text: "Hintergrund sparsam (¼ der Daten)"; onClicked: seite.modus = "sparsam" }
            MenuItem { text: "Ohne Hintergrund"; onClicked: seite.modus = "aus" }
        }
    }

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
        } else if (fahrt) {
            var halte = [], i
            for (i = 0; i < fahrt.halte.length; ++i) {
                var h = fahrt.halte[i]
                halte.push({ lat: h.lat, lon: h.lon, name: h.name, farbe: fahrt.farbe,
                             rolle: i === 0 ? "start" : (i === fahrt.halte.length - 1 ? "ziel" : "halt") })
            }
            karte.marker = halte
            karte.linien = [{ farbe: fahrt.farbe, art: "zug", punkte: fahrt.linie }]
            rahmen = W.rahmenUm(halte)
            einpassenSpaeter.start()
        }
    }
    Timer { id: einpassenSpaeter; interval: 50; onTriggered: karte.einpassen(seite.rahmen) }

    Anfrage {
        id: laden
        onFertig: {
            karte.marker = daten.marker
            karte.linien = daten.linien
            seite.rahmen = daten.rahmen
            einpassenSpaeter.start()
        }
        onFehler: fenster.meldung(W.fehlerText(text))
    }

    Kopf {
        id: kopf
        anchors.top: parent.top
        titel: seite.titel
        untertitel: seite.modus === "aus" ? "Ohne Kartenhintergrund" : (seite.modus === "sparsam" ? "Kartenhintergrund sparsam" : "")
        laedt: laden.laeuft
    }

    Karte {
        id: karte
        anchors { top: kopf.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        kachelBasis: seite.modus === "aus" ? "" : fenster.kachelBasis
        sparsam: seite.modus === "sparsam"
        standortSichtbar: seite.folgen && fenster.standortDa
        standortLat: fenster.standortLat
        standortLon: fenster.standortLon
        Component.onCompleted: zentrieren(W.WIEN.lat, W.WIEN.lon, 12)
    }
}
