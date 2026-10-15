import QtQuick 1.1
import com.nokia.meego 1.1
import "wf.js" as W

// Verbindungen: zuerst die Oeffis (eine Anfrage), danach -- je nach
// Einstellung sofort oder auf Knopfdruck -- Rad, Auto, Sharing und Taxi.
// Der Server liefert dafuer fertige Adressen ("offen"), eine je Gruppe;
// geladen wird eine nach der anderen, damit im 2G-Netz die erste Antwort
// nicht auf die letzte warten muss.
Page {
    id: seite
    property variant von: null
    property variant nach: null
    property variant wann: null

    property variant gruppen: []
    property variant offen: []
    property variant meldungen: []
    property string fehler: ""
    property bool fertig: false

    // feste Hoehen: so bleibt die Liste beim Nachladen stehen
    property int hKopf: 56
    property int hKnopf: 76
    property int hRoute: 124
    property alias liste: liste

    tools: ToolBarLayout {
        ToolIcon { iconId: "toolbar-back"; onClicked: pageStack.pop() }
        ToolIcon { iconId: "toolbar-refresh"; onClicked: seite.laden() }
        ToolIcon {
            iconId: "toolbar-shuffle"
            onClicked: {
                var v = seite.von
                seite.von = seite.nach
                seite.nach = v
                seite.laden()
            }
        }
    }

    Component.onCompleted: laden()

    function laden() {
        gruppen = []
        offen = []
        meldungen = []
        fehler = ""
        fertig = false
        mehr.abbrechen()
        blaettern.abbrechen()
        var w = { von: von, nach: nach }
        if (wann && wann.zeit !== "") {
            w.zeit = wann.zeit
            w.datum = wann.datum
            w.ankunft = wann.ankunft
        }
        haupt.senden("routen", w)
    }

    // Neue Gruppen einsortieren; Gruppen mit gleichem Schluessel (die drei
    // "buchbaren" des Servers) zusammenlegen. wo: "vorne" | "hinten" | ""
    function einfuegen(neu, wo) {
        var g = W.kopie(gruppen)
        for (var i = 0; i < neu.gruppen.length; ++i) {
            var n = neu.gruppen[i]
            var idx = -1
            for (var j = 0; j < g.length; ++j)
                if (g[j].schluessel === n.schluessel) idx = j
            if (idx < 0) {
                g.push(n)
                continue
            }
            var alt = g[idx].routen, ids = {}
            for (j = 0; j < alt.length; ++j) ids[alt[j].id] = true
            var dazu = []
            for (j = 0; j < n.routen.length; ++j)
                if (!ids[n.routen[j].id]) dazu.push(n.routen[j])
            if (wo === "vorne") {
                g[idx].routen = dazu.concat(alt)
                g[idx].frueher = n.frueher
            } else {
                g[idx].routen = alt.concat(dazu)
                if (wo === "hinten")
                    g[idx].spaeter = n.spaeter
            }
        }
        g.sort(function(a, b) { return a.rang - b.rang })
        gruppen = g
        if (neu.meldungen && neu.meldungen.length > 0 && wo === "")
            meldungen = meldungen.concat(neu.meldungen)
    }

    function eintraege() {
        var l = []
        for (var i = 0; i < gruppen.length; ++i) {
            var g = gruppen[i]
            if (g.routen.length === 0)
                continue
            l.push({ typ: "kopf", text: g.titel, hinweis: g.hinweis })
            if (g.schluessel === "oeffi" && g.frueher !== "")
                l.push({ typ: "knopf", was: "frueher", text: "Früher", url: g.frueher })
            for (var j = 0; j < g.routen.length; ++j)
                l.push({ typ: "route", r: g.routen[j] })
            if (g.schluessel === "oeffi" && g.spaeter !== "")
                l.push({ typ: "knopf", was: "spaeter", text: "Später", url: g.spaeter })
        }
        return l
    }

    function naechsteOffene() {
        if (offen.length === 0) {
            fertig = true
            return
        }
        var o = W.kopie(offen)
        var url = o.shift()
        offen = o
        mehr.senden("routen_url", { url: url })
    }

    Anfrage {
        id: haupt
        onFertig: {
            seite.einfuegen(daten, "")
            seite.offen = daten.offen
            if (seite.gruppen.length === 0 && daten.offen.length === 0)
                seite.fehler = daten.meldungen.length > 0 ? daten.meldungen[0].text : "Keine Verbindung gefunden."
            if (fenster.weitereAutomatisch())
                seite.naechsteOffene()
        }
        onFehler: seite.fehler = W.fehlerText(text)
    }
    Anfrage {
        id: mehr
        onFertig: {
            seite.einfuegen(daten, "")
            seite.naechsteOffene()
        }
        onFehler: { fenster.meldung(W.fehlerText(text)); seite.naechsteOffene() }
    }
    Anfrage {
        id: blaettern
        property string wo: ""
        onFertig: {
            var vorher = liste.contentY
            var anzahl = 0
            for (var i = 0; i < seite.gruppen.length; ++i)
                if (seite.gruppen[i].schluessel === "oeffi") anzahl = seite.gruppen[i].routen.length
            seite.einfuegen(daten, wo)
            var neu = 0
            for (i = 0; i < seite.gruppen.length; ++i)
                if (seite.gruppen[i].schluessel === "oeffi") neu = seite.gruppen[i].routen.length
            // Neue Routen oben: um deren Hoehe weiter unten bleiben
            liste.contentY = vorher + (wo === "vorne" ? (neu - anzahl) * seite.hRoute : 0)
        }
        onFehler: fenster.meldung(W.fehlerText(text))
    }

    Kopf {
        id: kopf
        anchors.top: parent.top
        titel: W.ortName(seite.von) + " → " + W.ortName(seite.nach)
        untertitel: W.zeitAnzeige(seite.wann)
        laedt: haupt.laeuft || mehr.laeuft || blaettern.laeuft
    }

    ListView {
        id: liste
        anchors { top: kopf.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        model: seite.eintraege()
        delegate: Item {
            id: zeile
            // Ein leeres variant liest sich unter Qt 4.7 als undefined, nicht
            // als null: deshalb ein eigener Wahrheitswert.
            property bool istRoute: modelData.typ === "route"
            property variant r: istRoute ? modelData.r : null
            property bool oeffi: istRoute && r.gruppe === "oeffi"
            width: liste.width
            height: modelData.typ === "kopf" ? seite.hKopf : (modelData.typ === "knopf" ? seite.hKnopf : seite.hRoute)

            // --- Gruppenkopf ---
            Ueberschrift {
                visible: modelData.typ === "kopf"
                x: 16
                width: parent.width - 32
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.typ === "kopf" ? modelData.text : ""
            }

            // --- Frueher / Spaeter ---
            Button {
                visible: modelData.typ === "knopf"
                anchors.centerIn: parent
                width: parent.width - 64
                text: modelData.typ === "knopf" ? modelData.text : ""
                enabled: !blaettern.laeuft
                onClicked: {
                    blaettern.wo = modelData.was === "frueher" ? "vorne" : "hinten"
                    blaettern.senden("routen_url", { url: modelData.url })
                }
            }

            // --- Route ---
            Item {
                visible: zeile.istRoute
                anchors.fill: parent
                Rectangle { anchors.fill: parent; color: "#26ffffff"; visible: maus.pressed }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16 }
                    height: 1
                    color: "#333333"
                }

                // Oeffis: Zeiten gross; sonst Sinnbild und Titel
                Linie {
                    id: sinn
                    visible: zeile.istRoute && !zeile.oeffi
                    x: 16
                    y: 18
                    groesse: 40
                    art: zeile.r ? zeile.r.art : "sonst"
                    farbe: zeile.r ? zeile.r.farbe : "#666666"
                }
                Text {
                    id: hauptText
                    anchors { left: zeile.oeffi ? parent.left : sinn.right; leftMargin: 16; right: dauerText.left; rightMargin: 8 }
                    y: 14
                    color: zeile.r && zeile.r.ausgefallen ? "#ff6666" : "white"
                    font.pixelSize: 28
                    elide: Text.ElideRight
                    text: {
                        if (!zeile.r) return ""
                        if (zeile.oeffi)
                            return zeile.r.ab.zeit + " – " + zeile.r.an.zeit + (zeile.r.an.tag !== "" ? " (" + zeile.r.an.tag + ")" : "")
                        return zeile.r.titel + (zeile.r.anbieter !== "" && zeile.r.anbieter !== zeile.r.titel ? " · " + zeile.r.anbieter : "")
                    }
                }
                Text {
                    id: dauerText
                    anchors { right: parent.right; rightMargin: 16; baseline: hauptText.baseline }
                    text: zeile.r ? zeile.r.dauer : ""
                    color: "white"
                    font.pixelSize: 24
                }
                // Verspaetung der ersten Fahrt
                Text {
                    anchors { left: hauptText.left; top: hauptText.bottom }
                    visible: zeile.oeffi && text !== ""
                    text: {
                        if (!zeile.r) return ""
                        if (zeile.r.ausgefallen) return "Fällt aus"
                        var f = zeile.r.erste_fahrt
                        if (f && f.echtzeit && f.verspaetung > 0) return "ab " + f.live + " (+" + f.verspaetung + ")"
                        if (f && f.echtzeit) return "pünktlich"
                        return ""
                    }
                    color: zeile.r && (zeile.r.ausgefallen || (zeile.r.erste_fahrt && zeile.r.erste_fahrt.verspaetung > 0)) ? "#ff6666" : "#7ed67e"
                    font.pixelSize: 18
                }
                Row {
                    id: marken
                    visible: zeile.oeffi
                    anchors { left: parent.left; leftMargin: 16; right: parent.right; rightMargin: 16 }
                    y: 70
                    spacing: 6
                    clip: true
                    Repeater {
                        model: zeile.oeffi ? zeile.r.linien : []
                        Linie { art: modelData.art; text: modelData.text; farbe: modelData.farbe; groesse: 30 }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: zeile.oeffi ? (zeile.r.umstiege === 1 ? "1 Umstieg" : zeile.r.umstiege + " Umstiege") : ""
                        color: "#8c8c8c"
                        font.pixelSize: 18
                    }
                }
                Text {
                    visible: !zeile.oeffi
                    anchors { left: hauptText.left; right: parent.right; rightMargin: 16 }
                    y: 58
                    elide: Text.ElideRight
                    color: "#8c8c8c"
                    font.pixelSize: 20
                    text: {
                        if (!zeile.r || zeile.oeffi) return ""
                        var t = []
                        if (zeile.r.untertitel !== "") t.push(zeile.r.untertitel)
                        else if (zeile.r.strecke !== "") t.push(zeile.r.strecke)
                        if (zeile.r.ab.zeit !== "") t.push("ab " + zeile.r.ab.zeit)
                        if (zeile.r.an.zeit !== "") t.push("an " + zeile.r.an.zeit)
                        return t.join(" · ")
                    }
                }
                Text {
                    anchors { left: hauptText.left; right: parent.right; rightMargin: 16 }
                    y: zeile.oeffi ? 100 : 86
                    elide: Text.ElideRight
                    color: "#8c8c8c"
                    font.pixelSize: 18
                    visible: text !== ""
                    text: {
                        if (!zeile.r) return ""
                        if (zeile.oeffi) {
                            var f = zeile.r.erste_fahrt
                            return f ? "ab " + f.name + (f.gleis !== "" ? ", Gleis/Steig " + f.gleis : "") : ""
                        }
                        return zeile.r.meldungen.length > 0 ? zeile.r.meldungen[0].text : ""
                    }
                }
                MouseArea {
                    id: maus
                    anchors.fill: parent
                    onClicked: pageStack.push(Qt.resolvedUrl("RoutenSeite.qml"), { route: zeile.r })
                }
            }
        }

        footer: Column {
            width: liste.width
            spacing: 12
            Item { width: 1; height: 8 }
            Text {
                x: 16
                width: parent.width - 32
                visible: seite.fehler !== ""
                text: seite.fehler
                color: "#ff8080"
                font.pixelSize: 22
                wrapMode: Text.WordWrap
            }
            Repeater {
                model: seite.meldungen
                Text {
                    x: 16
                    width: parent.width - 32
                    visible: modelData.text !== "" && seite.gruppen.length > 0
                    text: (modelData.titel !== "" ? modelData.titel + ": " : "") + modelData.text
                    color: "#8c8c8c"
                    font.pixelSize: 20
                    wrapMode: Text.WordWrap
                }
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 64
                visible: seite.offen.length > 0 && !mehr.laeuft && !haupt.laeuft
                text: "Rad, Auto, Sharing, Taxi laden"
                onClicked: seite.naechsteOffene()
            }
            Text {
                x: 16
                width: parent.width - 32
                visible: seite.offen.length > 0 && !mehr.laeuft && !haupt.laeuft
                text: fenster.wlan ? "" : "Im Mobilfunknetz nur auf Wunsch (Einstellungen)."
                color: "#8c8c8c"
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                x: 16
                width: parent.width - 32
                visible: mehr.laeuft
                text: "Lade weitere Verkehrsmittel …"
                color: "#8c8c8c"
                font.pixelSize: 20
                horizontalAlignment: Text.AlignHCenter
            }
            Item { width: 1; height: 16 }
        }
    }
    ScrollDecorator { flickableItem: liste }
}
