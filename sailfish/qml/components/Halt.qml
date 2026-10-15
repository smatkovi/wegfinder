import QtQuick 2.0
import Sailfish.Silica 1.0
import "../wf.js" as W

// Ein Halt im Verlauf: links Zeit (und Echtzeit), ein Punkt auf der Linie,
// rechts Name und Gleis/Steig. Antippbar, wenn der Halt eine Kennung hat.
BackgroundItem {
    id: halt
    property var h: null
    property string farbe: "#8c8c8c"
    property bool fett: false
    property real linieX: Theme.horizontalPageMargin + zeitSpalte.width + Theme.paddingMedium + Theme.paddingSmall

    width: parent ? parent.width : Screen.width
    height: Math.max(Theme.itemSizeSmall, name.height + Theme.paddingMedium * 2)
    enabled: !!h && h.id !== ""

    Column {
        id: zeitSpalte
        x: Theme.horizontalPageMargin
        width: Theme.itemSizeMedium * 0.95
        anchors.verticalCenter: parent.verticalCenter
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: halt.h ? halt.h.zeit : ""
            color: halt.h && halt.h.ausgefallen ? "#ff6666" : Theme.primaryColor
            font.strikeout: !!halt.h && halt.h.ausgefallen
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            visible: text !== ""
            text: halt.h && halt.h.echtzeit ? (halt.h.verspaetung !== 0 ? halt.h.live : "pünktlich") : ""
            color: halt.h && halt.h.verspaetung > 0 ? "#ff6666" : "#5cb85c"
            font.pixelSize: Theme.fontSizeExtraSmall
        }
    }
    Rectangle {
        x: halt.linieX - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.paddingLarge
        height: width
        radius: width / 2
        color: "white"
        border.width: Theme.paddingSmall
        border.color: halt.farbe
    }
    Label {
        id: name
        anchors { left: parent.left; leftMargin: halt.linieX + Theme.paddingLarge; right: gleis.left; rightMargin: Theme.paddingSmall
                  verticalCenter: parent.verticalCenter }
        text: halt.h ? halt.h.name : ""
        font.bold: halt.fett
        wrapMode: Text.Wrap
        maximumLineCount: 2
        color: halt.highlighted ? Theme.highlightColor : Theme.primaryColor
    }
    Label {
        id: gleis
        anchors { right: parent.right; rightMargin: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
        visible: text !== ""
        text: halt.h && halt.h.gleis !== "" ? "Gl. " + halt.h.gleis : ""
        color: halt.h && halt.h.gleiswechsel ? "#ffb347" : Theme.secondaryColor
        font.pixelSize: Theme.fontSizeSmall
    }
}
