import QtQuick 1.1
import com.nokia.meego 1.1
import "wf.js" as W

// Verlauf einer Fahrt: alle Halte mit Zeit, Echtzeit und Gleis; vorbei
// gefahrene grau, der aktuelle hervorgehoben.
Page {
    id: seite
    property string url: ""
    property string titel: ""
    property string farbe: "#666666"
    property string station: ""
    property variant daten: null
    property string fehler: ""

    tools: ToolBarLayout {
        ToolIcon { iconId: "toolbar-back"; onClicked: pageStack.pop() }
        ToolIcon { iconId: "toolbar-refresh"; onClicked: seite.laden() }
        ToolIcon {
            iconSource: "bilder/karte.png"
            enabled: !!seite.daten
            onClicked: pageStack.push(Qt.resolvedUrl("KarteSeite.qml"),
                                      { fahrt: { titel: seite.titel, farbe: seite.farbe,
                                                 halte: seite.daten.halte, linie: seite.daten.linie } })
        }
    }

    Component.onCompleted: laden()
    function laden() {
        fehler = ""
        anfrage.senden("fahrt", { url: url })
    }

    Anfrage {
        id: anfrage
        onFertig: {
            seite.daten = daten
            // zum eigenen Halt rollen
            for (var i = 0; i < daten.halte.length; ++i)
                if (daten.halte[i].name === seite.station) {
                    liste.positionViewAtIndex(Math.max(0, i - 2), ListView.Beginning)
                    break
                }
        }
        onFehler: seite.fehler = W.fehlerText(text)
    }

    Kopf {
        id: kopf
        anchors.top: parent.top
        titel: seite.titel
        untertitel: seite.fehler
        laedt: anfrage.laeuft
    }

    ListView {
        id: liste
        anchors { top: kopf.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        model: seite.daten ? seite.daten.halte : []
        delegate: Item {
            width: liste.width
            height: 64
            opacity: modelData.vorbei ? 0.5 : 1
            Rectangle {
                anchors.fill: parent
                color: "#33ff4083"
                visible: seite.daten && index === seite.daten.aktuell
            }
            Rectangle {
                x: 111 - 4
                width: 8
                anchors { top: parent.top; bottom: parent.bottom }
                anchors.topMargin: index === 0 ? parent.height / 2 : 0
                anchors.bottomMargin: seite.daten && index === seite.daten.halte.length - 1 ? parent.height / 2 : 0
                color: seite.farbe
            }
            Halt {
                anchors.verticalCenter: parent.verticalCenter
                h: modelData
                farbe: seite.farbe
                fett: modelData.name === seite.station
                onClicked: if (modelData.id !== "")
                    pageStack.push(Qt.resolvedUrl("AbfahrtenSeite.qml"), { station: modelData.id, name: modelData.name })
            }
        }
    }
    ScrollDecorator { flickableItem: liste }
}
