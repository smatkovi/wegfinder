import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../wf.js" as W

// Ort suchen: Haltestellen, Adressen, Orte. Ohne Suchtext: Mein Standort,
// Favoriten, zuletzt benutzte Orte. Gesucht wird erst, wenn eine Weile
// nicht getippt wurde.
Page {
    id: seite
    property string titel: "Ort"
    property var ergebnisse: []
    property var orte: ({ favoriten: [], verlauf: [], verbindungen: [] })
    property string fehler: ""
    signal gewaehlt(var ort)

    onStatusChanged: {
        if (status === PageStatus.Active) {
            feld.forceActiveFocus()
            fenster.standortAn()
        } else if (status === PageStatus.Deactivating) {
            fenster.standortAus()
        }
    }
    Component.onCompleted: ladeOrte.senden("orte", {})

    function nehmen(o) {
        if (o.typ !== "standort")
            merken.senden("ort_merken", { ort: o })
        seite.gewaehlt(o)
        pageStack.pop()
    }
    function eintraege() {
        if (feld.text.length >= 2)
            return seite.ergebnisse
        var l = [W.standortOrt(0, 0)], i
        for (i = 0; i < seite.orte.favoriten.length; ++i) {
            var f = W.kopie(seite.orte.favoriten[i])
            f.favorit = true
            l.push(f)
        }
        for (i = 0; i < seite.orte.verlauf.length; ++i)
            l.push(seite.orte.verlauf[i])
        return l
    }

    Anfrage { id: ladeOrte; onFertig: seite.orte = daten }
    Anfrage { id: merken; onFertig: seite.orte = daten }
    Anfrage {
        id: suche
        onFertig: { seite.ergebnisse = daten; seite.fehler = daten.length === 0 ? "Nichts gefunden." : "" }
        onFehler: seite.fehler = W.fehlerText(text)
    }
    Timer {
        id: warte
        interval: 500
        onTriggered: {
            if (feld.text.length < 2) {
                suche.abbrechen()
                seite.ergebnisse = []
                return
            }
            var w = { text: feld.text }
            if (fenster.standortDa) {
                w.lat = fenster.standortLat
                w.lon = fenster.standortLon
            }
            suche.senden("suche", w)
        }
    }

    PageHeader {
        id: kopf
        title: seite.titel
    }
    SearchField {
        id: feld
        anchors.top: kopf.bottom
        width: parent.width
        placeholderText: "Haltestelle, Adresse, Ort"
        inputMethodHints: Qt.ImhNoPredictiveText
        onTextChanged: { seite.fehler = ""; warte.restart() }
        EnterKey.onClicked: { warte.stop(); warte.triggered() }
    }

    SilicaListView {
        id: liste
        anchors { top: feld.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        header: Column {
            width: liste.width
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: seite.fehler !== ""
                text: seite.fehler
                color: Theme.secondaryHighlightColor
                wrapMode: Text.Wrap
            }
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Small
                running: suche.laeuft
                visible: running
            }
        }
        model: seite.eintraege()
        delegate: ListItem {
            id: eintrag
            contentHeight: Theme.itemSizeMedium
            menu: modelData.typ === "standort" ? null : kontext
            onClicked: seite.nehmen(modelData)
            Component {
                id: kontext
                ContextMenu {
                    MenuItem {
                        text: modelData.favorit ? "Aus Favoriten entfernen" : "Als Favorit merken"
                        onClicked: merken.senden(modelData.favorit ? "ort_entfernen" : "ort_merken", { ort: modelData, favorit: true })
                    }
                    MenuItem {
                        visible: !modelData.favorit
                        text: "Aus dem Verlauf entfernen"
                        onClicked: merken.senden("ort_entfernen", { ort: modelData, favorit: false })
                    }
                }
            }
            Rectangle {
                id: punkt
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconSizeMedium
                height: width
                radius: Theme.paddingSmall
                color: modelData.typ === "standort" ? W.BLAU : (modelData.favorit ? W.ROSA : Theme.rgba(Theme.primaryColor, 0.2))
                Image {
                    anchors.centerIn: parent
                    width: parent.width * 0.75
                    height: width
                    source: modelData.typ === "station" ? "../" + W.sinnbild(W.artAusTypen(modelData.arten)) : "../bilder/standort.png"
                }
            }
            Column {
                anchors { left: punkt.right; leftMargin: Theme.paddingMedium; right: parent.right; rightMargin: Theme.horizontalPageMargin
                          verticalCenter: parent.verticalCenter }
                Label {
                    width: parent.width
                    text: W.ortName(modelData)
                    truncationMode: TruncationMode.Fade
                    color: eintrag.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: modelData.typ === "standort" ? (fenster.standortDa ? "Aktuelle Position" : "Position wird gesucht …") : W.ortZusatz(modelData)
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    truncationMode: TruncationMode.Fade
                }
            }
        }
        VerticalScrollDecorator { }
    }
}
