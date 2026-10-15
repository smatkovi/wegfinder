import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../wf.js" as W

// Eine Verbindung im Einzelnen: je Abschnitt Abfahrt, Linie, Richtung,
// Zwischenhalte (aufklappbar), Hinweise, Ankunft. Halte mit Kennung lassen
// sich antippen und zeigen deren Abfahrten.
Page {
    id: seite
    property var route: null

    function abfahrten(h) {
        if (h && h.id && h.id !== "")
            pageStack.push(Qt.resolvedUrl("AbfahrtenSeite.qml"), { station: h.id, name: h.name })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: inhalt.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: "Ziel in Pure Maps"
                visible: Karten.pureMapsDa && !!seite.route
                onClicked: Karten.zeigeOrt(seite.route.an.name, seite.route.an.lat, seite.route.an.lon)
            }
            MenuItem { text: "Karte"; onClicked: pageStack.push(Qt.resolvedUrl("KarteSeite.qml"), { route: seite.route }) }
        }

        Column {
            id: inhalt
            width: parent.width

            PageHeader {
                title: seite.route ? seite.route.ab.zeit + " – " + seite.route.an.zeit + "  ·  " + seite.route.dauer : ""
                description: seite.route ? (seite.route.gruppe === "oeffi"
                                            ? (seite.route.umstiege === 1 ? "1 Umstieg" : seite.route.umstiege + " Umstiege")
                                              + (seite.route.strecke !== "" ? " · " + seite.route.strecke : "")
                                            : seite.route.titel + (seite.route.untertitel !== "" ? " · " + seite.route.untertitel : ""))
                                         : ""
            }

            Repeater {
                model: seite.route ? seite.route.abschnitte : []
                Column {
                    id: abschnitt
                    readonly property var a: modelData
                    readonly property bool fuss: a.art === "fuss"
                    readonly property bool erster: index === 0
                    readonly property bool letzter: !!seite.route && index === seite.route.abschnitte.length - 1
                    property bool offen: false
                    width: inhalt.width

                    Halt {
                        id: abHalt
                        visible: !abschnitt.fuss || abschnitt.erster
                        h: abschnitt.a.von
                        farbe: abschnitt.fuss ? "#8c8c8c" : abschnitt.a.farbe
                        fett: true
                        onClicked: seite.abfahrten(abschnitt.a.von)
                    }

                    Item {
                        width: parent.width
                        height: mitte.height + Theme.paddingMedium * 2
                        Rectangle {
                            x: abHalt.linieX - width / 2
                            width: abschnitt.fuss ? Theme.paddingSmall / 1.5 : Theme.paddingSmall * 1.5
                            anchors { top: parent.top; bottom: parent.bottom }
                            color: abschnitt.fuss ? "#808080" : abschnitt.a.farbe
                            opacity: abschnitt.a.ausgefallen ? 0.4 : 1
                        }
                        Column {
                            id: mitte
                            y: Theme.paddingMedium
                            x: abHalt.linieX + Theme.paddingLarge
                            width: parent.width - x - Theme.horizontalPageMargin
                            spacing: Theme.paddingSmall
                            Row {
                                spacing: Theme.paddingMedium
                                visible: !abschnitt.fuss
                                Linie {
                                    id: marke
                                    art: abschnitt.a.art
                                    text: abschnitt.a.linie !== "" ? abschnitt.a.linie : abschnitt.a.bezeichnung
                                    farbe: abschnitt.a.farbe
                                }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: mitte.width - marke.width - Theme.paddingMedium
                                    text: abschnitt.a.richtung !== "" ? "→ " + abschnitt.a.richtung : ""
                                    truncationMode: TruncationMode.Fade
                                }
                            }
                            Label {
                                width: parent.width
                                wrapMode: Text.Wrap
                                color: abschnitt.a.ausgefallen ? "#ff6666" : Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeSmall
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
                                    anchors.margins: -Theme.paddingMedium
                                    enabled: abschnitt.a.halte.length > 0
                                    onClicked: abschnitt.offen = !abschnitt.offen
                                }
                            }
                            Repeater {
                                model: abschnitt.offen ? abschnitt.a.halte : []
                                BackgroundItem {
                                    width: mitte.width
                                    height: Theme.itemSizeExtraSmall * 0.8
                                    onClicked: seite.abfahrten(modelData)
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width
                                        truncationMode: TruncationMode.Fade
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: modelData.ausgefallen ? "#ff6666" : Theme.secondaryColor
                                        text: modelData.zeit + (modelData.live !== "" && modelData.live !== modelData.zeit ? " (" + modelData.live + ")" : "")
                                              + "  " + modelData.name
                                    }
                                }
                            }
                            Repeater {
                                model: abschnitt.a.infos
                                Label {
                                    width: mitte.width
                                    wrapMode: Text.Wrap
                                    color: Theme.secondaryColor
                                    font.pixelSize: Theme.fontSizeSmall
                                    text: modelData.label + (modelData.label !== "" && modelData.wert !== "" ? ": " : "") + modelData.wert
                                }
                            }
                        }
                    }

                    Halt {
                        visible: !abschnitt.fuss || abschnitt.letzter
                        h: abschnitt.a.nach
                        farbe: abschnitt.fuss ? "#8c8c8c" : abschnitt.a.farbe
                        fett: abschnitt.letzter
                        onClicked: seite.abfahrten(abschnitt.a.nach)
                    }
                }
            }

            SectionHeader { text: "Hinweise"; visible: !!seite.route && seite.route.meldungen.length > 0 }
            Repeater {
                model: seite.route ? seite.route.meldungen : []
                Label {
                    x: Theme.horizontalPageMargin
                    width: inhalt.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    text: (modelData.titel !== "" ? "<b>" + modelData.titel + "</b><br>" : "") + modelData.text
                }
            }
            SectionHeader { text: "Ausstattung"; visible: !!seite.route && seite.route.ausstattung.length > 0 }
            Label {
                x: Theme.horizontalPageMargin
                width: inhalt.width - 2 * Theme.horizontalPageMargin
                visible: !!seite.route && seite.route.ausstattung.length > 0
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: seite.route ? seite.route.ausstattung.join(" · ") : ""
            }
            Item { width: 1; height: Theme.paddingLarge }
            Label {
                x: Theme.horizontalPageMargin
                width: inhalt.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: "Buchen und Bezahlen gibt es in dieser App nicht. Halt antippen: Abfahrten dort."
            }
        }
        VerticalScrollDecorator { }
    }
}
