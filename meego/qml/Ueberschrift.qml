import QtQuick 1.1

// Abschnittsueberschrift wie in den Einstellungen der Standard-Apps:
// kleiner grauer Text rechts, eine Linie links davon.
Item {
    property alias text: t.text
    width: parent ? parent.width : 480
    height: 48
    Rectangle {
        anchors { left: parent.left; right: t.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        height: 1
        color: "#4d4d4d"
    }
    Text {
        id: t
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        color: "#8c8c8c"
        font.pixelSize: 20
        font.bold: true
    }
}
