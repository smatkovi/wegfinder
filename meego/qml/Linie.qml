import QtQuick 1.1
import "wf.js" as W

// Linienmarke: Sinnbild und Linie auf der Farbe des Verkehrsmittels.
Rectangle {
    id: marke
    property string art: "sonst"
    property string text: ""
    property string farbe: "#666666"
    property int groesse: 30

    width: reihe.width + 10
    height: groesse
    radius: 4
    color: farbe
    Row {
        id: reihe
        x: 5
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Image {
            anchors.verticalCenter: parent.verticalCenter
            source: W.sinnbild(marke.art)
            width: marke.groesse - 8
            height: width
            smooth: true
            // Schwarzes Sinnbild auf hellen Farben gibt es nicht; dort hilft
            // ein dunkler Grund unter dem Bild.
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
            font.pixelSize: marke.groesse - 10
            font.bold: true
        }
    }
}
