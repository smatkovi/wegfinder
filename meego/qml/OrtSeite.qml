import QtQuick 1.1
import com.nokia.meego 1.1
import "wf.js" as W

// Ort suchen: Haltestellen, Adressen, Orte. Ohne Suchtext: Mein Standort,
// Favoriten, zuletzt benutzte Orte. Gesucht wird erst, wenn eine Weile
// nicht getippt wurde -- im 2G-Netz kostet jede Anfrage eine Sekunde.
Page {
    id: seite
    property string titel: "Ort"
    property variant ergebnisse: []
    property variant orte: ({ favoriten: [], verlauf: [], verbindungen: [] })
    property variant gedrueckt: null
    property bool gedruecktFavorit: false
    property string fehler: ""
    signal gewaehlt(variant ort)

    tools: ToolBarLayout {
        ToolIcon { iconId: "toolbar-back"; onClicked: pageStack.pop() }
    }

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

    // Eintraege: ohne Suchtext Standort + Favoriten + Verlauf
    function eintraege() {
        if (feld.text.length >= 2)
            return seite.ergebnisse
        var l = [W.standortOrt(0, 0)]
        var i
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
    Anfrage {
        id: merken
        onFertig: seite.orte = daten
    }
    Anfrage {
        id: suche
        onFertig: { seite.ergebnisse = daten; seite.fehler = daten.length === 0 ? "Nichts gefunden." : "" }
        onFehler: seite.fehler = W.fehlerText(text)
    }
    Timer {
        id: warte
        interval: 700
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

    ContextMenu {
        id: menue
        MenuLayout {
            MenuItem {
                text: seite.gedruecktFavorit ? "Aus Favoriten entfernen" : "Als Favorit merken"
                onClicked: merken.senden(seite.gedruecktFavorit ? "ort_entfernen" : "ort_merken",
                                         { ort: seite.gedrueckt, favorit: true })
            }
            MenuItem {
                text: "Aus dem Verlauf entfernen"
                visible: !seite.gedruecktFavorit
                onClicked: merken.senden("ort_entfernen", { ort: seite.gedrueckt, favorit: false })
            }
        }
    }

    Kopf {
        id: kopf
        anchors.top: parent.top
        titel: seite.titel
        laedt: suche.laeuft
    }

    TextField {
        id: feld
        anchors { top: kopf.bottom; topMargin: 12; left: parent.left; leftMargin: 16; right: parent.right; rightMargin: 16 }
        placeholderText: "Haltestelle, Adresse, Ort"
        inputMethodHints: Qt.ImhNoPredictiveText
        onTextChanged: { seite.fehler = ""; warte.restart() }
        Keys.onReturnPressed: { warte.stop(); warte.triggered() }
        Image {
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            source: "image://theme/icon-m-input-clear"
            visible: feld.text !== ""
            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: feld.text = "" }
        }
    }

    ListView {
        id: liste
        anchors { top: feld.bottom; topMargin: 8; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        model: seite.eintraege()
        delegate: Item {
            id: eintrag
            width: liste.width
            height: 84
            Rectangle { anchors.fill: parent; color: "#26ffffff"; visible: maus.pressed }
            Rectangle {
                id: punkt
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                radius: 6
                color: modelData.typ === "standort" ? W.BLAU : (modelData.favorit ? W.ROSA : "#3d3d3d")
                Image {
                    anchors.centerIn: parent
                    width: 30
                    height: 30
                    smooth: true
                    source: modelData.typ === "station" ? W.sinnbild(W.artAusTypen(modelData.arten)) : "bilder/standort.png"
                }
            }
            Column {
                anchors { left: punkt.right; leftMargin: 14; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                Text {
                    width: parent.width
                    text: W.ortName(modelData)
                    color: "white"
                    font.pixelSize: 26
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: modelData.typ === "standort"
                          ? (fenster.standortDa ? "Aktuelle Position" : "Position wird gesucht …")
                          : W.ortZusatz(modelData)
                    color: "#8c8c8c"
                    font.pixelSize: 20
                    elide: Text.ElideRight
                }
            }
            MouseArea {
                id: maus
                anchors.fill: parent
                onClicked: seite.nehmen(modelData)
                onPressAndHold: {
                    if (modelData.typ === "standort")
                        return
                    seite.gedrueckt = modelData
                    seite.gedruecktFavorit = modelData.favorit === true
                    menue.open()
                }
            }
        }
        header: Text {
            width: liste.width
            visible: seite.fehler !== ""
            height: visible ? 60 : 0
            text: seite.fehler
            color: "#8c8c8c"
            font.pixelSize: 22
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
        }
    }
    ScrollDecorator { flickableItem: liste }
}
