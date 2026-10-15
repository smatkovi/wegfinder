# Schnittstelle

## Server: api.i-mobility.at

Abgelesen aus der Android-App 26.20.0 (`ch.swift.willi`, jadx) und am
echten Server geprüft (15.10.2026). Retrofit-Annotationen sind verschleiert:
`ty4` = GET, `p78` = POST, `qo2` = DELETE, `l39` = Query, `ve8` = Path.

### Köpfe

Jede Anfrage trägt

    x-imob-identity: wegfinder/26.20.0;<plattform>/<version>
    x-imob-app-state: foreground
    x-imob-feature-overrides: accessible-image-urls
    Accept-Language: de
    Authorization: Bearer <token>        (außer bei der Anmeldung)

Der Server prüft den Namen vor dem ersten Schrägstrich (`wegfinder`, anderes
gibt 418) und leitet aus dem Teil nach dem Strichpunkt die Plattform ab
(ohne den Kopf scheitert `register_client` mit einem 500er: Spalte
„platform“ leer). Dieser Client meldet ehrlich `sailfish/<VERSION_ID>` bzw.
`meego/1.2` und einen eigenen User-Agent.

### Anonyme Sitzung

1. `POST v1/register_client` (leer) → `{client_id, client_secret}`
2. `POST v2/register` mit `{client_id, client_secret}` (JSON) →
   `{access_token, token_type: "Bearer", expires_in: 300, refresh_token, scope: "imob"}`
3. `POST v2/token` (Formular) mit `grant_type=refresh_token`, `client_id`,
   `client_secret`, `refresh_token`, `device`; Kopf
   `X-Imob-Originated-From: refreshing_token` → neues Token.

Bei 401/403 erneuert der Dienst einmal und wiederholt.

### Benutzte Endpunkte

| Endpunkt | Zweck |
|---|---|
| `GET v1/locations/search?query=&latitude=&longitude=` | Ortssuche, Liste von `{location: {id, name, type, coordinate, transport_types, description}}` |
| `GET v3/routes?start_location_id=…\|start_latitude=…&start_longitude=…&destination_…&departure=\|arrival=<ISO>&old_groups=false` | Routen; erste Antwort nur Gruppe `public`, die übrigen Gruppen als fertige Adressen in `unresolved_urls` |
| dieselben Adressen mit `transportation_groups=individual\|fast_directly_bookable\|slow_directly_bookable\|even_slower_directly_bookable\|not_bookable` | Auto/Rad/zu Fuß, Taxi/Scooter, Bikesharing … |
| `earlier_url`, `later_url` je Gruppe | früher/später (nur `public`) |
| `GET routing/api/v2/departures?stations=<id>&include_previous_stops=false` | Abfahrten (bis 250, keine Begrenzung möglich; auch für `proxy:`-Kennungen aus Routen) |
| `route_request_url` einer Abfahrt (`routing/api/v1/stops?journey_id=…`) | Fahrtverlauf mit `current_station_index` und Linienzug |
| `GET v7/radar?bbox=<lonW>,<latN>,<lonO>,<latS>&zoom=&filter=&location=<lon>,<lat>&map_width=&map_height=[&precision=]` | Umgebung: Gruppen mit `blips` (`station`, `partner`, `group`, `area_service`) |
| `GET v2/filters` | Filter der Umgebung |
| `offers_ref` einer Routenantwort (`v3/offers?ref=…&routes=…`) | Preise je Route: `{route_id, price: {amount (Cent), estimated}, messages, actions}`; anonym also Vollpreis, bei Taxi/Auto geschätzt |

Zeiten kommen teils mit `+02:00`, teils in UTC (`+00:00`, Auto/Rad).
Linienzüge sind Googles Encoded Polyline (5 Stellen).

### Konto (nur Sailfish, zum Ticketkauf)

* Anmelden: `POST v2/login` `{email, password, device, client_id, client_secret}`
  mit dem Client der anonymen Sitzung -> Token. Erneuern wie oben.
* Konto anlegen: `POST v2/register` `{email, password, client_id, client_secret}`
  mit dem anonymen Token -- die anonyme Sitzung wird zum Konto.
