import QtQuick 1.1
import com.nokia.meego 1.1
import "wf.js" as W

// Eine Verbindung im Einzelnen: je Abschnitt Abfahrt, Linie, Richtung,
// Zwischenhalte (aufklappbar), Hinweise des Anbieters, Ankunft. Ein Halt
// mit Kennung laesst sich antippen und zeigt dessen Abfahrten.
Page {
    id: seite
    property variant route: null
    property variant preis: null     // aus v3/offers, siehe ErgebnisSeite

    tools: ToolBarLayout {
        ToolIcon { iconId: "toolbar-back"; onClicked: pageStack.pop() }
        ToolIcon { iconSource: "bilder/karte.png"; onClicked: pageStack.push(Qt.resolvedUrl("KarteSeite.qml"), { route: seite.route }) }
    }

    function abfahrten(h) {
        if (h && h.id && h.id !== "")
            pageStack.push(Qt.resolvedUrl("AbfahrtenSeite.qml"), { station: h.id, name: h.name })
    }

    Kopf {
        id: kopf
        anchors.top: parent.top
        titel: seite.route ? seite.route.ab.zeit + " – " + seite.route.an.zeit + "  ·  " + seite.route.dauer : ""
        untertitel: seite.route ? (seite.route.gruppe === "oeffi"
                                   ? (seite.route.umstiege === 1 ? "1 Umstieg" : seite.route.umstiege + " Umstiege")
                                     + (seite.route.strecke !== "" ? " · " + seite.route.strecke : "")
                                   : seite.route.titel + (seite.route.untertitel !== "" ? " · " + seite.route.untertitel : ""))
                                : ""
    }

    Flickable {
        id: flick
        anchors { top: kopf.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: inhalt.height + 32
        clip: true

        Column {
            id: inhalt
            width: parent.width
            Item { width: 1; height: 12 }

            Repeater {
                model: seite.route ? seite.route.abschnitte : []
                Column {
                    id: abschnitt
                    property variant a: modelData
                    property bool fuss: a.art === "fuss"
                    property bool erster: index === 0
                    property bool letzter: seite.route && index === seite.route.abschnitte.length - 1
                    property bool offen: false
                    width: inhalt.width

                    // Abfahrt (bei Fusswegen nur am Anfang)
                    Halt {
                        visible: !abschnitt.fuss || abschnitt.erster
                        h: abschnitt.a.von
                        farbe: abschnitt.fuss ? "#8c8c8c" : abschnitt.a.farbe
                        fett: true
                        onClicked: seite.abfahrten(abschnitt.a.von)
                    }

                    // Mitte: Linie, Richtung, Dauer, Zwischenhalte
                    Item {
                        width: parent.width
                        height: mitte.height + 16
                        Rectangle {
                            x: 107
                            width: abschnitt.fuss ? 4 : 8
                            anchors { top: parent.top; bottom: parent.bottom }
                            color: abschnitt.fuss ? "#666666" : abschnitt.a.farbe
                            opacity: abschnitt.a.ausgefallen ? 0.4 : 1
                        }
                        Column {
                            id: mitte
                            y: 8
                            x: 130
                            width: parent.width - 146
                            spacing: 6
                            Row {
                                spacing: 10
                                visible: !abschnitt.fuss
                                Linie {
                                    art: abschnitt.a.art
                                    text: abschnitt.a.linie !== "" ? abschnitt.a.linie : abschnitt.a.bezeichnung
                                    farbe: abschnitt.a.farbe
                                    groesse: 32
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: mitte.width - 120
                                    text: abschnitt.a.richtung !== "" ? "→ " + abschnitt.a.richtung : ""
                                    color: "white"
                                    font.pixelSize: 22
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                color: abschnitt.a.ausgefallen ? "#ff6666" : "#8c8c8c"
                                font.pixelSize: 20
                                text: {
                                    var t = []
                                    if (abschnitt.fuss) t.push("Zu Fuß")
                                    else if (abschnitt.a.linie !== "" && abschnitt.a.bezeichnung !== "") t.push(abschnitt.a.bezeichnung)
                                    t.push(abschnitt.a.dauer)
                                    if (abschnitt.a.strecke !== "") t.push(abschnitt.a.strecke)
                                    if (abschnitt.a.halte.length > 0)
                                        t.push((abschnitt.a.halte.length + 1) + " Halte " + (abschnitt.offen ? "▴" : "▾"))
                                    if (abschnitt.a.ausgefallen) t.push("fällt aus")
                                    return t.join(" · ")
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    enabled: abschnitt.a.halte.length > 0
                                    onClicked: abschnitt.offen = !abschnitt.offen
                                }
                            }
                            Repeater {
                                model: abschnitt.offen ? abschnitt.a.halte : []
                                Text {
                                    width: mitte.width
                                    elide: Text.ElideRight
                                    color: modelData.ausgefallen ? "#ff6666" : "#b3b3b3"
                                    font.pixelSize: 20
                                    text: modelData.zeit + (modelData.live !== "" && modelData.live !== modelData.zeit ? " (" + modelData.live + ")" : "")
                                          + "  " + modelData.name
                                    MouseArea { anchors.fill: parent; onClicked: seite.abfahrten(modelData) }
                                }
                            }
                            Repeater {
                                model: abschnitt.a.infos
                                Text {
                                    width: mitte.width
                                    wrapMode: Text.WordWrap
                                    color: "#b3b3b3"
                                    font.pixelSize: 20
                                    text: modelData.label + (modelData.label !== "" && modelData.wert !== "" ? ": " : "") + modelData.wert
                                }
                            }
                        }
                    }

                    // Ankunft (bei Fusswegen nur am Ende)
                    Halt {
                        visible: !abschnitt.fuss || abschnitt.letzter
                        h: abschnitt.a.nach
                        farbe: abschnitt.fuss ? "#8c8c8c" : abschnitt.a.farbe
                        fett: abschnitt.letzter
                        onClicked: seite.abfahrten(abschnitt.a.nach)
                    }
                }
            }

            Item { width: 1; height: 16 }
            Ueberschrift {
                x: 16
                width: parent.width - 32
                text: "Preis"
                visible: !!seite.preis
            }
            Text {
                x: 16
                width: inhalt.width - 32
                visible: !!seite.preis
                wrapMode: Text.WordWrap
                color: "white"
                font.pixelSize: 26
                text: seite.preis ? seite.preis.text : ""
            }
            Text {
                x: 16
                width: inhalt.width - 32
                visible: !!seite.preis
                wrapMode: Text.WordWrap
                color: "#b3b3b3"
                font.pixelSize: 20
                text: seite.preis ? W.verbinden([seite.preis.geschaetzt ? "" : "Vollpreis ohne Ermäßigung.",
                                                 seite.preis.hinweis, seite.preis.co2], " ") : ""
            }
            Ueberschrift {
                x: 16
                width: parent.width - 32
                text: "Hinweise"
                visible: seite.route && seite.route.meldungen.length > 0
            }
            Repeater {
                model: seite.route ? seite.route.meldungen : []
                Text {
                    x: 16
                    width: inhalt.width - 32
                    wrapMode: Text.WordWrap
                    color: "white"
                    font.pixelSize: 22
                    text: (modelData.titel !== "" ? "<b>" + modelData.titel + "</b><br>" : "") + modelData.text
                }
            }
            Ueberschrift {
                x: 16
                width: parent.width - 32
                text: "Ausstattung"
                visible: seite.route && seite.route.ausstattung.length > 0
            }
            Text {
                x: 16
                width: inhalt.width - 32
                visible: seite.route && seite.route.ausstattung.length > 0
                wrapMode: Text.WordWrap
                color: "#b3b3b3"
                font.pixelSize: 20
                text: seite.route ? seite.route.ausstattung.join(" · ") : ""
            }
            Item { width: 1; height: 12 }
            Text {
                x: 16
                width: inhalt.width - 32
                wrapMode: Text.WordWrap
                color: "#666666"
                font.pixelSize: 18
                text: "Buchen und Bezahlen gibt es in dieser App nicht. Halt antippen: Abfahrten dort."
            }
        }
    }
    ScrollDecorator { flickableItem: flick }
}
