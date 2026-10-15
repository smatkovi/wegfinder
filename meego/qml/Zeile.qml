import QtQuick 1.1
import com.nokia.meego 1.1

// Eine antippbare Zeile wie in den Einstellungen der Standard-Apps: oben
// klein und grau, was es ist, darunter gross der Wert, rechts der Pfeil.
// Langes Druecken meldet gehalten() (Kontextmenue).
Item {
    id: zeile
    property alias titel: titelText.text
    property alias wert: wertText.text
    property bool pfeil: true
    property bool aktiv: true
    signal clicked
    signal gehalten

    width: parent ? parent.width : 480
    height: 84

    Rectangle {
        anchors.fill: parent
        color: "#26ffffff"
        visible: maus.pressed
    }
    Column {
        anchors { left: parent.left; leftMargin: 16; right: pfeilBild.left; rightMargin: 8
                  verticalCenter: parent.verticalCenter }
        Text {
            id: titelText
            width: parent.width
            color: "#8c8c8c"
            font.pixelSize: 20
            elide: Text.ElideRight
        }
        Text {
            id: wertText
            width: parent.width
            color: zeile.aktiv ? "white" : "#666666"
            font.pixelSize: 28
            elide: Text.ElideRight
        }
    }
    Image {
        id: pfeilBild
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        source: "image://theme/icon-m-common-drilldown-arrow-inverse"
        visible: zeile.pfeil
        width: visible ? implicitWidth : 0
    }
    MouseArea {
        id: maus
        anchors.fill: parent
        enabled: zeile.aktiv
        onClicked: zeile.clicked()
        onPressAndHold: zeile.gehalten()
    }
}
