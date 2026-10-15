import QtQuick 1.1

// Eine Anfrage an den Dienst, als Baustein fuer die Seiten.
//
//   Anfrage { id: suche; onFertig: liste = daten; onFehler: meldung(text) }
//   suche.senden("verbindungen", { von: 14, nach: 21 })
//
// Jede Antwort geht an alle Bausteine; jeder nimmt nur die mit seiner
// Nummer und zerlegt auch nur die. Wer neu sendet, bevor die alte Antwort
// da ist, bekommt die alte nicht mehr -- so ueberholt eine spaete Antwort
// auf eine verworfene Suche nie die aktuelle.
Item {
    id: anfrage
    property int nummer: -1
    property bool laeuft: nummer >= 0
    signal fertig(variant daten)
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
