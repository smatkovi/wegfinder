import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../wf.js" as W

// Ein Ticket zum Vorzeigen: Barcode gross auf weissem Grund, Gueltigkeit,
// Strecke. Die Barcodes kommen fertig vom Server und liegen danach auf dem
// Telefon -- vorzeigen geht auch ohne Netz.
Page {
    id: seite
    property var ticket: null
    property var daten: null
    property string fehler: ""
    property int takt: 0
    allowedOrientations: Orientation.Portrait

    Component.onCompleted: if (ticket.details) laden.senden("ticket", { id: ticket.id })
    Anfrage {
        id: laden
        onFertig: seite.daten = daten
        onFehler: seite.fehler = W.fehlerText(text)
    }
    Anfrage {
        id: pdf
        onFertig: Qt.openUrlExternally("file://" + daten.datei)
        onFehler: fenster.meldung(W.fehlerText(text))
    }
    Timer { interval: 30000; repeat: true; running: Qt.application.active; onTriggered: seite.takt++ }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: spalte.height + Theme.paddingLarge

        PullDownMenu {
            busy: laden.laeuft || pdf.laeuft
            MenuItem {
                text: "PDF öffnen"
                visible: !!seite.ticket && seite.ticket.pdf
                onClicked: pdf.senden("ticket_pdf", { id: seite.ticket.id })
            }
            MenuItem {
                text: "Neu laden"
                visible: !!seite.ticket && seite.ticket.details
                onClicked: laden.senden("ticket", { id: seite.ticket.id })
            }
        }

        Column {
            id: spalte
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: seite.ticket ? (seite.ticket.name !== "" ? seite.ticket.name : "Ticket") : ""
                description: seite.daten && seite.daten.offline ? "Ohne Netz – gespeicherte Fassung" : (seite.ticket ? seite.ticket.preis : "")
            }

            Repeater {
                model: seite.daten ? seite.daten.eintraege : []
                Column {
                    width: spalte.width
                    spacing: Theme.paddingSmall
                    readonly property var g: { seite.takt; return W.gueltigkeit(modelData.von, modelData.bis) }
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        visible: text !== ""
                        text: modelData.titel
                        font.pixelSize: Theme.fontSizeLarge
                        color: Theme.highlightColor
                        wrapMode: Text.Wrap
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: modelData.bild !== ""
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        height: bild.paintedHeight + 2 * Theme.paddingLarge
                        color: "white"
                        radius: Theme.paddingSmall
                        Image {
                            id: bild
                            anchors.centerIn: parent
                            width: parent.width - 2 * Theme.paddingLarge
                            fillMode: Image.PreserveAspectFit
                            smooth: false          // Barcodes scharf, nicht weichgezeichnet
                            source: modelData.bild !== "" ? "file://" + modelData.bild : ""
                            sourceSize.width: width
                        }
                        Rectangle {
                            anchors.fill: parent
                            visible: modelData.abgelaufen || modelData.storniert
                            color: Theme.rgba("#000000", 0.6)
                            radius: parent.radius
                            Label {
                                anchors.centerIn: parent
                                width: parent.width - 2 * Theme.paddingLarge
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                text: modelData.storniert ? "Dieses Ticket wurde storniert." : "Dieses Ticket ist abgelaufen."
                                color: "white"
                            }
                        }
                    }
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        text: g.text
                        color: W.gueltigFarbe(g.farbe)
                        font.pixelSize: Theme.fontSizeMedium
                    }
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        visible: text !== ""
                        text: modelData.route
                        wrapMode: Text.Wrap
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    Item { width: 1; height: Theme.paddingLarge }
                }
            }

            // Ohne Detailansicht (oder solange sie laedt): die Angaben der Liste
            Column {
                width: parent.width
                visible: !seite.daten
                DetailItem {
                    label: "Gültigkeit"
                    value: { seite.takt; return seite.ticket ? W.gueltigkeit(seite.ticket.von, seite.ticket.bis).text : "" }
                }
                Repeater {
                    model: seite.ticket ? seite.ticket.felder : []
                    Label {
                        x: Theme.horizontalPageMargin
                        width: spalte.width - 2 * Theme.horizontalPageMargin
                        text: modelData
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: spalte.width - 2 * Theme.horizontalPageMargin
                    visible: !!seite.ticket && !seite.ticket.details && seite.ticket.pdf
                    text: "Dieses Ticket gibt es nur als PDF – im Zugmenü öffnen."
                    wrapMode: Text.Wrap
                    color: Theme.secondaryHighlightColor
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: spalte.width - 2 * Theme.horizontalPageMargin
                    visible: seite.fehler !== ""
                    text: seite.fehler
                    wrapMode: Text.Wrap
                    color: "#ff6666"
                }
            }
        }
        VerticalScrollDecorator { }
    }
}
