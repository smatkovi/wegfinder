import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../wf.js" as W

// Verbindungen: zuerst die Oeffis, danach -- je nach Einstellung sofort oder
// auf Knopfdruck -- Rad, Auto, Sharing und Taxi (wie am N9,
// meego/qml/ErgebnisSeite.qml).
Page {
    id: seite
    property var von: null
    property var nach: null
    property var wann: null

    property var gruppen: []
    property var offen: []
    property var meldungen: []
    property string fehler: ""

    property real hKopf: Theme.itemSizeExtraSmall
    property real hKnopf: Theme.itemSizeMedium

    Component.onCompleted: laden()

    function laden() {
        gruppen = []
        offen = []
        meldungen = []
        fehler = ""
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

    function einfuegen(neu, wo) {
        var g = W.kopie(gruppen)
        for (var i = 0; i < neu.gruppen.length; ++i) {
            var n = neu.gruppen[i], idx = -1, j
            for (j = 0; j < g.length; ++j)
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
                if (wo === "hinten") g[idx].spaeter = n.spaeter
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
            l.push({ typ: "kopf", text: g.titel })
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
        if (offen.length === 0)
            return
        var o = W.kopie(offen)
        var url = o.shift()
        offen = o
        mehr.senden("routen_url", { url: url })
    }

    function ersteOeffiId() {
        for (var i = 0; i < gruppen.length; ++i)
            if (gruppen[i].schluessel === "oeffi" && gruppen[i].routen.length > 0) return gruppen[i].routen[0].id
        return ""
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
        onFertig: { seite.einfuegen(daten, ""); seite.naechsteOffene() }
        onFehler: { fenster.meldung(W.fehlerText(text)); seite.naechsteOffene() }
    }
    Anfrage {
        id: blaettern
        property string wo: ""
        onFertig: {
            // Die Eintraege sind verschieden hoch: nach "Frueher" die bisher
            // erste Oeffi-Route oben halten, nach "Spaeter" bleibt alles stehen.
            var vorher = liste.contentY, erste = seite.ersteOeffiId()
            seite.einfuegen(daten, wo)
            if (wo === "vorne" && erste !== "") {
                var l = liste.model
                for (var i = 0; i < l.length; ++i)
                    if (l[i].typ === "route" && l[i].r.id === erste) {
                        liste.positionViewAtIndex(Math.max(0, i - 1), ListView.Beginning)
                        break
                    }
            } else {
                liste.contentY = vorher
            }
        }
        onFehler: fenster.meldung(W.fehlerText(text))
    }

    SilicaListView {
        id: liste
        anchors.fill: parent

        PullDownMenu {
            busy: haupt.laeuft || mehr.laeuft || blaettern.laeuft
            MenuItem {
                text: "Rückfahrt"
                onClicked: {
                    var v = seite.von
                    seite.von = seite.nach
                    seite.nach = v
                    seite.laden()
                }
            }
            MenuItem { text: "Neu laden"; onClicked: seite.laden() }
        }

        header: PageHeader {
            title: W.ortName(seite.von) + " → " + W.ortName(seite.nach)
            description: W.zeitAnzeige(seite.wann)
        }

        model: seite.eintraege()
        delegate: Item {
            id: zeile
            readonly property bool istRoute: modelData.typ === "route"
            readonly property var r: istRoute ? modelData.r : null
            readonly property bool oeffi: istRoute && r.gruppe === "oeffi"
            width: liste.width
            height: modelData.typ === "kopf" ? seite.hKopf : (modelData.typ === "knopf" ? seite.hKnopf : knopf.height)

            SectionHeader {
                visible: modelData.typ === "kopf"
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.typ === "kopf" ? modelData.text : ""
            }
            Button {
                visible: modelData.typ === "knopf"
                anchors.centerIn: parent
                text: modelData.typ === "knopf" ? modelData.text : ""
                enabled: !blaettern.laeuft
                onClicked: {
                    blaettern.wo = modelData.was === "frueher" ? "vorne" : "hinten"
                    blaettern.senden("routen_url", { url: modelData.url })
                }
            }
            // Eine Route: Spalte mit Zeiten (oder Titel), Verspaetung, Linien,
            // Abfahrtsort -- die Hoehe ergibt sich aus dem Inhalt, damit bei
            // grossen Schriften nichts uebereinander liegt.
            BackgroundItem {
                id: knopf
                visible: zeile.istRoute
                width: parent.width
                height: zeile.istRoute ? spalte.height + 2 * Theme.paddingMedium : 0
                onClicked: {
                    fenster.letzteRoute = zeile.r
                    pageStack.push(Qt.resolvedUrl("RoutenSeite.qml"), { route: zeile.r })
                }

                Linie {
                    id: sinn
                    visible: zeile.istRoute && !zeile.oeffi
                    x: Theme.horizontalPageMargin
                    y: Theme.paddingMedium
                    groesse: Theme.iconSizeMedium
                    art: zeile.r ? zeile.r.art : "sonst"
                    farbe: zeile.r ? zeile.r.farbe : "#666666"
                }
                Column {
                    id: spalte
                    y: Theme.paddingMedium
                    anchors { left: zeile.oeffi ? parent.left : sinn.right; leftMargin: zeile.oeffi ? Theme.horizontalPageMargin : Theme.paddingMedium
                              right: parent.right; rightMargin: Theme.horizontalPageMargin }
                    spacing: Theme.paddingSmall / 2

                    Item {
                        width: parent.width
                        height: hauptText.height
                        Label {
                            id: hauptText
                            anchors { left: parent.left; right: dauerText.left; rightMargin: Theme.paddingSmall }
                            font.pixelSize: zeile.oeffi ? Theme.fontSizeLarge : Theme.fontSizeMedium
                            truncationMode: TruncationMode.Fade
                            color: zeile.r && zeile.r.ausgefallen ? "#ff6666" : (knopf.highlighted ? Theme.highlightColor : Theme.primaryColor)
                            text: {
                                if (!zeile.r) return ""
                                if (zeile.oeffi)
                                    return zeile.r.ab.zeit + " – " + zeile.r.an.zeit + (zeile.r.an.tag !== "" ? " (" + zeile.r.an.tag + ")" : "")
                                return zeile.r.titel + (zeile.r.anbieter !== "" && zeile.r.anbieter !== zeile.r.titel ? " · " + zeile.r.anbieter : "")
                            }
                        }
                        Label {
                            id: dauerText
                            anchors { right: parent.right; baseline: hauptText.baseline }
                            text: zeile.r ? zeile.r.dauer : ""
                            color: knopf.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                    }
                    Label {
                        width: parent.width
                        visible: zeile.oeffi && text !== ""
                        font.pixelSize: Theme.fontSizeExtraSmall
                        text: {
                            if (!zeile.r) return ""
                            if (zeile.r.ausgefallen) return "Fällt aus"
                            var f = zeile.r.erste_fahrt
                            if (f && f.echtzeit && f.verspaetung > 0) return "ab " + f.live + " (+" + f.verspaetung + ")"
                            if (f && f.echtzeit) return "pünktlich"
                            return ""
                        }
                        color: zeile.r && (zeile.r.ausgefallen || (zeile.r.erste_fahrt && zeile.r.erste_fahrt.verspaetung > 0)) ? "#ff6666" : "#5cb85c"
                    }
                    Flow {
                        visible: zeile.oeffi
                        width: parent.width
                        spacing: Theme.paddingSmall
                        Repeater {
                            model: zeile.oeffi ? zeile.r.linien : []
                            Linie { art: modelData.art; text: modelData.text; farbe: modelData.farbe }
                        }
                        Label {
                            height: Theme.itemSizeExtraSmall * 0.55
                            verticalAlignment: Text.AlignVCenter
                            text: zeile.oeffi ? (zeile.r.umstiege === 1 ? "1 Umstieg" : zeile.r.umstiege + " Umstiege") : ""
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                        }
                    }
                    Label {
                        visible: !zeile.oeffi && text !== ""
                        width: parent.width
                        truncationMode: TruncationMode.Fade
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeSmall
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
                    Label {
                        width: parent.width
                        visible: text !== ""
                        truncationMode: TruncationMode.Fade
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        text: {
                            if (!zeile.r) return ""
                            if (zeile.oeffi) {
                                var f = zeile.r.erste_fahrt
                                return f ? "ab " + f.name + (f.gleis !== "" ? ", Gleis/Steig " + f.gleis : "") : ""
                            }
                            return zeile.r.meldungen.length > 0 ? zeile.r.meldungen[0].text : ""
                        }
                    }
                }
            }
        }

        footer: Column {
            width: liste.width
            spacing: Theme.paddingMedium
            Item { width: 1; height: Theme.paddingSmall }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: seite.fehler !== ""
                text: seite.fehler
                color: Theme.highlightColor
                wrapMode: Text.Wrap
            }
            Repeater {
                model: seite.gruppen.length > 0 ? seite.meldungen : []
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    text: (modelData.titel !== "" ? modelData.titel + ": " : "") + modelData.text
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.Wrap
                }
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: seite.offen.length > 0 && !mehr.laeuft && !haupt.laeuft
                text: "Rad, Auto, Sharing, Taxi laden"
                onClicked: seite.naechsteOffene()
            }
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Medium
                running: haupt.laeuft || mehr.laeuft
                visible: running
            }
            Item { width: 1; height: Theme.paddingLarge }
        }
        VerticalScrollDecorator { }
    }
}
