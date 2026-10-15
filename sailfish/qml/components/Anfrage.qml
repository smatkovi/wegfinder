import QtQuick 2.0

// Eine Anfrage an den Dienst, als Baustein fuer die Seiten (wie am N9,
// meego/qml/Anfrage.qml).
//
//   Anfrage { id: suche; onFertig: liste = daten; onFehler: meldung(text) }
//   suche.senden("suche", { text: "Westbahnhof" })
//
// Jede Antwort geht an alle Bausteine; jeder nimmt nur die mit seiner
// Nummer. Wer neu sendet, bevor die alte Antwort da ist, bekommt die alte
// nicht mehr.
Item {
    id: anfrage
    property int nummer: -1
    property bool laeuft: nummer >= 0
    signal fertig(var daten)
    signal fehler(string text)

    function senden(befehl, werte) {
        nummer = Dienst.anfrage(befehl, JSON.stringify(werte ? werte : {}))
    }
    function abbrechen() { nummer = -1 }

    Connections {
        target: Dienst
        onAntwort: {
            if (id !== anfrage.nummer)
                return
            anfrage.nummer = -1
            var wert
            try {
                wert = JSON.parse(daten)
            } catch (e) {
                anfrage.fehler("Unlesbare Antwort des Dienstes")
                return
            }
            if (ok)
                anfrage.fertig(wert)
            else
                anfrage.fehler(String(wert))
        }
    }
}
