import QtQuick 1.1
import com.nokia.meego 1.1

// Die Titelleiste im Rosa von wegfinder, gebaut wie die Kopfzeilen der
// Standard-Apps (72 px hoch im Hochformat), mit optionaler Unterzeile und
// einem Drehrad, solange etwas laedt.
Rectangle {
    id: kopf
    property alias titel: titelText.text
    property alias untertitel: unterText.text
    property bool laedt: false
    signal clicked

    width: parent ? parent.width : 480
    height: screen.currentOrientation === Screen.Landscape ? 56 : 72
    color: "#ff4083"
    z: 10

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 3
        color: "#c92a62"
    }

    MouseArea { anchors.fill: parent; onClicked: kopf.clicked() }

    Column {
        anchors { left: parent.left; leftMargin: 16; right: rad.left; rightMargin: 8
                  verticalCenter: parent.verticalCenter; verticalCenterOffset: -1 }
        Text {
            id: titelText
            width: parent.width
            color: "white"
            font.pixelSize: unterText.text === "" ? 28 : 24
            font.family: "Nokia Pure Text Light"
            elide: Text.ElideRight
        }
        Text {
            id: unterText
            visible: text !== ""
            width: parent.width
            color: "#ffe0ea"
            font.pixelSize: 18
            elide: Text.ElideRight
        }
    }

    BusyIndicator {
        id: rad
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        running: kopf.laedt
        visible: kopf.laedt
        width: visible ? implicitWidth : 0
        platformStyle: BusyIndicatorStyle { inverted: true }
    }
}
