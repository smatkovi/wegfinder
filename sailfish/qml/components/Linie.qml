import QtQuick 2.0
import Sailfish.Silica 1.0
import "../wf.js" as W

// Linienmarke: Sinnbild und Linie auf der Farbe des Verkehrsmittels.
Rectangle {
    id: marke
    property string art: "sonst"
    property string text: ""
    property string farbe: "#666666"
    property int groesse: Theme.itemSizeExtraSmall * 0.55

    width: reihe.width + Theme.paddingSmall * 2
    height: groesse
    radius: Theme.paddingSmall / 2
    color: farbe
    Row {
        id: reihe
        x: Theme.paddingSmall
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.paddingSmall / 2
        Image {
            anchors.verticalCenter: parent.verticalCenter
            source: "../" + W.sinnbild(marke.art)
            width: marke.groesse - Theme.paddingSmall
            height: width
            smooth: true
            Rectangle {
                anchors.fill: parent
                anchors.margins: -1
                z: -1
                radius: 3
                color: "#55000000"
                visible: W.schriftAuf(marke.farbe) !== "#ffffff"
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: marke.text !== ""
            text: marke.text
            color: W.schriftAuf(marke.farbe)
            font.pixelSize: marke.groesse * 0.62
            font.bold: true
        }
    }
}
