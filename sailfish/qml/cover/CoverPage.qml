import QtQuick 2.0
import Sailfish.Silica 1.0
import "../wf.js" as W

CoverBackground {
    Image {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: Theme.paddingLarge }
        source: "/usr/share/icons/hicolor/108x108/apps/wegfinder.png"
        opacity: 0.35
    }
    Column {
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: Theme.paddingLarge }
        spacing: Theme.paddingSmall
        Label {
            width: parent.width
            text: fenster.letzteRoute ? fenster.letzteRoute.ab.zeit + " – " + fenster.letzteRoute.an.zeit : "wegfinder"
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.primaryColor
            horizontalAlignment: Text.AlignHCenter
        }
        Label {
            width: parent.width
            visible: !!fenster.letzteRoute
            text: fenster.letzteRoute ? fenster.letzteRoute.titel : ""
            color: Theme.highlightColor
            truncationMode: TruncationMode.Fade
            horizontalAlignment: Text.AlignHCenter
        }
        Label {
            width: parent.width
            visible: !!fenster.letzteRoute
            text: fenster.letzteRoute && fenster.letzteRoute.erste_fahrt ? "ab " + fenster.letzteRoute.erste_fahrt.name : ""
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
            wrapMode: Text.Wrap
            maximumLineCount: 2
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
