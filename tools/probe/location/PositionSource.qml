import QtQuick 1.1

// Ersatz fuer QtMobility.location am Rechner (Probelauf): meldet nach
// einer Sekunde einen festen Standort am Wiener Westbahnhof.
Item {
    property bool active: false
    property int updateInterval: 1000
    property variant position: ({ latitudeValid: false, longitudeValid: false,
                                  coordinate: { latitude: 0, longitude: 0 } })
    Timer {
        running: parent.active
        interval: 1000
        onTriggered: parent.position = { latitudeValid: true, longitudeValid: true,
                                         coordinate: { latitude: 48.1966, longitude: 16.3378 } }
    }
}
