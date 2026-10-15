import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../wf.js" as W

// Zahlungsmittel des wegfinder-Kontos: Kreditkarte/Debitkarte, PayPal.
// Wie in der Android-App gehen 3-D Secure und die PayPal-Freigabe im
// Browser; die Seite fragt danach alle 5 s den Stand ab.
//
// auswahl: aus dem Kauf geoeffnet -- Antippen waehlt das Zahlungsmittel
// (Signal gewaehlt) und schliesst die Seite.
Page {
    id: seite
    property bool auswahl: false
    property string quelle: "profile"     // "flow/<id>" aus dem Kauf
    property var liste: []
    property string fehler: ""
    property var wartet: null              // Zahlungsmittel, dessen Freigabe aussteht
    signal gewaehlt(var zahlungsmittel)

    Component.onCompleted: laden.senden("zahlungsmittel", {})

    Anfrage { id: laden; onFertig: seite.liste = daten; onFehler: seite.fehler = W.fehlerText(text) }
    Anfrage {
        id: aendern
        onFertig: { seite.liste = daten; seite.fehler = "" }
        onFehler: seite.fehler = W.fehlerText(text)
    }
    Anfrage {
        id: anlegen
        onFertig: {
            seite.fehler = ""
            if (daten.redirect !== "") {
                seite.wartet = daten
                Qt.openUrlExternally(daten.redirect)
                abfrage.start()
            } else if (daten.freigabe !== "") {
                seite.wartet = daten
                Qt.openUrlExternally(daten.freigabe)
            } else {
                laden.senden("zahlungsmittel", {})
                fenster.meldung("Zahlungsmittel hinzugefügt.")
            }
        }
        onFehler: seite.fehler = W.fehlerText(text)
    }
    Anfrage {
        id: paypalFertig
        onFertig: { seite.wartet = daten; abfrage.start() }
        onFehler: seite.fehler = W.fehlerText(text)
    }
    Anfrage {
        id: stand
        onFertig: {
            if (daten.fehlgeschlagen) {
                abfrage.stop()
                seite.wartet = null
                seite.fehler = daten.hinweis !== "" ? daten.hinweis : "Die Freigabe ist gescheitert."
                laden.senden("zahlungsmittel", {})
            } else if (daten.fertig) {
                abfrage.stop()
                seite.wartet = null
                fenster.meldung("Zahlungsmittel bereit: " + daten.titel)
                laden.senden("zahlungsmittel", {})
            }
        }
    }
    Timer {
        id: abfrage
        interval: 5000
        repeat: true
        onTriggered: if (seite.wartet) stand.senden("zahlungsmittel_status", { id: seite.wartet.id })
    }

    // Karte eingeben. Die Daten gehen nur an mpay24 (ueber den Dienst) und
    // verschwinden mit dem Dialog.
    Component {
        id: karteDialog
        Dialog {
            id: dlg
            canAccept: nummer.text.replace(/[^0-9]/g, "").length >= 12 && ablauf.text.length >= 4 && cvc.text.length >= 3
            onAccepted: anlegen.senden("karte_anlegen", { nummer: nummer.text, ablauf: ablauf.text, cvc: cvc.text,
                                                         quelle: seite.quelle })
            Column {
                width: parent.width
                spacing: Theme.paddingSmall
                DialogHeader { acceptText: "Hinzufügen"; title: "Kredit- oder Debitkarte" }
                TextField {
                    id: nummer
                    width: parent.width
                    label: "Kartennummer"
                    placeholderText: "Kartennummer"
                    inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
                    EnterKey.onClicked: ablauf.focus = true
                    focus: true
                }
                TextField {
                    id: ablauf
                    width: parent.width
                    label: "Gültig bis (MM/JJ)"
                    placeholderText: "MM/JJ"
                    inputMethodHints: Qt.ImhPreferNumbers | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
                    EnterKey.onClicked: cvc.focus = true
                }
                PasswordField {
                    id: cvc
                    width: parent.width
                    label: "Prüfnummer (CVC)"
                    placeholderText: "CVC"
                    inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData
                    showEchoModeToggle: false
                    EnterKey.onClicked: if (dlg.canAccept) dlg.accept()
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: "Visa und Mastercard (auch Debit). Die Kartendaten gehen verschlüsselt direkt an den Zahlungsdienst "
                          + "mpay24 und werden auf dem Telefon nicht gespeichert. Verlangt die Bank eine Bestätigung "
                          + "(3-D Secure), öffnet sich danach der Browser."
                }
            }
        }
    }

    SilicaListView {
        id: ansicht
        anchors.fill: parent
        PullDownMenu {
            busy: laden.laeuft || anlegen.laeuft
            MenuItem {
                text: "PayPal hinzufügen"
                onClicked: anlegen.senden("paypal_anlegen", { quelle: seite.quelle })
            }
            MenuItem {
                text: "Karte hinzufügen"
                onClicked: pageStack.push(karteDialog)
            }
        }
        header: Column {
            width: ansicht.width
            PageHeader { title: seite.auswahl ? "Zahlungsmittel wählen" : "Zahlungsmittel" }

            // Freigabe im Browser laeuft
            Column {
                width: parent.width
                visible: !!seite.wartet
                spacing: Theme.paddingMedium
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                    text: seite.wartet && seite.wartet.typ === "paypal"
                          ? "Im Browser bei PayPal anmelden und wegfinder freigeben. Danach hier „Freigegeben“ tippen."
                          : "Im Browser die Karte bei deiner Bank bestätigen (3-D Secure). Die App merkt es von selbst."
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.paddingMedium
                    Button {
                        text: "Browser erneut öffnen"
                        onClicked: Qt.openUrlExternally(seite.wartet.redirect !== "" ? seite.wartet.redirect : seite.wartet.freigabe)
                    }
                    Button {
                        visible: !!seite.wartet && seite.wartet.typ === "paypal" && !abfrage.running
                        text: "Freigegeben"
                        onClicked: paypalFertig.senden("paypal_fertig", { id: seite.wartet.id })
                    }
                }
                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: BusyIndicatorSize.Medium
                    running: abfrage.running
                    visible: running
                }
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Medium
                running: anlegen.laeuft
                visible: running
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: seite.fehler !== ""
                text: seite.fehler
                wrapMode: Text.Wrap
                color: "#ff6666"
            }
        }

        model: seite.liste
        delegate: ListItem {
            id: eintrag
            contentHeight: Theme.itemSizeMedium
            menu: ContextMenu {
                MenuItem {
                    text: "Als Standard"
                    visible: !modelData.standard
                    onClicked: aendern.senden("zahlungsmittel_standard", { id: modelData.id })
                }
                MenuItem {
                    text: "Löschen"
                    onClicked: eintrag.remorseAction("Lösche " + modelData.titel, function() {
                        aendern.senden("zahlungsmittel_loeschen", { id: modelData.id })
                    })
                }
            }
            onClicked: {
                if (seite.auswahl && modelData.fertig) {
                    seite.gewaehlt(modelData)
                    pageStack.pop()
                }
            }
            Column {
                anchors { left: parent.left; right: parent.right; margins: Theme.horizontalPageMargin; verticalCenter: parent.verticalCenter }
                Label {
                    width: parent.width
                    text: modelData.titel + (modelData.standard ? "  ★" : "")
                    truncationMode: TruncationMode.Fade
                    color: eintrag.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: modelData.fehlgeschlagen ? "#ff6666" : Theme.secondaryColor
                    truncationMode: TruncationMode.Fade
                    text: W.verbinden([modelData.ablauf !== "" ? "gültig bis " + modelData.ablauf : "",
                                       modelData.fertig ? "" : (modelData.fehlgeschlagen ? "Freigabe gescheitert" : "Freigabe offen"),
                                       modelData.hinweis], " · ")
                }
            }
        }
        ViewPlaceholder {
            enabled: !laden.laeuft && seite.liste.length === 0 && !seite.wartet && !anlegen.laeuft
            text: "Noch kein Zahlungsmittel"
            hintText: "Im Zugmenü eine Karte oder PayPal hinzufügen."
        }
        VerticalScrollDecorator { }
    }
}
