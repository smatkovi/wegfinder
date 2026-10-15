# wegfinder für Sailfish OS und MeeGo Harmattan

Routen in Österreich mit Öffis, Rad, Auto, Sharing und Taxi, Abfahrten mit
Echtzeit und Verkehrsmittel in der Nähe – auf Sailfish-Telefonen (armv7hl,
aarch64) und auf dem Nokia N9/N950. Ein **inoffizieller** Client, nicht von
der iMobility GmbH oder den ÖBB.

**Ohne Buchen und Bezahlen**: keine Tickets, keine Zahlungsmittel, kein
Konto. Was die Android-App zum Buchen anbietet (Taxi, Scooter, Mietwagen),
erscheint hier nur als Möglichkeit mit Dauer, Preisangabe und Ladestand.

## Was es kann

* **Route planen**: Von/Nach mit Ortssuche (Haltestellen, Adressen, Orte),
  „Mein Standort“, Abfahrt oder Ankunft zu einer Zeit, Rückfahrt.
* **Ergebnisse** wie in der App gruppiert: Öffentlich (mit Früher/Später),
  Selbst unterwegs (Auto, Fahrrad, zu Fuß), Sharing & Taxi, weitere
  Angebote (Bikesharing, Taxistandplatz).
* **Verbindung im Einzelnen**: Abschnitte mit Linie, Richtung, Gleis/Steig,
  Echtzeit, Ausfällen, aufklappbaren Zwischenhalten, Hinweisen der Anbieter
  (Preis, Ladestand, freie Räder) und Ausstattung.
* **Abfahrten** jeder Haltestelle (jeder Halt einer Route ist antippbar) und
  der **Verlauf einer Fahrt** mit aktuellem Halt.
* **In der Nähe**: Karte mit Haltestellen, Leihrädern, E-Scootern,
  Carsharing, Taxi und Parken, Filter wie in der App.
* **Karte**: eigene Schiebekarte mit OpenStreetMap-Kacheln (ohne
  Kartenbibliothek, nach dem Muster von Fahrplan AT), Linien je
  Verkehrsmittel in deren Farbe. Unter Sailfish lassen sich Ziel und
  Fußweg an Pure Maps übergeben (wie in Fahrplan AT).
* **Favoriten** und zuletzt gesuchte Verbindungen, nur auf dem Telefon.

## Sparsam im 2G-Netz

Das N9 hängt oft an EDGE/GPRS. Deshalb:

* Alles geht gzip-komprimiert über eine einzige, offen gehaltene
  TLS-Verbindung (eine Routensuche: 2 statt 15 KB, ein TLS-Handschlag statt
  einem je Anfrage).
* Die Anmeldung beim Server (anonym) wird gespeichert, nicht bei jedem Start
  neu ausgehandelt.
* Zuerst kommen nur die Öffis; Rad, Auto, Sharing und Taxi (vier weitere
  Anfragen) am N9 im Mobilfunknetz nur auf Knopfdruck (einstellbar).
* Die Ortssuche fragt erst, wenn eine Weile nicht getippt wurde.
* Kartenkacheln gehen nur einmal übers Netz (30 Tage auf dem Telefon), höchstens
  zwei gleichzeitig. Im Mobilfunknetz am N9 „sparsam“: eine Zoomstufe tiefer,
  doppelt so groß – ein Viertel der Daten. Oder ganz ohne Hintergrund; die
  Linien und Punkte kommen trotzdem sofort.
* Abfahrtstafeln (vom Server bis 230 KB, gezippt 20 KB) gelten 30 s und
  werden nur auf Wunsch neu geladen; Umgebung im Mobilfunknetz nur auf
  „Hier suchen“.
* Der Dienst gibt der Oberfläche nur das Nötige weiter: aus 230 KB
  Abfahrten werden 10 KB, das QML am N9 hat wenig zu zerlegen.

## Aufbau

    ┌───────────────────────────────┐
    │ Oberfläche                    │  N9: Qt 4.7, QML 1, Harmattan-Komponenten
    │                               │  SFOS: Qt 5.6, Silica
    └──────────────┬────────────────┘
                   │ stdin/stdout, eine Zeile je Anfrage (meego/src/Dienst.h)
    ┌──────────────┴────────────────┐
    │ wf-dienst (Rust, statisch)    │  api.i-mobility.at, anonyme Sitzung,
    │                               │  Kachel-Zwischenspeicher auf 127.0.0.1
    └───────────────────────────────┘

