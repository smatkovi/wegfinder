#!/bin/sh
# Rendert die Sinnbilder (icons/sinnbilder, Verkehrsmittel) und die
# Werkzeugsymbole (icons/werkzeug) fuer beide Oberflaechen als PNG:
#
#   meego/qml/bilder/      Sinnbilder 48 px, Werkzeug 40 px (Harmattan-Leiste)
#   sailfish/qml/bilder/   Sinnbilder 64 px, Werkzeug 64 px
#
# Weiss auf durchsichtig; die Farbe kommt in der Oberflaeche dahinter.
set -e
cd "$(dirname "$0")/.."
command -v rsvg-convert >/dev/null || { echo "rsvg-convert fehlt" >&2; exit 1; }
for ziel in meego sailfish; do
    mkdir -p "$ziel/qml/bilder"
    if [ "$ziel" = meego ]; then gs=48; gw=40; else gs=64; gw=64; fi
    for f in icons/sinnbilder/*.svg; do
        rsvg-convert -w $gs -h $gs "$f" -o "$ziel/qml/bilder/$(basename "$f" .svg).png"
    done
    for f in icons/werkzeug/*.svg; do
        rsvg-convert -w $gw -h $gw "$f" -o "$ziel/qml/bilder/$(basename "$f" .svg).png"
    done
done
echo "== Bilder: $(ls meego/qml/bilder | wc -l) je Oberflaeche"
