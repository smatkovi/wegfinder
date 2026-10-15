import QtQuick 1.1
import com.nokia.meego 1.1
import "wf.js" as W

// Abfahrten einer Station, mit Echtzeit, Gleis/Steig und Ausfaellen.
// Antippen zeigt den Verlauf der Fahrt. Die Tafel kommt gross vom Server
// (bis 230 KB, gezippt 20 KB) -- der Dienst haelt sie 30 s vor, und die
// Seite fragt nur auf Wunsch neu.
Page {
    id: seite
    property string station: ""
    property string name: ""
    property variant daten: null
    property string fehler: ""

    tools: ToolBarLayout {
        ToolIcon { iconId: "toolbar-back"; onClicked: pageStack.pop() }
        ToolIcon { iconId: "toolbar-refresh"; onClicked: seite.laden(true) }
        ToolIcon {
            iconSource: "bilder/standort.png"
            onClicked: {
                // Route hierher: Startseite mit diesem Ziel
                var start = pageStack.find(function(p) { return p.suchen !== undefined && p.nach !== undefined })
                if (start) {
                    start.nach = { id: seite.station, name: seite.name, unter: "", typ: "station", lat: 0, lon: 0, bezeichnung: "" }
                    pageStack.pop(start)
                }
            }
        }
    }

    Component.onCompleted: laden(false)

    function laden(neu) {
        fehler = ""
        anfrage.senden("abfahrten", { station: station, neu: neu })
    }

    Anfrage {
        id: anfrage
        onFertig: { seite.daten = daten; if (daten.abfahrten.length === 0) seite.fehler = "Keine Abfahrten in nächster Zeit." }
        onFehler: seite.fehler = W.fehlerText(text)
    }

    Kopf {
        id: kopf
        anchors.top: parent.top
        titel: seite.name
        untertitel: seite.daten ? "Abfahrten · Stand " + seite.daten.stand : "Abfahrten"
        laedt: anfrage.laeuft
    }

    ListView {
        id: liste
        anchors { top: kopf.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        model: seite.daten ? seite.daten.abfahrten : []
        delegate: Item {
            width: liste.width
            height: 80
            Rectangle { anchors.fill: parent; color: "#26ffffff"; visible: maus.pressed }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16 }
                height: 1
                color: "#333333"
            }
            Column {
                id: zeit
                x: 12
                width: 76
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    text: modelData.zeit
                    color: modelData.ausgefallen ? "#ff6666" : "white"
                    font.strikeout: modelData.ausgefallen
                    font.pixelSize: 26
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    visible: text !== ""
                    text: modelData.ausgefallen ? "fällt aus" : (modelData.echtzeit ? (modelData.verspaetung !== 0 ? modelData.live : "pünktlich") : "")
                    color: modelData.ausgefallen || modelData.verspaetung > 0 ? "#ff6666" : "#7ed67e"
                    font.pixelSize: 18
                }
            }
            Linie {
                id: marke
                anchors { left: zeit.right; leftMargin: 14; verticalCenter: parent.verticalCenter }
                art: modelData.art
                text: modelData.linie
                farbe: modelData.farbe
                groesse: 32
            }
            Column {
                anchors { left: marke.right; leftMargin: 12; right: gleis.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                Text {
                    width: parent.width
                    text: modelData.richtung
                    color: "white"
                    font.pixelSize: 24
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: modelData.meldungen.length > 0 ? modelData.meldungen[0].text : W.inMinuten(modelData.wann)
                    color: modelData.meldungen.length > 0 ? "#ffb347" : "#8c8c8c"
                    font.pixelSize: 18
                    elide: Text.ElideRight
                }
            }
            Text {
                id: gleis
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                text: modelData.gleis
                color: modelData.gleiswechsel ? "#ffb347" : "#b3b3b3"
                font.pixelSize: 22
            }
            MouseArea {
                id: maus
                anchors.fill: parent
                onClicked: if (modelData.fahrt !== "")
                    pageStack.push(Qt.resolvedUrl("FahrtSeite.qml"),
                                   { url: modelData.fahrt, titel: modelData.linie + " → " + modelData.richtung,
                                     farbe: modelData.farbe, station: seite.name })
            }
        }
        footer: Text {
            width: liste.width
            height: 80
            visible: seite.fehler !== "" || (!!seite.daten && seite.daten.gesamt > seite.daten.abfahrten.length)
            text: seite.fehler !== "" ? seite.fehler
                  : (seite.daten ? "Weitere " + (seite.daten.gesamt - seite.daten.abfahrten.length) + " Abfahrten ausgeblendet (Einstellungen)." : "")
            color: "#8c8c8c"
            font.pixelSize: 20
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
    ScrollDecorator { flickableItem: liste }
}
