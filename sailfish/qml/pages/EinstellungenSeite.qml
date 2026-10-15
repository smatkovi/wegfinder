import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../wf.js" as W

// Datensparen, Abfahrten, Speicher, Verlauf.
Page {
    id: seite
    property var e: fenster.einst
    property string speicher: ""

    Component.onCompleted: speicherAnfrage.senden("speicher", {})
    function setzen(werte) { speichern.senden("einstellungen_setzen", werte) }

    Anfrage { id: speichern; onFertig: fenster.einst = daten; onFehler: fenster.meldung(W.fehlerText(text)) }
    Anfrage { id: speicherAnfrage; onFertig: seite.speicher = daten.text }
    Anfrage { id: verlauf; onFertig: fenster.meldung("Verlauf geleert.") }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: inhalt.height + Theme.paddingLarge
        Column {
            id: inhalt
            width: parent.width
            PageHeader { title: "Einstellungen"; description: fenster.wlan ? "Gerade im WLAN" : "Gerade im Mobilfunknetz" }

            ComboBox {
                label: "Rad, Auto, Sharing, Taxi"
                description: "Zuerst kommen immer die Öffis; die übrigen Verkehrsmittel sind vier weitere Anfragen."
                currentIndex: seite.e.weitere_laden === "immer" ? 0 : (seite.e.weitere_laden === "wlan" ? 1 : 2)
                menu: ContextMenu {
                    MenuItem { text: "immer gleich mitladen"; onClicked: seite.setzen({ weitere_laden: "immer" }) }
                    MenuItem { text: "nur im WLAN gleich mitladen"; onClicked: seite.setzen({ weitere_laden: "wlan" }) }
                    MenuItem { text: "nur auf Knopfdruck"; onClicked: seite.setzen({ weitere_laden: "nie" }) }
                }
            }
            ComboBox {
                label: "Kartenhintergrund im Mobilfunknetz"
                description: "Eine Kachel hat 20–50 KB. Geladene Kacheln bleiben 30 Tage auf dem Telefon; im WLAN wird immer voll geladen."
                currentIndex: seite.e.karte_mobil === "voll" ? 0 : (seite.e.karte_mobil === "sparsam" ? 1 : 2)
                menu: ContextMenu {
                    MenuItem { text: "voll"; onClicked: seite.setzen({ karte_mobil: "voll" }) }
                    MenuItem { text: "sparsam (¼ der Daten)"; onClicked: seite.setzen({ karte_mobil: "sparsam" }) }
                    MenuItem { text: "aus (nur Linien und Punkte)"; onClicked: seite.setzen({ karte_mobil: "aus" }) }
                }
            }
            Slider {
                width: parent.width
                label: "Abfahrten je Station"
                minimumValue: 10
                maximumValue: 100
                stepSize: 10
                value: W.zahl(seite.e.abfahrten_max, 60)
                valueText: value
                onReleased: seite.setzen({ abfahrten_max: value })
            }
            SectionHeader { text: "Speicher" }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: "Gespeicherte Kartenkacheln: " + seite.speicher
                color: Theme.highlightColor
            }
            Item { width: 1; height: Theme.paddingMedium }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Kacheln löschen"
                onClicked: Remorse.popupAction(seite, "Kacheln gelöscht", function() { speicherAnfrage.senden("kacheln_leeren", {}) })
            }
            Item { width: 1; height: Theme.paddingMedium }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Verlauf löschen"
                onClicked: verlauf.senden("verlauf_leeren", {})
            }
        }
        VerticalScrollDecorator { }
    }
}
