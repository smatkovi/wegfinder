import QtQuick 2.0
import Sailfish.Silica 1.0
import "../wf.js" as W

// Titelbild: die zuletzt angesehene Verbindung. Das Titelbild ist schmal
// (je nach Geraet ein Drittel bis die Haelfte der Bildschirmbreite): die
// Zeiten schrumpfen auf die Breite, alles andere bricht um statt
// abgeschnitten zu werden.
CoverBackground {
    id: titel
    readonly property var r: fenster.letzteRoute

    Image {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Theme.paddingLarge }
        width: parent.width * 0.45
        height: width
        source: "/usr/share/icons/hicolor/172x172/apps/wegfinder.png"
        opacity: titel.r ? 0.15 : 0.6
        smooth: true
    }

    Label {
        anchors.centerIn: parent
        visible: !titel.r
        text: "wegfinder"
        font.pixelSize: Theme.fontSizeLarge
    }

    Column {
        visible: !!titel.r
        anchors { left: parent.left; right: parent.right; top: parent.top
                  leftMargin: Theme.paddingMedium; rightMargin: Theme.paddingMedium; topMargin: Theme.paddingLarge }
        spacing: Theme.paddingSmall

        Label {
            width: parent.width
            text: titel.r ? titel.r.ab.zeit + "–" + titel.r.an.zeit : ""
            font.pixelSize: Theme.fontSizeLarge
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Theme.fontSizeExtraSmall
            horizontalAlignment: Text.AlignHCenter
        }
        Label {
            width: parent.width
            text: titel.r ? W.verbinden([titel.r.dauer, titel.r.gruppe === "oeffi"
                                         ? (titel.r.umstiege === 1 ? "1 Umst." : titel.r.umstiege + " Umst.") : ""], " · ") : ""
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
        Label {
            width: parent.width
            text: titel.r ? titel.r.titel : ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.highlightColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
        Label {
            width: parent.width
            visible: text !== ""
            text: titel.r && titel.r.erste_fahrt ? "ab " + titel.r.erste_fahrt.name
                  + (titel.r.erste_fahrt.gleis !== "" ? ", Gl. " + titel.r.erste_fahrt.gleis : "") : ""
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
    }
}
