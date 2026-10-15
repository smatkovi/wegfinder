import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../wf.js" as W

// Meine Tickets: gueltige zuerst. Ohne Netz die zuletzt geladene Liste.
Page {
    id: seite
    property var daten: null
    property string fehler: ""
    property int takt: 0          // Gueltigkeit jede Minute neu rechnen

    Component.onCompleted: laden()
    function laden() {
        fehler = ""
        anfrage.senden("tickets", {})
    }
    Anfrage {
        id: anfrage
        onFertig: seite.daten = daten
        onFehler: seite.fehler = W.fehlerText(text)
    }
    Timer { interval: 60000; repeat: true; running: Qt.application.active; onTriggered: seite.takt++ }

    SilicaListView {
        id: liste
        anchors.fill: parent
        PullDownMenu {
            busy: anfrage.laeuft
            MenuItem { text: "Konto"; onClicked: pageStack.push(Qt.resolvedUrl("KontoSeite.qml")) }
            MenuItem { text: "Neu laden"; onClicked: seite.laden() }
        }
        header: PageHeader {
            title: "Meine Tickets"
            description: seite.daten && seite.daten.offline ? "Ohne Netz – Stand der letzten Abfrage" : ""
        }
        model: seite.daten ? seite.daten.tickets : []
        delegate: BackgroundItem {
            id: eintrag
            height: spalte.height + 2 * Theme.paddingMedium
            readonly property var g: { seite.takt; return W.gueltigkeit(modelData.von, modelData.bis) }
            onClicked: pageStack.push(Qt.resolvedUrl("TicketSeite.qml"), { ticket: modelData })
            Column {
                id: spalte
                x: Theme.horizontalPageMargin
                y: Theme.paddingMedium
                width: parent.width - 2 * Theme.horizontalPageMargin
                Label {
                    width: parent.width
                    text: modelData.name !== "" ? modelData.name : "Ticket"
                    wrapMode: Text.Wrap
                    color: eintrag.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: W.verbinden([eintrag.g.text, modelData.zustand, modelData.preis], " · ")
                    font.pixelSize: Theme.fontSizeSmall
                    color: W.gueltigFarbe(eintrag.g.farbe)
                    wrapMode: Text.Wrap
                }
                Repeater {
                    model: modelData.felder.slice(0, 3)
                    Label {
                        width: spalte.width
                        text: modelData
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
        ViewPlaceholder {
            enabled: !anfrage.laeuft && (seite.fehler !== "" || (!!seite.daten && seite.daten.tickets.length === 0))
            text: seite.fehler !== "" ? "Tickets nicht geladen" : "Keine Tickets"
            hintText: seite.fehler !== "" ? seite.fehler : "Gekaufte Tickets erscheinen hier und bleiben auch ohne Netz verfügbar."
        }
        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: anfrage.laeuft && !seite.daten
        }
        VerticalScrollDecorator { }
    }
}