* `GET user/api/v1/me` -> `{data: {email, first_name, last_name, account_type,
  email_pending_validation, …}}`; `PATCH user/api/v1/me` für Name/E-Mail.
* E-Mail bestätigen: `POST user/api/v1/me/validate-confirmation {code}`,
  erneut senden: `POST user/api/v1/me/request-confirmation {email, revalidate: true}`.
* Abmelden: `POST v1/revoke` (Formular `token=<refresh>&client_id=android`).

### Ticketkauf (`v3/flow`)

* Startdaten: `actions[].flow.data` eines Angebots aus `v3/offers`.
* `POST v3/flow` -> 303 auf `/v3/flow/<id>`. Ein Flow hat genau einen
  Bildschirm: `summary`, `pending`, `success`, `error` (u. a.).
* `summary`: `item.offers[]` (id, name, price, selected, features),
  `prerequisites` (registration, email, verify_email, name, payment, discounts,
  push_notifications -- die letzten zwei überspringt die App), `payment.primary`,
  `passengers.default.people[]`, `confirmation{}`, `email`, `next_step`,
  `next_step_enabled`, `launch_data`.
* Jede Änderung: ganzen Flow an `POST v3/flow/{id}` (409: `GET v3/flow/{id}`).
  Angebot: `offers[*].selected`; Zahlungsmittel: `payment.primary = {id, type,
  brand, title, …}`; Name: `PATCH user/api/v1/me` und Reisende/r `id == "me"`.
* Buchen: ganzen Flow an `POST v3/flow/{id}/continue` -> `pending`, alle 2 s
  `GET v3/flow/{id}` bis `success {ticket_id, …}` oder `error`.
  `next_step_enabled` ist auch bei offenen Voraussetzungen `true`; gebucht
  wird erst, wenn keine mehr offen sind.
* Verwerfen: `DELETE v3/flow/{id}`.

### Zahlungsmittel

* `POST v2/payment_options {source: "profile"|"flow/<id>", set_default,
  set_fallback, payment_type: "credit_card"|"paypal"}` -> Kopf `Location`;
  bei Karten `credit_card.api_key`, bei PayPal `approve_url`.
* Karte: `POST https://mpay24.com/app/bin/tokenizer/api/v1/cc`, Kopf `Api-Key`,
  `{brand: VISA|MASTERCARD|UNKNOWN, identifier: <Kartennummer>, expiry: JJMM, cvc}`
  -> `{brand, identifier, expiry, redirect?: {title, initial, final}}`, dann
  `PATCH <Location> {"credit_card": <Antwort>}`. Mit `redirect.initial`:
  3-D Secure im Browser, `GET v2/payment_options/{id}` alle 5 s bis
  `initialized && !verification_failed`.
* PayPal: `approve_url` im Browser, dann `PATCH v2/payment_options/{id}
  {"payment_type": "paypal"}` und abfragen.
* `GET v2/payment_options`, `PATCH …/{id} {"default": true}`, `DELETE …/{id}`.

### Tickets

* `GET v4/tickets` -> `{payment_options, tickets: [{id, type, status, name,
  validity {from, to}, state, price, pdf_url, booking_details_url, fields, …}]}`.
* Barcode: `GET <booking_details_url>` -> `partner|aggregator|group` ->
  `ticket_preview.groups[].tickets[]` mit `barcode` = fertiges Bild (Base64),
  `title`, `validity`, `expired`, `cancelled`. Token nur für api.i-mobility.at.

Nicht benutzt: `v1/reservation`, `v1/memberships`, `v2/shop`, `v3/rental`,
`v1/promotions`, `v1/discounts`, Google Pay, …

## Dienst: wf-dienst

Zeilenprotokoll über stdin/stdout:

    hin:     <id> TAB <befehl> TAB <json>
    zurück:  <id> TAB <1|0> TAB <json oder Fehlertext als JSON-String>

