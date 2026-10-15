import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: spalte.height + Theme.paddingLarge
        Column {
            id: spalte
            width: parent.width
            spacing: Theme.paddingLarge
            PageHeader { title: "Über wegfinder"; description: "Version " + fenster.version }
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "/usr/share/icons/hicolor/172x172/apps/wegfinder.png"
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                textFormat: Text.StyledText
                linkColor: Theme.highlightColor
                onLinkActivated: Qt.openUrlExternally(link)
                text: "<p><b>Inoffizieller Client</b> für wegfinder auf Sailfish OS und MeeGo Harmattan. "
                    + "Nicht von der iMobility GmbH oder den ÖBB.</p><br>"
                    + "<p>Routen mit Öffis, Rad, Auto, Sharing und Taxi, Abfahrten mit Echtzeit, Verkehrsmittel in der Nähe. "
                    + "Öffi-Tickets lassen sich mit einem wegfinder-Konto kaufen (Kreditkarte oder PayPal) und offline vorzeigen; "
                    + "für alles andere braucht es kein Konto.</p><br>"
                    + "<p>Daten: wegfinder-Schnittstelle (api.i-mobility.at), anonym. Karte: © OpenStreetMap-Mitwirkende, "
                    + "Kacheln von tile.openstreetmap.org.</p><br>"
                    + "<p>Favoriten und Verlauf bleiben auf dem Telefon.</p><br>"
                    + "<p>Freie Software unter der GPLv3: <a href=\"https://github.com/smatkovi/wegfinder\">github.com/smatkovi/wegfinder</a></p>"
            }
        }
        VerticalScrollDecorator { }
    }
}