* **wf-dienst** (`dienst/`): derselbe Rust-Dienst auf allen drei
  Architekturen, statisch gegen musl, eigenes OpenSSL und eingebettete
  Mozilla-Wurzeln (das TLS des N9 ist zu alt). Er formt die Antworten des
  Servers in kleine, fertig beschriftete Objekte um (Uhrzeiten in Wiener
  Zeit, Verspätung, Farben, ausgedünnte Linien). Befehle in [api.md](api.md).
* **Kacheln**: das Qt 4.7 des N9 erreicht tile.openstreetmap.org nicht
  (nur TLS 1.2); der Dienst liefert die Kacheln über `http://127.0.0.1:<port>`
  aus seinem Zwischenspeicher. Sailfish nutzt denselben Weg.
* **Oberflächen**: `meego/qml` (eine Datei je Seite) und `sailfish/qml`
  (Silica), gemeinsame Hilfen in `meego/qml/wf.js`.

## Warum kein Port der APK

Die Android-App (`ch.swift.willi`, 26.20.0) ist Kotlin mit Jetpack Compose,
Google Maps und Play Services, `minSdk 29` – nichts davon läuft auf
Harmattan oder brauchbar unter Sailfish. Was sie anspricht, ist eine
schlichte REST-Schnittstelle mit anonymer OAuth-Sitzung; die übernimmt
dieser Client. Abgelesen aus der APK (jadx) und am echten Server geprüft,
siehe [api.md](api.md).

## Symbol

Das Startsymbol ist das Logo der Android-App in der Form der
Harmattan-Symbole (Superellipse |x|^2,8 + |y|^2,8 = 1). Es liegt nicht im
Repo: `icons/make-icons.py` holt es beim Bauen aus der eigenen APK
(`~/Downloads/wegfinder_26.20.0_APKPure.apk` oder `WF_APK=…`, braucht
apktool und rsvg-convert). Ohne APK gibt es ein eigenes Motiv. Das Logo
gehört der iMobility GmbH.

## Bauen

    tools/toolchain.sh              # Rust + musl-Toolchains unter /tmp/rust
    tools/build-meego.sh            # N9: Dienst und Oberfläche
    meego/build-deb.sh              # -> build/wegfinder_<version>_armel.deb
    tools/build-sailfish.sh         # -> build/wegfinder-<version>-1.{armv7hl,aarch64}.rpm

Das N9 baut mit MADDEs GCC 4.4.1 gegen den Harmattan-Sysroot (QtSDK),
Sailfish mit `mb2` in der Platform-SDK-Chroot gegen SailfishOS 5.1.0.11.

## Probeläufe ohne Telefon

* `python3 tools/dienst-probe.py <wf-dienst>` – spielt alle Befehle gegen den
  echten Server durch (Suche, Routen samt Sharing, Karte, Abfahrten,
  Fahrtverlauf, Umgebung, Kachel).
* `tools/probe.sh 'js:…' warte:… bild:/tmp/a.png` – zeichnet die
  N9-Oberfläche mit Qt 4.8 aus dem QtSDK auf einem Dummy-X-Server.
* `tools/sfos-probe.sh 'js:…' warte:…` – erzeugt alle Sailfish-Seiten in der
  echten Silica-Laufzeit des SDK-Ziels unter qemu und zeigt jede
  QML-Warnung.

## Installieren

* **N9/N950:** `dpkg -i wegfinder_0.1.0_armel.deb` (als root bzw. `devel-su`).
* **Sailfish (ab 5.0):** `devel-su pkcon install-local wegfinder-0.1.0-1.aarch64.rpm`
  (bzw. armv7hl). Gebaut gegen SailfishOS 5.1.0.11.

Ablage: `~/.config/wegfinder` (Sitzung, Einstellungen), `~/.local/share/wegfinder`
(Favoriten, Verlauf), `~/.cache/wegfinder` (Kacheln, Protokoll `dienst.log`).

## Lizenz

GPLv3 (`COPYING`).

* `dienst/certs/cacert.pem`: Mozilla-CA-Bündel von curl.se, MPL 2.0.
* Karte: © OpenStreetMap-Mitwirkende (ODbL), Kacheln von tile.openstreetmap.org.
* Sinnbilder der Verkehrsmittel: eigene, teils aus Fahrplan AT.
* Linienfarben und Namen der Verkehrsmittel (`dienst/src/arten.rs`) aus den
  Daten der Android-App.
