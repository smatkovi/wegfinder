import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../wf.js" as W

// In der Naehe: Haltestellen, Leihraeder, E-Scooter, Carsharing, Taxi,
// Parken. Antippen zeigt die Angaben; Haltestellen fuehren zu den
// Abfahrten. Gebucht wird nichts. Im WLAN laedt die Seite nach jedem
// Verschieben neu, sonst auf Knopfdruck.
Page {
    id: seite
    allowedOrientations: Orientation.All
    property var filterListe: [{ id: "", titel: "Alles" }]
    property string filter: fenster.einst.umgebung_filter !== undefined ? fenster.einst.umgebung_filter : "public"
    property string filterName: filter === "" ? "Alles" : "Öffis"
    property var punkte: []
    property int gesamt: 0
    property int gewaehlt: -1
    readonly property bool hatP: gewaehlt >= 0 && gewaehlt < punkte.length
    readonly property var p: hatP ? punkte[gewaehlt] : null
    property bool veraltet: false
    property bool erstesMal: true
    property string modus: fenster.kartenModus()

    onStatusChanged: {
        if (status === PageStatus.Active) fenster.standortAn()
        else if (status === PageStatus.Deactivating) fenster.standortAus()
    }
    Component.onCompleted: {
        filterAnfrage.senden("filter", {})
        if (fenster.standortDa)
            karte.zentrieren(fenster.standortLat, fenster.standortLon, 16)
        else
            karte.zentrieren(W.WIEN.lat, W.WIEN.lon, 15)
        startZeit.start()
    }
    Timer { id: startZeit; interval: 150; onTriggered: seite.laden() }
    Connections {
        target: fenster
        onStandortDaChanged: {
            if (fenster.standortDa && seite.erstesMal) {
                karte.zentrieren(fenster.standortLat, fenster.standortLon, 16)
                seite.laden()
            }
        }
    }

    function zumStandort() {
        if (fenster.standortDa) {
            karte.zentrieren(fenster.standortLat, fenster.standortLon, Math.max(karte.zoom, 16))
            laden()
        } else {
            fenster.meldung("Warte auf den Standort …")
        }
    }
    function laden() {
        if (karte.width <= 0)
            return
        if (fenster.standortDa)
            erstesMal = false
        var r = karte.rahmen()
        gewaehlt = -1
        veraltet = false
        anfrage.senden("umgebung", { n: r.n, s: r.s, w: r.w, o: r.o, zoom: karte.zoom, filter: seite.filter,
                                     breite: Math.round(karte.lb), hoehe: Math.round(karte.lh) })
    }
    function hinZuStart(o) {
        var start = pageStack.find(function(pg) { return pg.suchen !== undefined && pg.nach !== undefined })
        if (start) {
            start.nach = o
            pageStack.pop(start)
        }
    }

    Anfrage {
        id: anfrage
        onFertig: {
            seite.punkte = daten.punkte
            seite.gesamt = daten.gesamt
            if (daten.punkte.length === 0)
                fenster.meldung("Hier nichts gefunden – Ausschnitt verschieben oder Filter ändern.")
        }
        onFehler: fenster.meldung(W.fehlerText(text))
    }
    Anfrage {
        id: filterAnfrage
        onFertig: {
            var l = [{ id: "", titel: "Alles" }]
            for (var i = 0; i < daten.length; ++i) {
                l.push(daten[i])
                if (daten[i].id === seite.filter) seite.filterName = daten[i].titel
            }
            seite.filterListe = l
        }
    }
    Anfrage { id: merken; onFertig: fenster.einst = daten }

    Karte {
        id: karte
        anchors.fill: parent
        kachelBasis: seite.modus === "aus" ? "" : fenster.kachelBasis
        sparsam: seite.modus === "sparsam"
        punkte: seite.punkte
        gewaehlt: seite.gewaehlt
        standortSichtbar: fenster.standortDa
        standortLat: fenster.standortLat
        standortLon: fenster.standortLon
        onPunktAngetippt: seite.gewaehlt = index
        onLeerAngetippt: seite.gewaehlt = -1
        onBewegt: {
            if (fenster.wlan) nachladen.restart()
            else seite.veraltet = true
        }
        onGehalten: {
            seite.hinZuStart(W.kartenOrt(lat, lon))
            fenster.meldung("Ziel: Punkt auf der Karte")
        }
    }
    Timer { id: nachladen; interval: 900; onTriggered: seite.laden() }

    SilicaFlickable {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: kopf.height
        contentHeight: height + 1
        z: 10
        PullDownMenu {
            busy: anfrage.laeuft
            Repeater {
                model: seite.filterListe
                MenuItem {
                    text: modelData.titel
                    font.bold: modelData.id === seite.filter
                    onClicked: {
                        seite.filter = modelData.id
                        seite.filterName = modelData.titel
                        merken.senden("einstellungen_setzen", { umgebung_filter: modelData.id })
                        seite.laden()
                    }
                }
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
                Label { width: parent.width; text: "In der Nähe"; color: Theme.highlightColor; font.pixelSize: Theme.fontSizeLarge }
                Label {
                    width: parent.width
                    text: seite.filterName + (seite.punkte.length > 0
                          ? " · " + (seite.gesamt > seite.punkte.length ? "die nächsten " + seite.punkte.length + " von " + seite.gesamt : seite.punkte.length + " Treffer")
                          : "") + "  ▾ Filter"
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                }
            }
        }
    }

    Button {
        anchors { top: parent.top; topMargin: Theme.itemSizeLarge * 1.2; horizontalCenter: parent.horizontalCenter }
        visible: seite.veraltet && !anfrage.laeuft
        text: "Hier suchen"
        z: 10
        onClicked: seite.laden()
    }

    Column {
        anchors { right: parent.right; rightMargin: Theme.paddingMedium; bottom: feld.visible ? feld.top : parent.bottom
                  bottomMargin: Theme.itemSizeSmall }
        spacing: Theme.paddingSmall
        z: 10
        Repeater {
            model: ["plus", "minus", "standort"]
            IconButton {
                icon.source: "../bilder/" + modelData + ".png"
                icon.width: Theme.iconSizeMedium
                icon.height: Theme.iconSizeMedium
                Rectangle { anchors.fill: parent; z: -1; radius: width / 2; color: Theme.rgba("#000000", 0.45) }
                onClicked: {
                    if (modelData === "plus") karte.zoomen(karte.zoom + 1, karte.width / 2, karte.height / 2)
                    else if (modelData === "minus") karte.zoomen(karte.zoom - 1, karte.width / 2, karte.height / 2)
                    else seite.zumStandort()
                }
            }
        }
    }

    // Angaben zum gewaehlten Punkt
    Rectangle {
        id: feld
        visible: seite.hatP
        z: 11
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Math.min(spalte.height + Theme.paddingLarge * 2, seite.height * 0.55)
        color: Theme.rgba(Theme.overlayBackgroundColor, 0.95)
        MouseArea { anchors.fill: parent }
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: Theme.paddingSmall / 2; color: seite.p ? seite.p.farbe : W.ROSA }
        SilicaFlickable {
            anchors.fill: parent
            anchors.margins: Theme.paddingLarge
            contentHeight: spalte.height
            clip: true
            Column {
                id: spalte
                width: parent.width
                spacing: Theme.paddingSmall
                Row {
                    spacing: Theme.paddingMedium
                    width: parent.width
                    Linie {
                        id: m
                        art: seite.p ? (seite.p.punktart === "station" ? W.artAusTypen(seite.p.arten) : seite.p.art) : "sonst"
                        farbe: seite.p ? seite.p.farbe : "#666666"
                        groesse: Theme.iconSizeMedium
                    }
                    Column {
                        width: parent.width - m.width - Theme.paddingMedium
                        Label { width: parent.width; text: seite.p ? seite.p.name : ""; truncationMode: TruncationMode.Fade }
                        Label {
                            width: parent.width
                            text: seite.p ? W.verbinden([seite.p.bezeichnung, seite.p.adresse], " · ") : ""
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            truncationMode: TruncationMode.Fade
                        }
                    }
                }
                Repeater {
                    model: seite.p ? seite.p.felder.slice(0, 8) : []
                    Label {
                        width: spalte.width
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        text: modelData.label + (modelData.label !== "" && modelData.wert !== "" ? ": " : "") + modelData.wert
                    }
                }
                Row {
                    spacing: Theme.paddingMedium
                    Button {
                        visible: !!seite.p && seite.p.punktart === "station"
                        text: "Abfahrten"
                        preferredWidth: Theme.buttonWidthSmall
                        onClicked: pageStack.push(Qt.resolvedUrl("AbfahrtenSeite.qml"), { station: seite.p.id, name: seite.p.name })
                    }
                    Button {
                        text: "Route hierher"
                        preferredWidth: Theme.buttonWidthSmall
                        onClicked: seite.hinZuStart(seite.p.punktart === "station"
                                    ? { id: seite.p.id, name: seite.p.name, unter: "", typ: "station", lat: seite.p.lat, lon: seite.p.lon, bezeichnung: "" }
                                    : W.kartenOrt(seite.p.lat, seite.p.lon, seite.p.name))
                    }
                }
            }
        }
    }
}
