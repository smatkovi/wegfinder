import QtQuick 1.1
import com.nokia.meego 1.1
import QtMobility.location 1.2
import "wf.js" as W

// wegfinder fuer Harmattan. Eine Datei je Seite; ins Netz geht alles ueber
// den Dienst (Kontexteigenschaft "Dienst", Baustein Anfrage.qml).
PageStackWindow {
    id: fenster
    showStatusBar: true
    initialPage: StartSeite { }

    // vom Dienst beim Start
    property variant einst: ({ weitere_laden: "wlan", karte_mobil: "sparsam", abfahrten_max: 30 })
    property bool wlan: false
    property string kachelBasis: ""
    property string version: ""

    // Standort: nur an, solange eine Seite ihn braucht (Akku).
    property int standortNutzer: 0
    property bool standortDa: false
    property real standortLat: 0
    property real standortLon: 0

    function standortAn() { standortNutzer = standortNutzer + 1 }
    function standortAus() { standortNutzer = Math.max(0, standortNutzer - 1) }

    PositionSource {
        id: gps
        active: fenster.standortNutzer > 0 && platformWindow.active
        updateInterval: 5000
        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid) {
                fenster.standortLat = position.coordinate.latitude
                fenster.standortLon = position.coordinate.longitude
                fenster.standortDa = true
            }
        }
    }

    // Kacheln laden? Im WLAN immer, sonst nach Einstellung.
    function kartenModus() {
        if (wlan)
            return "voll"
        return einst.karte_mobil
    }
    // Weitere Verkehrsmittel (Sharing, Rad, Auto, Taxi) gleich mitladen?
    function weitereAutomatisch() {
        var w = einst.weitere_laden
        return w === "immer" || (w === "wlan" && wlan)
    }
    function netzPruefen() { netz.senden("netz", {}) }

    Component.onCompleted: {
        theme.inverted = true
        start.senden("start", {})
        kacheln.senden("kacheln", {})
    }

    Anfrage {
        id: start
        onFertig: {
            fenster.einst = daten.einstellungen
            fenster.wlan = daten.wlan
            fenster.version = daten.version
        }
    }
    Anfrage {
        id: kacheln
        onFertig: fenster.kachelBasis = "http://127.0.0.1:" + daten.port
    }
    Anfrage {
        id: netz
        onFertig: fenster.wlan = daten.wlan
    }
    // Wechselt das Netz, merkt die App es beim naechsten Vordergrund.
    Connections {
        target: platformWindow
        onActiveChanged: if (platformWindow.active) fenster.netzPruefen()
    }

    // Kurze Meldung oben, verschwindet nach vier Sekunden.
    function meldung(text) {
        bannerText.text = text
        banner.opacity = 1
        bannerZeit.restart()
    }

    Rectangle {
        id: banner
        z: 100
        x: 8
        y: 44
        width: parent.width - 16
        height: bannerText.height + 32
        radius: 6
        color: "#e6202020"
        border.color: W.ROSA
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Text {
            id: bannerText
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 32
            wrapMode: Text.WordWrap
            color: "white"
            font.pixelSize: 22
        }
        MouseArea { anchors.fill: parent; onClicked: banner.opacity = 0 }
        Timer { id: bannerZeit; interval: 4000; onTriggered: banner.opacity = 0 }
    }
}
