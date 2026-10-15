import QtQuick 2.0
import Sailfish.Silica 1.0
import QtPositioning 5.2
import "pages"
import "components"
import "wf.js" as W

// wegfinder fuer Sailfish. Eine Datei je Seite (pages/); ins Netz geht alles
// ueber den Dienst (Kontexteigenschaft "Dienst", components/Anfrage.qml) --
// derselbe Rust-Dienst wie am N9.
ApplicationWindow {
    id: fenster
    initialPage: Component { StartSeite { } }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations

    property var einst: ({ weitere_laden: "immer", karte_mobil: "voll", abfahrten_max: 60, umgebung_filter: "public" })
    property bool wlan: false
    property string kachelBasis: ""
    property string version: ""
    // fuers Titelbild: die zuletzt angesehene Verbindung
    property var letzteRoute: null

    property int standortNutzer: 0
    property bool standortDa: false
    property real standortLat: 0
    property real standortLon: 0
    function standortAn() { standortNutzer = standortNutzer + 1 }
    function standortAus() { standortNutzer = Math.max(0, standortNutzer - 1) }

    PositionSource {
        id: gps
        active: fenster.standortNutzer > 0 && Qt.application.state === Qt.ApplicationActive
        updateInterval: 5000
        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid) {
                fenster.standortLat = position.coordinate.latitude
                fenster.standortLon = position.coordinate.longitude
                fenster.standortDa = true
            }
        }
    }

    function kartenModus() {
        return wlan ? "voll" : einst.karte_mobil
    }
    function weitereAutomatisch() {
        var w = einst.weitere_laden
        return w === "immer" || (w === "wlan" && wlan)
    }

    Component.onCompleted: {
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
    Anfrage { id: kacheln; onFertig: fenster.kachelBasis = "http://127.0.0.1:" + daten.port }
    Anfrage { id: netz; onFertig: fenster.wlan = daten.wlan }
    Connections {
        target: Qt.application
        onStateChanged: if (Qt.application.state === Qt.ApplicationActive) netz.senden("netz", {})
    }

    function meldung(text) {
        notiz.text = text
        notiz.show()
    }
    Notice {
        id: notiz
        duration: Notice.Long
    }
}
