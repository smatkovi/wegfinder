import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../wf.js" as W

// wegfinder-Konto: Anmelden, Konto anlegen, Abmelden. Fuer Routen braucht
// es keins; zum Ticketkauf verlangt der Server eines. Das Kennwort geht nur
// an den Server und wird nirgends gespeichert -- auf dem Telefon bleibt nur
// das Erneuerungs-Token (0600, im Sandkasten-Ordner der App).
Page {
    id: seite
    property var konto: null
    property bool neu: false          // Konto anlegen statt anmelden
    property string fehler: ""
    signal angemeldet(bool neu)       // neu: Konto gerade angelegt

    Component.onCompleted: laden.senden("konto", {})

    Anfrage { id: laden; onFertig: seite.konto = daten; onFehler: seite.fehler = W.fehlerText(text) }
    Anfrage {
        id: senden
        onFertig: {
            seite.konto = daten
            seite.fehler = ""
            kennwort.text = ""
            if (daten.angemeldet) {
                fenster.meldung(seite.neu ? "Konto angelegt. Bitte die E-Mail bestätigen." : "Angemeldet.")
                seite.angemeldet(seite.neu)
            }
        }
        onFehler: seite.fehler = W.fehlerText(text)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: spalte.height + Theme.paddingLarge

        PullDownMenu {
            visible: !!seite.konto && seite.konto.angemeldet
            MenuItem {
                text: "Abmelden"
                onClicked: Remorse.popupAction(seite, "Abgemeldet", function() { senden.senden("abmelden", {}) })
            }
        }

        Column {
            id: spalte
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: "Konto"
                description: seite.konto && seite.konto.angemeldet ? seite.konto.email : "wegfinder-Konto für den Ticketkauf"
            }

            // --- angemeldet ---
            Column {
                width: parent.width
                visible: !!seite.konto && seite.konto.angemeldet
                spacing: Theme.paddingSmall
                DetailItem { label: "E-Mail"; value: (seite.konto && seite.konto.email) || "" }
                DetailItem { label: "Name"; value: seite.konto ? W.verbinden([seite.konto.vorname, seite.konto.nachname], " ") : ""; visible: value !== "" }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    visible: !!seite.konto && !!seite.konto.offline
                    text: "Ohne Netz – Angaben vom letzten Abruf."
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
                DetailItem {
                    label: "E-Mail bestätigt"
                    value: seite.konto && seite.konto.email_offen ? "noch nicht – Code aus der E-Mail beim Kauf eingeben" : "ja"
                }
            }

            // --- nicht angemeldet ---
            Column {
                width: parent.width
                visible: !!seite.konto && !seite.konto.angemeldet
                spacing: Theme.paddingMedium

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    text: seite.neu
                          ? "Neues wegfinder-Konto. Danach kommt eine E-Mail mit einem Bestätigungslink."
                          : "Mit dem wegfinder-Konto anmelden (dasselbe wie in der Android- oder iPhone-App). Konten über Google oder Apple gehen hier nicht."
                }
                TextField {
                    id: email
                    width: parent.width
                    label: "E-Mail"
                    placeholderText: "E-Mail"
                    inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                    EnterKey.iconSource: "image://theme/icon-m-enter-next"
                    EnterKey.onClicked: kennwort.focus = true
                }
                PasswordField {
                    id: kennwort
                    width: parent.width
                    label: "Kennwort"
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: knopf.clicked(null)
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    visible: seite.fehler !== ""
                    text: seite.fehler
                    wrapMode: Text.Wrap
                    color: "#ff6666"
                    font.pixelSize: Theme.fontSizeSmall
                }
                Button {
                    id: knopf
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: seite.neu ? "Konto anlegen" : "Anmelden"
                    enabled: email.text.indexOf("@") > 0 && kennwort.text.length >= 6 && !senden.laeuft
                    onClicked: senden.senden(seite.neu ? "registrieren" : "anmelden",
                                             { email: email.text.trim(), kennwort: kennwort.text })
                }
                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: BusyIndicatorSize.Medium
                    running: senden.laeuft
                    visible: running
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: seite.neu ? "Ich habe schon ein Konto" : "Neues Konto anlegen"
                    onClicked: { seite.neu = !seite.neu; seite.fehler = "" }
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !seite.neu
                    text: "Kennwort vergessen"
                    onClicked: Qt.openUrlExternally("https://password.wegfinder.at/password/forgot")
                }
            }
        }
        VerticalScrollDecorator { }
    }
}
