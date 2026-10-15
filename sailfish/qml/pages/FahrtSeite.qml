import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../wf.js" as W

// Verlauf einer Fahrt: alle Halte; vorbei gefahrene blass, der aktuelle
// hervorgehoben.
Page {
    id: seite
    property string url: ""
    property string titel: ""
    property string farbe: "#666666"
    property string station: ""
    property var daten: null
    property string fehler: ""

    Component.onCompleted: laden()
    function laden() {
        fehler = ""
        anfrage.senden("fahrt", { url: url })
    }
    Anfrage {
        id: anfrage
        onFertig: {
            seite.daten = daten
            for (var i = 0; i < daten.halte.length; ++i)
                if (daten.halte[i].name === seite.station) {
                    liste.positionViewAtIndex(Math.max(0, i - 2), ListView.Beginning)
                    break
                }
        }
        onFehler: seite.fehler = W.fehlerText(text)
    }

    SilicaListView {
        id: liste
        anchors.fill: parent
        PullDownMenu {
            busy: anfrage.laeuft
            MenuItem {
                text: "Karte"
                enabled: !!seite.daten
                onClicked: pageStack.push(Qt.resolvedUrl("KarteSeite.qml"),
                                          { fahrt: { titel: seite.titel, farbe: seite.farbe,
                                                     halte: seite.daten.halte, linie: seite.daten.linie } })
            }
            MenuItem { text: "Neu laden"; onClicked: seite.laden() }
        }
        header: PageHeader { title: seite.titel; description: seite.fehler }
        model: seite.daten ? seite.daten.halte : []
        delegate: Item {
            width: liste.width
            height: halt.height
            opacity: modelData.vorbei ? 0.5 : 1
            Rectangle {
                anchors.fill: parent
                color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                visible: !!seite.daten && index === seite.daten.aktuell
            }
            Rectangle {
                x: halt.linieX - width / 2
                width: Theme.paddingSmall * 1.5
                anchors { top: parent.top; bottom: parent.bottom }
                anchors.topMargin: index === 0 ? parent.height / 2 : 0
                anchors.bottomMargin: !!seite.daten && index === seite.daten.halte.length - 1 ? parent.height / 2 : 0
                color: seite.farbe
            }
            Halt {
                id: halt
                h: modelData
                farbe: seite.farbe
                fett: modelData.name === seite.station
                onClicked: pageStack.push(Qt.resolvedUrl("AbfahrtenSeite.qml"), { station: modelData.id, name: modelData.name })
            }
        }
        VerticalScrollDecorator { }
    }
}
