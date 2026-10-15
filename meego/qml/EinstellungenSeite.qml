import QtQuick 1.1
import com.nokia.meego 1.1
import "wf.js" as W

// Datensparen (fuers 2G-Netz), Abfahrten, Speicher, Verlauf.
Page {
    id: seite
    property variant e: fenster.einst
    property string speicher: ""

    tools: ToolBarLayout {
        ToolIcon { iconId: "toolbar-back"; onClicked: pageStack.pop() }
    }

    Component.onCompleted: speicherAnfrage.senden("speicher", {})

    function setzen(werte) {
        speichern.senden("einstellungen_setzen", werte)
    }

    Anfrage { id: speichern; onFertig: fenster.einst = daten; onFehler: fenster.meldung(W.fehlerText(text)) }
    Anfrage { id: speicherAnfrage; onFertig: seite.speicher = daten.text }
    Anfrage { id: verlauf; onFertig: fenster.meldung("Verlauf geleert.") }

    QueryDialog {
        id: leerenFrage
        titleText: "Kartenkacheln löschen?"
        message: "Die gespeicherten Kacheln (" + seite.speicher + ") werden bei Bedarf neu geladen – im Mobilfunknetz kostet das Daten."
        acceptButtonText: "Löschen"
        rejectButtonText: "Abbrechen"
        onAccepted: speicherAnfrage.senden("kacheln_leeren", {})
    }

    Kopf {
        id: kopf
        anchors.top: parent.top
        titel: "Einstellungen"
        untertitel: fenster.wlan ? "Gerade im WLAN" : "Gerade im Mobilfunknetz"
        laedt: speichern.laeuft
    }

    Flickable {
        anchors { top: kopf.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: inhalt.height + 32
        clip: true
        Column {
            id: inhalt
            x: 16
            width: parent.width - 32
            spacing: 12
            Item { width: 1; height: 4 }

            Ueberschrift { text: "Rad, Auto, Sharing, Taxi" }
            ButtonColumn {
                width: parent.width
                Button {
                    text: "Immer gleich mitladen"
                    checked: seite.e.weitere_laden === "immer"
                    onClicked: seite.setzen({ weitere_laden: "immer" })
                }
                Button {
                    text: "Nur im WLAN gleich mitladen"
                    checked: seite.e.weitere_laden === "wlan"
                    onClicked: seite.setzen({ weitere_laden: "wlan" })
                }
                Button {
                    text: "Nur auf Knopfdruck"
                    checked: seite.e.weitere_laden === "nie"
                    onClicked: seite.setzen({ weitere_laden: "nie" })
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#8c8c8c"
                font.pixelSize: 20
                text: "Zuerst kommen immer die Öffis. Die übrigen Verkehrsmittel sind vier weitere Anfragen (zusammen etwa 10 KB)."
            }

            Ueberschrift { text: "Kartenhintergrund im Mobilfunknetz" }
            ButtonColumn {
                width: parent.width
                Button {
                    text: "Voll"
                    checked: seite.e.karte_mobil === "voll"
                    onClicked: seite.setzen({ karte_mobil: "voll" })
                }
                Button {
                    text: "Sparsam (¼ der Daten, unschärfer)"
                    checked: seite.e.karte_mobil === "sparsam"
                    onClicked: seite.setzen({ karte_mobil: "sparsam" })
                }
                Button {
                    text: "Aus (nur Linien und Punkte)"
                    checked: seite.e.karte_mobil === "aus"
                    onClicked: seite.setzen({ karte_mobil: "aus" })
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#8c8c8c"
                font.pixelSize: 20
                text: "Eine Kachel hat 20–50 KB, ein Bildschirm braucht etwa zehn. Geladene Kacheln bleiben 30 Tage "
                      + "auf dem Telefon. Im WLAN wird immer voll geladen. Auf der Karte lässt es sich im Menü umschalten."
            }
            Row {
                width: parent.width
                spacing: 12
                Text {
                    width: parent.width - leeren.width - 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Gespeicherte Kacheln: " + seite.speicher
                    color: "white"
                    font.pixelSize: 22
                }
                Button {
                    id: leeren
                    width: 150
                    text: "Löschen"
                    onClicked: leerenFrage.open()
                }
            }

            Ueberschrift { text: "Abfahrten" }
            Text { text: "Höchstens " + anzahl.value + " Abfahrten zeigen"; color: "white"; font.pixelSize: 24 }
            Slider {
                id: anzahl
                width: parent.width
                minimumValue: 10
                maximumValue: 100
                stepSize: 10
                value: W.zahl(seite.e.abfahrten_max, 30)
                valueIndicatorVisible: true
                onPressedChanged: if (!pressed) seite.setzen({ abfahrten_max: value })
            }

            Ueberschrift { text: "Verlauf" }
            Button {
                width: parent.width
                text: "Zuletzt gesuchte Orte löschen"
                onClicked: verlauf.senden("verlauf_leeren", {})
            }
        }
    }
}
