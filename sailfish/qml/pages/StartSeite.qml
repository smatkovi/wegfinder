import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../wf.js" as W

// Route planen: Von, Nach, Wann; darunter Favoriten und zuletzt gesuchte
// Verbindungen (nur auf dem Telefon).
Page {
    id: seite
    property var von: W.standortOrt(0, 0)
    property var nach: null
    property var wann: ({ zeit: "", datum: "", ankunft: false })
    property var orte: ({ favoriten: [], verlauf: [], verbindungen: [] })
    property bool wartet: false

    property bool brauchtGps: status === PageStatus.Active
                              && ((!!von && von.typ === "standort") || (!!nach && nach.typ === "standort"))
    onBrauchtGpsChanged: brauchtGps ? fenster.standortAn() : fenster.standortAus()
    onStatusChanged: if (status === PageStatus.Active) ladeOrte.senden("orte", {})

    Anfrage { id: ladeOrte; onFertig: seite.orte = daten }
    Anfrage { id: merken; onFertig: seite.orte = daten }

    function waehlen(wer) {
        var p = pageStack.push(Qt.resolvedUrl("OrtSeite.qml"), { titel: wer === "von" ? "Start" : "Ziel" })
        p.gewaehlt.connect(function(o) {
            if (wer === "von") seite.von = o
            else seite.nach = o
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

    function zeitWaehlen(ankunft) {
        var d = new Date()
        var dlg = pageStack.push("Sailfish.Silica.TimePickerDialog",
                                 { hour: d.getHours(), minute: d.getMinutes(), hourMode: DateTime.TwentyFourHours })
        dlg.accepted.connect(function() {
            seite.wann = { zeit: W.zweistellig(dlg.hour) + ":" + W.zweistellig(dlg.minute),
                           datum: seite.wann.datum || W.datumText(new Date()), ankunft: ankunft }
        })
    }
    function tagWaehlen() {
        var dlg = pageStack.push("Sailfish.Silica.DatePickerDialog", { date: new Date() })
        dlg.accepted.connect(function() {
            var z = seite.wann.zeit !== "" ? seite.wann.zeit : W.uhrText(new Date())
            seite.wann = { zeit: z, datum: W.datumText(dlg.date), ankunft: seite.wann.ankunft }
        })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: inhalt.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem { text: "Über wegfinder"; onClicked: pageStack.push(Qt.resolvedUrl("InfoSeite.qml")) }
            MenuItem { text: "Einstellungen"; onClicked: pageStack.push(Qt.resolvedUrl("EinstellungenSeite.qml")) }
            MenuItem { text: "Konto"; onClicked: pageStack.push(Qt.resolvedUrl("KontoSeite.qml")) }
            MenuItem { text: "Meine Tickets"; onClicked: pageStack.push(Qt.resolvedUrl("TicketsSeite.qml")) }
            MenuItem { text: "In der Nähe"; onClicked: pageStack.push(Qt.resolvedUrl("UmgebungSeite.qml")) }
            MenuItem { text: "Route suchen"; onClicked: seite.suchen() }
        }

        Column {
            id: inhalt
            width: parent.width

            PageHeader {
                title: "wegfinder"
                description: seite.wartet ? "Warte auf den Standort …" : "Route planen"
            }

            Item {
                width: parent.width
                height: vonKnopf.height + nachKnopf.height
                ValueButton {
                    id: vonKnopf
                    width: parent.width - tausch.width
                    label: "Von"
                    value: seite.von ? W.ortName(seite.von) : "Start wählen"
                    onClicked: seite.waehlen("von")
                }
                ValueButton {
                    id: nachKnopf
                    anchors.top: vonKnopf.bottom
                    width: parent.width - tausch.width
                    label: "Nach"
                    value: seite.nach ? W.ortName(seite.nach) : "Ziel wählen"
                    onClicked: seite.waehlen("nach")
                }
                IconButton {
                    id: tausch
                    anchors { right: parent.right; rightMargin: Theme.paddingMedium; verticalCenter: parent.verticalCenter }
                    icon.source: "../bilder/tauschen.png"
                    icon.width: Theme.iconSizeMedium
                    icon.height: Theme.iconSizeMedium
                    onClicked: seite.tauschen()
                }
            }
            ValueButton {
                id: wannKnopf
                label: "Wann"
                value: W.zeitAnzeige(seite.wann)
                onClicked: zeitMenue.open(wannKnopf)
                ContextMenu {
                    id: zeitMenue
                    MenuItem { text: "Jetzt abfahren"; onClicked: seite.wann = { zeit: "", datum: "", ankunft: false } }
                    MenuItem { text: "Abfahrt um …"; onClicked: seite.zeitWaehlen(false) }
                    MenuItem { text: "Ankunft um …"; onClicked: seite.zeitWaehlen(true) }
                    MenuItem { text: "Anderer Tag …"; onClicked: seite.tagWaehlen() }
                }
            }
            Item { width: 1; height: Theme.paddingLarge }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Route suchen"
                preferredWidth: Theme.buttonWidthLarge
                onClicked: seite.suchen()
            }
            Item { width: 1; height: Theme.paddingLarge }

            SectionHeader { text: "Favoriten"; visible: seite.orte.favoriten.length > 0 }
            Repeater {
                model: seite.orte.favoriten
                ListItem {
                    id: fav
                    contentHeight: Theme.itemSizeMedium
                    menu: ContextMenu {
                        MenuItem { text: "Als Start"; onClicked: seite.von = modelData }
                        MenuItem { text: "Als Ziel"; onClicked: seite.nach = modelData }
                        MenuItem { text: "Aus Favoriten entfernen"; onClicked: merken.senden("ort_entfernen", { ort: modelData, favorit: true }) }
                    }
                    onClicked: {
                        seite.nach = modelData
                        if (seite.von) seite.suchen()
                    }
                    Column {
                        anchors { left: parent.left; right: parent.right; margins: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                        Label { width: parent.width; text: W.ortName(modelData); truncationMode: TruncationMode.Fade; color: fav.highlighted ? Theme.highlightColor : Theme.primaryColor }
                        Label { width: parent.width; text: W.ortZusatz(modelData); font.pixelSize: Theme.fontSizeExtraSmall; color: Theme.secondaryColor; truncationMode: TruncationMode.Fade }
                    }
                }
            }
            SectionHeader { text: "Zuletzt gesucht"; visible: seite.orte.verbindungen.length > 0 }
            Repeater {
                model: seite.orte.verbindungen
                BackgroundItem {
                    id: verb
                    height: Theme.itemSizeMedium
                    onClicked: {
                        seite.von = modelData.von
                        seite.nach = modelData.nach
                        seite.suchen()
                    }
                    Column {
                        anchors { left: parent.left; right: parent.right; margins: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                        Label { width: parent.width; text: W.ortName(modelData.von) + " →"; font.pixelSize: Theme.fontSizeSmall; color: Theme.secondaryColor; truncationMode: TruncationMode.Fade }
                        Label { width: parent.width; text: W.ortName(modelData.nach); truncationMode: TruncationMode.Fade; color: verb.highlighted ? Theme.highlightColor : Theme.primaryColor }
                    }
                }
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: seite.orte.favoriten.length === 0 && seite.orte.verbindungen.length === 0
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                text: "Tipp: In der Ortssuche einen Eintrag lange drücken, um ihn als Favorit zu merken. "
                      + "Favoriten erscheinen dann hier – antippen genügt, um hinzufinden."
            }
        }
        VerticalScrollDecorator { }
    }
}
