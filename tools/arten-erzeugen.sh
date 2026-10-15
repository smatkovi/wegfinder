#!/bin/sh
# Erzeugt dienst/src/arten.rs (Farben und Namen der Verkehrsmittel) aus der
# APK der Android-App: assets/definitions.json und assets/translations/de.json.
#
#   tools/arten-erzeugen.sh [APK]
set -e
cd "$(dirname "$0")/.."
APK=${1:-${WF_APK:-$HOME/Downloads/wegfinder_26.20.0_APKPure.apk}}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unzip -q -o "$APK" assets/definitions.json assets/translations/de.json -d "$TMP"
python3 - "$TMP/assets" > dienst/src/arten.rs <<'PY'
import json, sys
a = sys.argv[1]
d = json.load(open(a + "/definitions.json"))
tr = json.load(open(a + "/translations/de.json"))
print("//! Farben und Bezeichnungen der Verkehrsmittel, je Kennung des Servers.")
print("//!")
print("//! Erzeugt aus assets/definitions.json und assets/translations/de.json der")
print("//! Android-App 26.20.0 (tools/arten-erzeugen.sh). Nur Fakten: Linienfarben")
print("//! und Namen, keine Grafiken.")
print()
print("pub const ARTEN: &[(&str, &str, &str)] = &[")
for t in d["transport"]:
    if "mock" in t["id"]:
        continue
    lab = tr.get(t["translation_key"], "")
    print("    (%s, %s, %s)," % (json.dumps(t["id"]), json.dumps(t["color"].lower()), json.dumps(lab, ensure_ascii=False)))
print("];")
print()
print("pub const GRUPPEN: &[(&str, &str)] = &[")
for g in d["transportation_group"]:
    print("    (%s, %s)," % (json.dumps(g["id"]), json.dumps(tr.get(g["translation_key"], g["id"]), ensure_ascii=False)))
print("];")
PY
echo "== dienst/src/arten.rs: $(grep -c '^    (' dienst/src/arten.rs) Eintraege"
