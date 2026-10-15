import QtQuick 1.1
import "wf.js" as W

// Ein Halt im Verlauf einer Route: links Zeit (und Echtzeit), ein Punkt auf
// der Linie, rechts Name und Gleis/Steig.
Item {
    id: halt
    property variant h: null
    property string farbe: "#8c8c8c"
    property bool fett: false
    signal clicked

    width: parent ? parent.width : 480
    height: Math.max(56, name.height + 16)

    Rectangle { anchors.fill: parent; color: "#26ffffff"; visible: maus.pressed && halt.h && halt.h.id !== "" }

    Column {
        x: 12
        width: 86
        anchors.verticalCenter: parent.verticalCenter
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: halt.h ? halt.h.zeit : ""
            color: halt.h && halt.h.ausgefallen ? "#ff6666" : "white"
            font.pixelSize: 26
            font.strikeout: halt.h ? halt.h.ausgefallen : false
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            visible: text !== ""
            text: halt.h && halt.h.echtzeit ? (halt.h.verspaetung !== 0 ? halt.h.live : "pünktlich") : ""
            color: halt.h && halt.h.verspaetung > 0 ? "#ff6666" : "#7ed67e"
            font.pixelSize: 18
        }
    }
    Rectangle {
        x: 111 - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 20
        height: 20
        radius: 10
        color: "white"
        border.width: 4
        border.color: halt.farbe
        smooth: true
    }
    Text {
        id: name
        anchors { left: parent.left; leftMargin: 130; right: gleis.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        text: halt.h ? halt.h.name : ""
        color: "white"
        font.pixelSize: halt.fett ? 26 : 24
        font.bold: halt.fett
        wrapMode: Text.WordWrap
        maximumLineCount: 2
    }
    Text {
        id: gleis
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        visible: text !== ""
        text: halt.h && halt.h.gleis !== "" ? "Gl. " + halt.h.gleis : ""
        color: halt.h && halt.h.gleiswechsel ? "#ffb347" : "#b3b3b3"
        font.pixelSize: 20
    }
    MouseArea {
        id: maus
        anchors.fill: parent
        onClicked: halt.clicked()
    }
}
