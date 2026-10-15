#!/bin/sh
# Packt Oberflaeche, Dienst und QML als Harmattan-.deb.
#
#   meego/build-deb.sh [version]     # -> build/wegfinder_<version>_armel.deb
#
# Keine versionierten Abhaengigkeiten: das installierte Qt ist
# 4.7.4~git20120327, und "~" sortiert unter der leeren Zeichenkette.
set -e
cd "$(dirname "$0")/.."

VERSION=${1:-$(sed -n 's/^version = "\(.*\)"/\1/p' dienst/Cargo.toml | head -1)}
STAGE=build/stage-meego
rm -rf "$STAGE"

for b in wegfinder wf-dienst; do
    [ -x build/meego/$b ] || { echo "build/meego/$b fehlt -- erst tools/build-meego.sh" >&2; exit 1; }
done
[ -f meego/icons/icon-80.png ] || python3 icons/make-icons.py
[ -d meego/qml/bilder ] || sh tools/bilder.sh

mkdir -p "$STAGE/opt/wegfinder/bin" "$STAGE/opt/wegfinder/qml/bilder" \
         "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/icons/hicolor/80x80/apps" \
         "$STAGE/DEBIAN"

cp build/meego/wegfinder build/meego/wf-dienst "$STAGE/opt/wegfinder/bin/"
chmod 755 "$STAGE/opt/wegfinder/bin/"*
cp meego/qml/*.qml meego/qml/*.js "$STAGE/opt/wegfinder/qml/"
cp meego/qml/bilder/*.png "$STAGE/opt/wegfinder/qml/bilder/"
cp meego/wegfinder.desktop "$STAGE/usr/share/applications/"
cp meego/postinst meego/prerm "$STAGE/DEBIAN/"
# Aegis: Standort fuer "Mein Standort" und "In der Naehe"
cp meego/wegfinder.aegis "$STAGE/DEBIAN/_aegis"
chmod 755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/prerm"
cp meego/icons/icon-80.png "$STAGE/usr/share/icons/hicolor/80x80/apps/wegfinder.png"

VERSION="$VERSION" STAGE="$STAGE" python3 - <<'PY'
import base64, io, os, textwrap
icon = base64.b64encode(open("meego/icons/icon-64.png", "rb").read()).decode("ascii")
text = io.open("meego/control.in", encoding="utf-8").read()
text = text.replace("@VERSION@", os.environ["VERSION"])
# Die base64-Zeilen brauchen je ein fuehrendes Leerzeichen, sonst zeigt der
# Programm-Manager kein Bild.
text = text.replace("@ICON@", "\n".join(" " + z for z in textwrap.wrap(icon, 76)))
io.open(os.environ["STAGE"] + "/DEBIAN/control", "w", encoding="utf-8").write(text)
PY

DEB="build/wegfinder_${VERSION}_armel.deb"
python3 meego/mkdeb.py "$STAGE" "$DEB"
