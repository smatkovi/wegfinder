import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../wf.js" as W

// Abfahrten einer Station mit Echtzeit, Gleis/Steig und Ausfaellen;
// antippen zeigt den Verlauf der Fahrt.
Page {
    id: seite
    property string station: ""
    property string name: ""
    property var daten: null
    property string fehler: ""

    Component.onCompleted: laden(false)
    function laden(neu) {
        fehler = ""
        anfrage.senden("abfahrten", { station: station, neu: neu })
    }
    Anfrage {
        id: anfrage
        onFertig: { seite.daten = daten; if (daten.abfahrten.length === 0) seite.fehler = "Keine Abfahrten in nächster Zeit." }
        onFehler: seite.fehler = W.fehlerText(text)
    }
    function routeHierher() {
        var start = pageStack.find(function(p) { return p.suchen !== undefined && p.nach !== undefined })
        if (start) {
            start.nach = { id: seite.station, name: seite.name, unter: "", typ: "station", lat: 0, lon: 0, bezeichnung: "" }
            pageStack.pop(start)
        }
    }

    SilicaListView {
        id: liste
        anchors.fill: parent
        PullDownMenu {
            busy: anfrage.laeuft
            MenuItem { text: "Route hierher"; onClicked: seite.routeHierher() }
            MenuItem { text: "Neu laden"; onClicked: seite.laden(true) }
        }
        header: PageHeader {
            title: seite.name
            description: seite.daten ? "Abfahrten · Stand " + seite.daten.stand : "Abfahrten"
        }
        model: seite.daten ? seite.daten.abfahrten : []
        delegate: BackgroundItem {
            id: eintrag
            height: Theme.itemSizeMedium
            enabled: modelData.fahrt !== ""
            onClicked: pageStack.push(Qt.resolvedUrl("FahrtSeite.qml"),
                                      { url: modelData.fahrt, titel: modelData.linie + " → " + modelData.richtung,
                                        farbe: modelData.farbe, station: seite.name })
            Column {
                id: zeit
                x: Theme.horizontalPageMargin
                width: Theme.itemSizeMedium * 0.95
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    text: modelData.zeit
                    color: modelData.ausgefallen ? "#ff6666" : Theme.primaryColor
                    font.strikeout: modelData.ausgefallen
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    visible: text !== ""
                    text: modelData.ausgefallen ? "fällt aus" : (modelData.echtzeit ? (modelData.verspaetung !== 0 ? modelData.live : "pünktlich") : "")
                    color: modelData.ausgefallen || modelData.verspaetung > 0 ? "#ff6666" : "#5cb85c"
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }
            Linie {
                id: marke
                anchors { left: zeit.right; leftMargin: Theme.paddingMedium; verticalCenter: parent.verticalCenter }
                art: modelData.art
                text: modelData.linie
                farbe: modelData.farbe
            }
            Column {
                anchors { left: marke.right; leftMargin: Theme.paddingMedium; right: gleis.left; rightMargin: Theme.paddingSmall
                          verticalCenter: parent.verticalCenter }
                Label {
                    width: parent.width
                    text: modelData.richtung
                    truncationMode: TruncationMode.Fade
                    color: eintrag.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    visible: text !== ""
                    text: modelData.meldungen.length > 0 ? modelData.meldungen[0].text : W.inMinuten(modelData.wann)
                    color: modelData.meldungen.length > 0 ? "#ffb347" : Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                }
            }
            Label {
                id: gleis
                anchors { right: parent.right; rightMargin: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                text: modelData.gleis
                color: modelData.gleiswechsel ? "#ffb347" : Theme.secondaryColor
            }
        }
        footer: Label {
            x: Theme.horizontalPageMargin
            width: liste.width - 2 * Theme.horizontalPageMargin
            height: visible ? Theme.itemSizeMedium : 0
            visible: seite.fehler !== "" || (!!seite.daten && seite.daten.gesamt > seite.daten.abfahrten.length)
            text: seite.fehler !== "" ? seite.fehler
                  : (seite.daten ? "Weitere " + (seite.daten.gesamt - seite.daten.abfahrten.length) + " Abfahrten ausgeblendet (Einstellungen)." : "")
            color: Theme.secondaryHighlightColor
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: anfrage.laeuft && !seite.daten
        }
        VerticalScrollDecorator { }
    }
}
