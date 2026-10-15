import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../wf.js" as W

// Ticket kaufen. Der Ablauf kommt vom Server (v3/flow, siehe
// dienst/src/kauf.rs): Angebot waehlen, offene Schritte erledigen (Konto,
// E-Mail bestaetigen, Name, Zahlungsmittel), dann "Kostenpflichtig buchen"
// -- immer erst nach einem Dialog mit Ticket, Preis und Zahlungsmittel.
Page {
    id: seite
    property var startdaten: null      // aus dem Angebot (preis.kauf)
    property string titel: ""
    property var f: null               // Ansicht des Flows vom Dienst
    property string fehler: ""
    readonly property var su: f && f.summary ? f.summary : null
    readonly property bool offen: !!su && su.voraussetzungen.length > 0
    readonly property bool bereit: !!su && !offen && su.weiter_aktiv && !!su.zahlung
    property bool gekauft: false

    function hat(v) { return !!su && su.voraussetzungen.indexOf(v) >= 0 }

    Component.onCompleted: anfrage.senden("kauf_start", { daten: startdaten })
    // Ohne Kauf verlassen: den angefangenen Kauf beim Server verwerfen.
    Component.onDestruction: if (f && f.bildschirm === "summary") Dienst.anfrage("kauf_abbrechen", JSON.stringify({ id: f.id }))

    Anfrage {
        id: anfrage
        onFertig: {
            seite.fehler = ""
            seite.f = daten
            if (daten.bildschirm === "pending") stand.start()
            else stand.stop()
            if (daten.bildschirm === "success") {
                seite.gekauft = true
                fenster.meldung("Ticket gekauft.")
            }
        }
        onFehler: seite.fehler = W.fehlerText(text)
    }
    Anfrage { id: konto; onFertig: if (seite.f) anfrage.senden("kauf_abgleichen", { id: seite.f.id }); onFehler: seite.fehler = W.fehlerText(text) }
    Anfrage { id: codeSenden; onFertig: fenster.meldung("Code ist unterwegs."); onFehler: seite.fehler = W.fehlerText(text) }
    Timer {
        id: stand
        interval: 2000
        repeat: true
        onTriggered: if (!anfrage.laeuft && seite.f) anfrage.senden("kauf_stand", { id: seite.f.id })
    }

    function anmelden() {
        var p = pageStack.push(Qt.resolvedUrl("KontoSeite.qml"))
        p.angemeldet.connect(function(neu) {
            pageStack.pop(seite)
            // Neues Konto: der Kauf bleibt gueltig. Bestehendes Konto: wie die
            // App einen neuen Kauf mit denselben Startdaten beginnen.
            anfrage.senden(neu ? "kauf_abgleichen" : "kauf_neu_starten", { id: seite.f.id })
        })
    }
    function zahlungWaehlen() {
        var p = pageStack.push(Qt.resolvedUrl("ZahlungSeite.qml"), { auswahl: true, quelle: "flow/" + seite.f.id })
        p.gewaehlt.connect(function(z) {
            anfrage.senden("kauf_zahlung", { id: seite.f.id, zahlungsmittel: z })
        })
    }

    Component {
        id: bestaetigung
        Dialog {
            onAccepted: anfrage.senden("kauf_buchen", { id: seite.f.id, bestaetigt: true, preis: seite.su.preis })
            Column {
                width: parent.width
                spacing: Theme.paddingLarge
                DialogHeader { acceptText: "Kostenpflichtig buchen"; cancelText: "Zurück" }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.highlightColor
                    text: {
                        var a = ""
                        for (var i = 0; i < seite.su.angebote.length; ++i)
                            if (seite.su.angebote[i].gewaehlt) a = seite.su.angebote[i].name
                        return a
                    }
                }
                DetailItem { label: "Preis"; value: seite.su.preis }
                DetailItem { label: "Strecke"; value: seite.su.route.von + " → " + seite.su.route.nach }
                DetailItem { label: "Abfahrt"; value: seite.su.route.datum + " " + seite.su.route.ab }
                DetailItem { label: "Bezahlt mit"; value: seite.su.zahlung ? seite.su.zahlung.titel : "" }
                DetailItem { label: "Ticket an"; value: seite.su.email; visible: seite.su.email !== "" }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    text: "Mit „Kostenpflichtig buchen“ wird das Ticket gekauft und vom Zahlungsmittel abgebucht. "
                          + seite.su.meldungen.join(" ")
                }
            }
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: spalte.height + Theme.paddingLarge

        PullDownMenu {
            busy: anfrage.laeuft
            visible: !!seite.f && seite.f.bildschirm === "summary"
            MenuItem { text: "Neu laden"; onClicked: anfrage.senden("kauf_laden", { id: seite.f.id }) }
        }

        Column {
            id: spalte
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: seite.gekauft ? "Gekauft" : "Ticket kaufen"
                description: seite.su ? seite.su.route.von + " → " + seite.su.route.nach + " · " + seite.su.route.ab : seite.titel
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Large
                running: !seite.f && anfrage.laeuft
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

            // ---------------- Uebersicht ----------------
            Column {
                width: parent.width
                visible: !!seite.su
                spacing: Theme.paddingSmall

                SectionHeader { text: "Ticket" }
                Repeater {
                    model: seite.su ? seite.su.angebote : []
                    BackgroundItem {
                        id: angebot
                        width: parent.width
                        height: aSpalte.height + 2 * Theme.paddingMedium
                        highlighted: down || modelData.gewaehlt
                        onClicked: if (!modelData.gewaehlt) anfrage.senden("kauf_angebot", { id: seite.f.id, angebot: modelData.id })
                        Column {
                            id: aSpalte
                            x: Theme.horizontalPageMargin
                            y: Theme.paddingMedium
                            width: parent.width - 2 * Theme.horizontalPageMargin
                            Item {
                                width: parent.width
                                height: aName.height
                                Label {
                                    id: aName
                                    anchors { left: parent.left; right: aPreis.left; rightMargin: Theme.paddingMedium }
                                    text: (modelData.gewaehlt ? "● " : "○ ") + modelData.name
                                    wrapMode: Text.Wrap
                                    color: modelData.gewaehlt ? Theme.highlightColor : Theme.primaryColor
                                }
                                Label {
                                    id: aPreis
                                    anchors.right: parent.right
                                    text: modelData.preis
                                    color: modelData.gewaehlt ? Theme.highlightColor : Theme.primaryColor
                                }
                            }
                            Label {
                                width: parent.width
                                visible: text !== ""
                                text: modelData.merkmale.join(" · ")
                                wrapMode: Text.Wrap
                                font.pixelSize: Theme.fontSizeExtraSmall
                                color: Theme.secondaryColor
                            }
                        }
                    }
                }
                Repeater {
                    model: seite.su ? seite.su.meldungen : []
                    Label {
                        x: Theme.horizontalPageMargin
                        width: spalte.width - 2 * Theme.horizontalPageMargin
                        text: modelData
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryHighlightColor
                    }
                }

                // --- offene Schritte ---
                SectionHeader { text: "Noch zu erledigen"; visible: seite.offen }
                ButtonLayout {
                    visible: seite.hat("registration")
                    Button { text: "Anmelden oder Konto anlegen"; onClicked: seite.anmelden() }
                }
                Column {
                    width: parent.width
                    visible: seite.hat("verify_email") && !seite.hat("registration")
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        text: "E-Mail bestätigen: den Code aus der E-Mail von wegfinder eingeben."
                    }
                    TextField {
                        id: code
                        width: parent.width
                        label: "Code"
                        placeholderText: "Code aus der E-Mail"
                        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    }
                    ButtonLayout {
                        Button { text: "Bestätigen"; enabled: code.text.trim() !== ""; onClicked: konto.senden("email_code", { code: code.text.trim() }) }
                        Button { text: "Code erneut senden"; onClicked: codeSenden.senden("email_code_senden", {}) }
                    }
                }
                Column {
                    width: parent.width
                    visible: seite.hat("name") && !seite.hat("registration")
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        text: "Name (steht auf dem Ticket):"
                    }
                    TextField { id: vorname; width: parent.width; label: "Vorname"; placeholderText: "Vorname" }
                    TextField { id: nachname; width: parent.width; label: "Nachname"; placeholderText: "Nachname" }
                    ButtonLayout {
                        Button {
                            text: "Speichern"
                            enabled: vorname.text.trim() !== "" && nachname.text.trim() !== ""
                            onClicked: anfrage.senden("kauf_name", { id: seite.f.id, vorname: vorname.text.trim(), nachname: nachname.text.trim() })
                        }
                    }
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    visible: seite.hat("email") && !seite.hat("registration")
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeSmall
                    text: "Im Konto fehlt die E-Mail-Adresse."
                }

                // --- Zahlung ---
                SectionHeader { text: "Bezahlen mit"; visible: !seite.hat("registration") }
                BackgroundItem {
                    visible: !seite.hat("registration")
                    width: parent.width
                    height: Theme.itemSizeSmall
                    onClicked: seite.zahlungWaehlen()
                    Label {
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        truncationMode: TruncationMode.Fade
                        text: seite.su && seite.su.zahlung ? seite.su.zahlung.titel + "  (ändern)" : "Zahlungsmittel wählen …"
                        color: seite.su && seite.su.zahlung ? Theme.primaryColor : Theme.highlightColor
                    }
                }

                // --- Bestaetigungen des Anbieters ---
                Repeater {
                    model: seite.su ? seite.su.bestaetigungen : []
                    TextSwitch {
                        text: modelData.text
                        checked: modelData.bestaetigt
                        automaticCheck: false
                        onClicked: anfrage.senden("kauf_bestaetigen", { id: seite.f.id, schluessel: modelData.schluessel, wert: !checked })
                    }
                }

                DetailItem { label: "Ticket per E-Mail an"; value: seite.su ? seite.su.email : ""; visible: !!seite.su && seite.su.email !== "" }
                Repeater {
                    model: seite.su ? seite.su.reisende : []
                    DetailItem { label: "Reisende/r"; value: W.verbinden([modelData.vorname, modelData.nachname], " ") }
                }

                Item { width: 1; height: Theme.paddingLarge }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    preferredWidth: Theme.buttonWidthLarge
                    text: (seite.su ? seite.su.weiter : "") + (seite.su && seite.su.preis !== "" ? " · " + seite.su.preis : "")
                    enabled: seite.bereit && !anfrage.laeuft
                    onClicked: pageStack.push(bestaetigung)
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    visible: text !== ""
                    text: seite.su ? W.verbinden([seite.su.weiter_warnung, seite.su.hinweis], "\n") : ""
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                }
            }

            // ---------------- Warten ----------------
            Column {
                width: parent.width
                visible: !!seite.f && seite.f.bildschirm === "pending"
                spacing: Theme.paddingLarge
                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: BusyIndicatorSize.Large
                    running: parent.visible && seite.f.pending.fehler === ""
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    text: seite.f && seite.f.pending ? (seite.f.pending.fehler !== "" ? seite.f.pending.fehler
                                                        : (seite.f.pending.text !== "" ? seite.f.pending.text : "Ticket wird ausgestellt …")) : ""
                    color: seite.f && seite.f.pending && seite.f.pending.fehler !== "" ? "#ff6666" : Theme.highlightColor
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    visible: !!seite.f && !!seite.f.pending && seite.f.pending.bestellnummer !== ""
                    text: seite.f && seite.f.pending ? "Bestellnummer: " + seite.f.pending.bestellnummer : ""
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.secondaryColor
                }
                ButtonLayout {
                    Button {
                        visible: !!seite.f && !!seite.f.pending && seite.f.pending.fehler !== ""
                        text: "Erneut versuchen"
                        onClicked: anfrage.senden("kauf_wiederholen", { id: seite.f.id })
                    }
                }
            }

            // ---------------- Fertig ----------------
            Column {
                width: parent.width
                visible: !!seite.f && seite.f.bildschirm === "success"
                spacing: Theme.paddingLarge
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.highlightColor
                    text: "Das Ticket ist gekauft."
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    visible: text !== ""
                    wrapMode: Text.Wrap
                    text: seite.f && seite.f.success ? W.verbinden([seite.f.success.text, seite.f.success.warnung], "\n") : ""
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Meine Tickets"
                    onClicked: pageStack.replace(Qt.resolvedUrl("TicketsSeite.qml"))
                }
            }

            // ---------------- Fehler ----------------
            Column {
                width: parent.width
                visible: !!seite.f && seite.f.bildschirm === "error"
                spacing: Theme.paddingMedium
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeLarge
                    color: "#ff6666"
                    text: seite.f && seite.f.error ? seite.f.error.titel : ""
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    text: seite.f && seite.f.error ? seite.f.error.text : ""
                }
            }
        }
        VerticalScrollDecorator { }
    }
}