| Befehl | Werte | Antwort |
|---|---|---|
| `start` | – | `{version, plattform, einstellungen, wlan}` |
| `netz` | – | `{wlan}` |
| `suche` | `{text, lat?, lon?}` | `[Ort]` |
| `routen` | `{von: Ort, nach: Ort, datum?, zeit?, ankunft?}` | `{gruppen, offen, preise_url, start, ziel, meldungen}` |
| `routen_url` | `{url}` | wie `routen` |
| `preise` | `{url}` (die `preise_url` einer Routenantwort) | `{route_id: {text, cent, geschaetzt, hinweis, co2}}` |
| `karte` | `{route: id, max?}` | `{linien: [{art, farbe, punkte: [[lat, lon]…]}], marker: [{lat, lon, name, rolle, farbe}], rahmen: {n, s, w, o}}` |
| `abfahrten` | `{station, max?, neu?}` | `{abfahrten: [Abfahrt], gesamt, station, stand}` |
| `fahrt` | `{url}` | `{halte, aktuell, meldungen, linie}` |
| `umgebung` | `{n, s, w, o, zoom, filter, breite, hoehe, max?}` | `{punkte, gruppen, gesamt}` (die nächsten `max`) |
| `filter` | – | `[{id, titel, kurz, leer}]` (1 Tag zwischengespeichert) |
| `orte`, `ort_merken`, `ort_entfernen`, `verbindung_merken`, `verlauf_leeren` | `{ort, favorit?, bezeichnung?}` / `{von, nach}` | `{favoriten, verlauf, verbindungen}` |
| `einstellungen`, `einstellungen_setzen` | `{weitere_laden, karte_mobil, abfahrten_max, umgebung_filter}` | Einstellungen |
| `kacheln` | – | `{port}` des Kachelservers (`GET /<z>/<x>/<y>.png`) |
| `konto`, `anmelden`, `registrieren`, `abmelden`, `email_code`, `email_code_senden` | `{email, kennwort}` / `{code}` | `{angemeldet, email, vorname, nachname, email_offen}` |
| `kauf_start` | `{daten}` (aus `preise`: `kauf`) | Ansicht `{id, bildschirm, summary|pending|success|error}` |
| `kauf_angebot`, `kauf_zahlung`, `kauf_name`, `kauf_bestaetigen`, `kauf_abgleichen`, `kauf_neu_starten`, `kauf_laden`, `kauf_stand`, `kauf_wiederholen`, `kauf_abbrechen` | `{id, …}` | Ansicht |
| `kauf_buchen` | `{id, bestaetigt: true, preis}` | Ansicht (bucht kostenpflichtig; nur ohne offene Voraussetzungen und mit unverändertem Preis) |
| `zahlungsmittel`, `zahlungsmittel_status`, `zahlungsmittel_standard`, `zahlungsmittel_loeschen` | `{id}` | Liste bzw. Zahlungsmittel |
| `karte_anlegen` | `{nummer, ablauf, cvc, quelle?}` | Zahlungsmittel (mit `redirect` für 3-D Secure) |
| `paypal_anlegen`, `paypal_fertig` | `{quelle?}` / `{id}` | Zahlungsmittel (mit `freigabe`) |
| `tickets`, `ticket`, `ticket_pdf` | – / `{id}` | Liste; Details mit Barcode-Bilddateien; PDF in ~/Downloads |
| `speicher`, `kacheln_leeren` | – | `{kacheln, text}` |

**Ort**: `{id, name, unter, typ (station|street|address|poi|standort|koordinate), lat, lon, arten}`

**Route**: `{id, gruppe (oeffi|selbst|teilen|weitere), art, typ, farbe, titel,
untertitel, anbieter, ab: Halt, an: Halt, erste_fahrt: Halt, dauer,
dauer_min, umstiege, strecke, linien: [{text, farbe, art}], abschnitte,
meldungen, ausstattung, ausgefallen, verspaetung}`

**Abschnitt**: `{art, typ, farbe, linie, kurz, richtung, bezeichnung, dauer,
strecke, von: Halt, nach: Halt, halte: [Halt], infos: [{label, wert}],
ausgefallen}`

**Halt**: `{name, id, lat, lon, zeit, live, verspaetung, echtzeit, tag, gleis,
gleiswechsel, ausgefallen}`

`art` ist die grobe Art fürs Sinnbild: zug, sbahn, ubahn, tram, bus, schiff,
seilbahn, fuss, rad, scooter, auto, taxi, sonst.
