import QtQuick 1.1
import com.nokia.meego 1.1
import com.nokia.extras 1.0
import "wf.js" as W

// Route planen: Von, Nach, Wann; darunter Favoriten und zuletzt gesuchte
// Verbindungen (beides nur auf dem Telefon).
Page {
    id: seite
    property variant von: W.standortOrt(0, 0)
    property variant nach: null
    property variant wann: ({ zeit: "", datum: "", ankunft: false })
    property variant orte: ({ favoriten: [], verlauf: [], verbindungen: [] })
    property bool wartet: false

    // GPS nur, solange die Seite vorne ist und es gebraucht wird
    property bool brauchtGps: status === PageStatus.Active
                              && (!!(von && von.typ === "standort") || !!(nach && nach.typ === "standort"))
    onBrauchtGpsChanged: brauchtGps ? fenster.standortAn() : fenster.standortAus()

    onStatusChanged: if (status === PageStatus.Active) ladeOrte.senden("orte", {})

    tools: ToolBarLayout {
        ToolIcon { iconSource: "bilder/umgebung.png"; onClicked: pageStack.push(Qt.resolvedUrl("UmgebungSeite.qml")) }
        ToolIcon { iconId: "toolbar-settings"; onClicked: pageStack.push(Qt.resolvedUrl("EinstellungenSeite.qml")) }
        ToolIcon { iconId: "toolbar-view-menu"; onClicked: menue.open() }
    }

    Menu {
        id: menue
        MenuLayout {
            MenuItem { text: "In der Nähe"; onClicked: pageStack.push(Qt.resolvedUrl("UmgebungSeite.qml")) }
            MenuItem { text: "Über wegfinder"; onClicked: pageStack.push(Qt.resolvedUrl("InfoSeite.qml")) }
        }
    }

    Anfrage { id: ladeOrte; onFertig: seite.orte = daten }
    Anfrage { id: merken; onFertig: seite.orte = daten }

    function waehlen(wer) {
        var p = pageStack.push(Qt.resolvedUrl("OrtSeite.qml"),
                               { titel: wer === "von" ? "Start" : "Ziel" })
        p.gewaehlt.connect(function(o) {
            if (wer === "von")
                seite.von = o
            else
                seite.nach = o
        })
    }

    function tauschen() {
        var v = von
        von = nach
        nach = v
    }

    function aufloesen(o) {
        if (o && o.typ === "standort")
            return fenster.standortDa ? W.standortOrt(fenster.standortLat, fenster.standortLon) : null
        return o
    }

    function suchen() {
        if (!von || !nach) {
            fenster.meldung(!von ? "Bitte einen Start wählen." : "Bitte ein Ziel wählen.")
            return
        }
        var v = aufloesen(von), n = aufloesen(nach)
        if (!v || !n) {
            wartet = true
            fenster.meldung("Warte auf den Standort …")
            return
        }
        wartet = false
        merken.senden("verbindung_merken", { von: v, nach: n })
        pageStack.push(Qt.resolvedUrl("ErgebnisSeite.qml"), { von: v, nach: n, wann: seite.wann })
    }

    Connections {
        target: fenster
        onStandortDaChanged: if (seite.wartet && fenster.standortDa) seite.suchen()
    }

    // --- Zeitwahl --------------------------------------------------------
    function zeitSetzen(ankunft) {
        var d = new Date()
        uhr.hour = d.getHours()
        uhr.minute = d.getMinutes()
        uhr.ankunft = ankunft
        uhr.open()
    }

    ContextMenu {
        id: zeitMenue
        MenuLayout {
            MenuItem { text: "Jetzt abfahren"; onClicked: seite.wann = { zeit: "", datum: "", ankunft: false } }
            MenuItem { text: "Abfahrt um …"; onClicked: seite.zeitSetzen(false) }
            MenuItem { text: "Ankunft um …"; onClicked: seite.zeitSetzen(true) }
            MenuItem { text: "Anderer Tag …"; onClicked: tag.open() }
        }
    }
    TimePickerDialog {
        id: uhr
        property bool ankunft: false
        titleText: ankunft ? "Ankunft um" : "Abfahrt um"
        acceptButtonText: "OK"
        rejectButtonText: "Abbrechen"
        hourMode: DateTime.TwentyFourHours
        fields: DateTime.Hours | DateTime.Minutes
        onAccepted: seite.wann = { zeit: W.zweistellig(hour) + ":" + W.zweistellig(minute),
                                   datum: seite.wann.datum || W.datumText(new Date()), ankunft: ankunft }
    }
    DatePickerDialog {
        id: tag
        titleText: "Tag"
        acceptButtonText: "OK"
        rejectButtonText: "Abbrechen"
        Component.onCompleted: { var d = new Date(); year = d.getFullYear(); month = d.getMonth() + 1; day = d.getDate() }
        onAccepted: {
            var datum = year + "-" + W.zweistellig(month) + "-" + W.zweistellig(day)
            var z = seite.wann.zeit !== "" ? seite.wann.zeit : W.uhrText(new Date())
            seite.wann = { zeit: z, datum: datum, ankunft: seite.wann.ankunft }
        }
    }

    // --- Favorit / Verlauf antippen ---------------------------------------
    property variant gedrueckt: null
    ContextMenu {
        id: favMenue
        MenuLayout {
            MenuItem { text: "Als Start"; onClicked: seite.von = seite.gedrueckt }
            MenuItem { text: "Als Ziel"; onClicked: seite.nach = seite.gedrueckt }
            MenuItem {
                text: "Aus Favoriten entfernen"
                onClicked: merken.senden("ort_entfernen", { ort: seite.gedrueckt, favorit: true })
            }
        }
    }

    Kopf {
        id: kopf
        anchors.top: parent.top
        titel: "wegfinder"
        untertitel: seite.wartet ? "Warte auf den Standort …" : "Route planen"
        laedt: seite.wartet
    }

    Flickable {
        anchors { top: kopf.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: inhalt.height + 24
        clip: true

        Column {
            id: inhalt
            width: parent.width

            Item {
                width: parent.width
                height: vonZeile.height + nachZeile.height
                Zeile {
                    id: vonZeile
                    anchors.right: tauschKnopf.left
                    width: parent.width - tauschKnopf.width
                    titel: "Von"
                    wert: seite.von ? W.ortName(seite.von) : "Start wählen"
                    pfeil: false
                    onClicked: seite.waehlen("von")
                }
                Zeile {
                    id: nachZeile
                    anchors.top: vonZeile.bottom
                    width: parent.width - tauschKnopf.width
                    titel: "Nach"
                    wert: seite.nach ? W.ortName(seite.nach) : "Ziel wählen"
                    pfeil: false
                    onClicked: seite.waehlen("nach")
                }
                Item {
                    id: tauschKnopf
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 72
                    height: 120
                    Rectangle { anchors.fill: parent; color: "#26ffffff"; visible: tauschMaus.pressed }
                    Image { anchors.centerIn: parent; source: "bilder/tauschen.png" }
                    MouseArea { id: tauschMaus; anchors.fill: parent; onClicked: seite.tauschen() }
                }
            }
            Zeile {
                titel: "Wann"
                wert: W.zeitAnzeige(seite.wann)
                pfeil: false
                onClicked: zeitMenue.open()
            }
            Item { width: 1; height: 12 }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 32
                text: "Route suchen"
                platformStyle: ButtonStyle { inverted: true }
                onClicked: seite.suchen()
            }
            Item { width: 1; height: 12 }

            Ueberschrift {
                x: 16
                width: parent.width - 32
                text: "Favoriten"
                visible: seite.orte.favoriten.length > 0
            }
            Repeater {
                model: seite.orte.favoriten
                Zeile {
                    titel: W.ortZusatz(modelData)
                    wert: W.ortName(modelData)
                    onClicked: {
                        seite.nach = modelData
                        if (seite.von)
                            seite.suchen()
                    }
                    onGehalten: { seite.gedrueckt = modelData; favMenue.open() }
                }
            }

            Ueberschrift {
                x: 16
                width: parent.width - 32
                text: "Zuletzt gesucht"
                visible: seite.orte.verbindungen.length > 0
            }
            Repeater {
                model: seite.orte.verbindungen
                Zeile {
                    titel: W.ortName(modelData.von) + " →"
                    wert: W.ortName(modelData.nach)
                    onClicked: {
                        seite.von = modelData.von
                        seite.nach = modelData.nach
                        seite.suchen()
                    }
                }
            }

            Text {
                x: 16
                width: parent.width - 32
                visible: seite.orte.favoriten.length === 0 && seite.orte.verbindungen.length === 0
                wrapMode: Text.WordWrap
                color: "#8c8c8c"
                font.pixelSize: 20
                text: "Tipp: In der Ortssuche einen Eintrag lange drücken, um ihn als Favorit zu merken. "
                      + "Favoriten erscheinen dann hier – antippen genügt, um hinzufinden."
            }
        }
    }
}
