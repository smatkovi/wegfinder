import QtQuick 1.1
import com.nokia.meego 1.1
import "wf.js" as W

// In der Naehe: Haltestellen, Leihraeder, E-Scooter, Carsharing, Taxi,
// Parken -- was der Server fuer den Kartenausschnitt meldet. Antippen zeigt
// die Angaben (Ladestand, Preis, freie Raeder ...); Haltestellen fuehren zu
// den Abfahrten. Gebucht wird nichts.
//
// Im WLAN laedt die Seite nach jedem Verschieben neu, im Mobilfunknetz nur
// auf Knopfdruck ("Hier suchen") -- eine Antwort hat leicht 20 KB.
Page {
    id: seite
    property variant filterListe: []
    property string filter: fenster.einst.umgebung_filter !== undefined ? fenster.einst.umgebung_filter : "public"
    property string filterName: filter === "" ? "Alles" : "Öffis"
    property int gesamt: 0
    property variant punkte: []
    property variant gruppen: []
    property int gewaehlt: -1
    property bool hatP: gewaehlt >= 0 && gewaehlt < punkte.length
    property variant p: hatP ? punkte[gewaehlt] : null
    property bool veraltet: false
    property bool erstesMal: true
    property string modus: fenster.kartenModus()

    tools: ToolBarLayout {
        ToolIcon { iconId: "toolbar-back"; onClicked: pageStack.pop() }
        ToolIcon { iconSource: "bilder/minus.png"; onClicked: karte.zoomen(karte.zoom - 1, karte.width / 2, karte.height / 2) }
        ToolIcon { iconSource: "bilder/plus.png"; onClicked: karte.zoomen(karte.zoom + 1, karte.width / 2, karte.height / 2) }
        ToolIcon { iconSource: "bilder/standort.png"; onClicked: seite.zumStandort() }
        ToolIcon { iconSource: "bilder/filter.png"; onClicked: filterWahl.open() }
        ToolIcon { iconId: "toolbar-refresh"; onClicked: seite.laden() }
    }

    onStatusChanged: {
        if (status === PageStatus.Active)
            fenster.standortAn()
        else if (status === PageStatus.Deactivating)
            fenster.standortAus()
    }

    Component.onCompleted: {
        filterAnfrage.senden("filter", {})
        if (fenster.standortDa)
            karte.zentrieren(fenster.standortLat, fenster.standortLon, 16)
        else
            karte.zentrieren(W.WIEN.lat, W.WIEN.lon, 15)
        startZeit.start()
    }
    // Erst laden, wenn die Karte ihre Groesse hat.
    Timer { id: startZeit; interval: 100; onTriggered: seite.laden() }

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
                                     breite: Math.round(karte.width), hoehe: Math.round(karte.height) })
    }

    Anfrage {
        id: anfrage
        onFertig: {
            seite.punkte = daten.punkte
            seite.gruppen = daten.gruppen
            seite.gesamt = daten.gesamt
            if (daten.punkte.length === 0)
                fenster.meldung("Hier nichts gefunden – Ausschnitt verschieben oder Filter ändern.")
        }
        onFehler: fenster.meldung(W.fehlerText(text))
    }
    Anfrage {
        id: filterAnfrage
        onFertig: {
            var l = [{ id: "", titel: "Alles", kurz: "Alles" }]
            for (var i = 0; i < daten.length; ++i)
                l.push(daten[i])
            seite.filterListe = l
            for (i = 0; i < l.length; ++i)
                if (l[i].id === seite.filter) seite.filterName = l[i].titel
            var namen = []
            for (i = 0; i < l.length; ++i)
                namen.push({ name: l[i].titel })
            filterModell.clear()
            for (i = 0; i < namen.length; ++i)
                filterModell.append(namen[i])
        }
    }

    Anfrage { id: merken; onFertig: fenster.einst = daten }
    ListModel { id: filterModell }
    SelectionDialog {
        id: filterWahl
        titleText: "Zeigen"
        model: filterModell
        onAccepted: {
            var f = seite.filterListe[selectedIndex]
            seite.filter = f.id
            seite.filterName = f.titel
            merken.senden("einstellungen_setzen", { umgebung_filter: f.id })
            seite.laden()
        }
    }

    Kopf {
        id: kopf
        anchors.top: parent.top
        titel: "In der Nähe"
        untertitel: seite.filterName + (seite.punkte.length > 0
                    ? " · " + (seite.gesamt > seite.punkte.length ? "die nächsten " + seite.punkte.length + " von " + seite.gesamt : seite.punkte.length + " Treffer")
                    : "")
        laedt: anfrage.laeuft
        onClicked: filterWahl.open()
    }

    Karte {
        id: karte
        anchors { top: kopf.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
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
            if (fenster.wlan)
                nachladen.restart()
            else
                seite.veraltet = true
        }
        onGehalten: {
            var o = W.kartenOrt(lat, lon)
            var start = pageStack.find(function(pg) { return pg.suchen !== undefined && pg.nach !== undefined })
            if (start) {
                start.nach = o
                pageStack.pop(start)
                fenster.meldung("Ziel: Punkt auf der Karte")
            }
        }
    }
    Timer { id: nachladen; interval: 900; onTriggered: seite.laden() }

    Button {
        anchors { top: kopf.bottom; topMargin: 12; horizontalCenter: parent.horizontalCenter }
        visible: seite.veraltet && !anfrage.laeuft
        text: "Hier suchen"
        width: 220
        onClicked: seite.laden()
    }

    // Angaben zum gewaehlten Punkt
    Rectangle {
        id: feld
        visible: seite.hatP
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Math.min(spalte.height + 24, seite.height * 0.55)
        color: "#f2161616"
        MouseArea { anchors.fill: parent }  // nicht zur Karte durchreichen
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 3; color: seite.p ? seite.p.farbe : W.ROSA }
        Flickable {
            anchors.fill: parent
            anchors.margins: 12
            contentHeight: spalte.height
            clip: true
            Column {
                id: spalte
                width: parent.width
                spacing: 6
                Row {
                    spacing: 12
                    width: parent.width
                    Linie {
                        id: m
                        art: seite.p ? (seite.p.punktart === "station" ? W.artAusTypen(seite.p.arten) : seite.p.art) : "sonst"
                        farbe: seite.p ? seite.p.farbe : "#666666"
                        groesse: 40
                    }
                    Column {
                        width: parent.width - m.width - 12
                        Text {
                            width: parent.width
                            text: seite.p ? seite.p.name : ""
                            color: "white"
                            font.pixelSize: 26
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: seite.p ? W.verbinden([seite.p.bezeichnung, seite.p.adresse], " · ") : ""
                            color: "#8c8c8c"
                            font.pixelSize: 20
                            elide: Text.ElideRight
                        }
                    }
                }
                Repeater {
                    model: seite.p ? seite.p.felder.slice(0, 8) : []
                    Text {
                        width: spalte.width
                        wrapMode: Text.WordWrap
                        color: "#d9d9d9"
                        font.pixelSize: 20
                        text: modelData.label + (modelData.label !== "" && modelData.wert !== "" ? ": " : "") + modelData.wert
                    }
                }
                Row {
                    spacing: 12
                    Button {
                        width: (spalte.width - 12) / 2
                        visible: !!seite.p && seite.p.punktart === "station"
                        text: "Abfahrten"
                        onClicked: pageStack.push(Qt.resolvedUrl("AbfahrtenSeite.qml"), { station: seite.p.id, name: seite.p.name })
                    }
                    Button {
                        width: (spalte.width - 12) / 2
                        text: "Route hierher"
                        onClicked: {
                            var o = seite.p.punktart === "station"
                                    ? { id: seite.p.id, name: seite.p.name, unter: "", typ: "station", lat: seite.p.lat, lon: seite.p.lon, bezeichnung: "" }
                                    : W.kartenOrt(seite.p.lat, seite.p.lon, seite.p.name)
                            var start = pageStack.find(function(pg) { return pg.suchen !== undefined && pg.nach !== undefined })
                            if (start) {
                                start.nach = o
                                pageStack.pop(start)
                            }
                        }
                    }
                }
            }
        }
    }
}
