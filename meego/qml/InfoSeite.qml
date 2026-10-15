import QtQuick 1.1
import com.nokia.meego 1.1
import "wf.js" as W

Page {
    id: seite
    tools: ToolBarLayout {
        ToolIcon { iconId: "toolbar-back"; onClicked: pageStack.pop() }
    }

    Kopf {
        id: kopf
        anchors.top: parent.top
        titel: "Über wegfinder"
        untertitel: "Version " + fenster.version
    }

    Flickable {
        anchors { top: kopf.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: text.height + 48
        clip: true
        Text {
            id: text
            x: 16
            y: 16
            width: parent.width - 32
            wrapMode: Text.WordWrap
            color: "white"
            font.pixelSize: 22
            textFormat: Text.RichText
            onLinkActivated: Dienst.oeffnen(link)
            text: "<p><b>Inoffizieller Client</b> für wegfinder auf MeeGo Harmattan (N9/N950) und Sailfish OS. "
                + "Nicht von der iMobility GmbH oder den ÖBB.</p>"
                + "<p>Routen mit Öffis, Rad, Auto, Sharing und Taxi, Abfahrten mit Echtzeit, Verkehrsmittel in der Nähe. "
                + "Buchen und Bezahlen gibt es hier bewusst nicht – dafür braucht es weder Konto noch Zahlungsdaten.</p>"
                + "<p>Daten: wegfinder-Schnittstelle (api.i-mobility.at), anonym. Karte: © OpenStreetMap-Mitwirkende, "
                + "Kacheln von tile.openstreetmap.org.</p>"
                + "<p>Favoriten und Verlauf bleiben auf dem Telefon.</p>"
                + "<p>Freie Software unter der GPLv3: "
                + "<a href=\"https://github.com/smatkovi/wegfinder\">github.com/smatkovi/wegfinder</a></p>"
        }
    }
}
