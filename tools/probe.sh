#!/bin/sh
# Probelauf der N9-Oberflaeche am Rechner (siehe tools/probe/probe.cpp).
#
#   tools/probe.sh 'js:...' warte:2000 bild:/tmp/a.png ...
#
# Baut den Netzdienst fuer den Rechner und das Probeprogramm gegen das
# X11-Qt 4.8.1 aus dem QtSDK; die Harmattan-Komponenten und das blanco-Thema
# kommen aus dessen Desktop-Teil (474/gcc). Der Dienst spricht mit dem
# echten Server, mit eigenem HOME. QtMobility.location gibt es am Rechner
# nicht: tools/probe/location ersetzt PositionSource (fester Standort).
set -e
cd "$(dirname "$0")/.."
WURZEL=$(pwd)
QT=${QT_DESKTOP:-$HOME/QtSDK/Desktop/Qt/4.8.1/gcc}
KOMP=${QT_KOMPONENTEN:-$HOME/QtSDK/Desktop/Qt/474/gcc}
AUS=/tmp/wf-probe
mkdir -p "$AUS" "$AUS/heim"

. tools/rust.env
cargo build --release --manifest-path dienst/Cargo.toml 2>&1 | grep -E "^(error|warning)" || true
DIENST=$CARGO_TARGET_DIR/release/wf-dienst

if [ ! -x "$AUS/probe" ] || [ tools/probe/probe.cpp -nt "$AUS/probe" ] \
        || [ meego/src/Dienst.cpp -nt "$AUS/probe" ] || [ meego/src/Dienst.h -nt "$AUS/probe" ]; then
    "$QT/bin/moc" meego/src/Dienst.h -o "$AUS/moc_Dienst.cpp"
    "$QT/bin/moc" tools/probe/probe.cpp -o "$AUS/probe.moc"
    INC="-I$QT/include -I$WURZEL/meego -I$AUS"
    for m in QtCore QtGui QtDeclarative; do INC="$INC -I$QT/include/$m"; done
    # Das SDK-Qt ist mit einem alten GCC gebaut: alte std::string-ABI.
    g++ -D_GLIBCXX_USE_CXX11_ABI=0 -fPIC -O1 -w $INC \
        tools/probe/probe.cpp meego/src/Dienst.cpp "$AUS/moc_Dienst.cpp" \
        -o "$AUS/probe" -L"$QT/lib" -lQtDeclarative -lQtGui -lQtCore -Wl,-rpath,"$QT/lib"
fi
SYSROOT=${SYSROOT:-$HOME/QtSDK/Madde/sysroots/harmattan_sysroot_10.2011.34-1_slim}
EXTRAS=$AUS/imports/com/nokia/extras
if [ ! -f "$EXTRAS/libmeegoextrasplugin.so" ] || [ tools/probe/extras-ersatz.cpp -nt "$EXTRAS/libmeegoextrasplugin.so" ]; then
    mkdir -p "$EXTRAS"
    cp -r "$SYSROOT/usr/lib/qt4/imports/com/nokia/extras/." "$EXTRAS/"
    rm -f "$EXTRAS/libmeegoextrasplugin.so"
    INC="-I$QT/include"
    for m in QtCore QtGui QtDeclarative; do INC="$INC -I$QT/include/$m"; done
    "$QT/bin/moc" tools/probe/extras-ersatz.cpp -o "$AUS/extras-ersatz.moc"
    g++ -D_GLIBCXX_USE_CXX11_ABI=0 -fPIC -shared -O1 -w $INC -I"$AUS" \
        tools/probe/extras-ersatz.cpp -o "$EXTRAS/libmeegoextrasplugin.so" \
        -L"$QT/lib" -lQtDeclarative -lQtGui -lQtCore -Wl,-rpath,"$QT/lib"
fi
mkdir -p "$AUS/imports/QtMobility/location"
cp tools/probe/location/* "$AUS/imports/QtMobility/location/"
cat > "$AUS/qt.conf" <<QTCONF
[Paths]
Prefix=$KOMP
Imports=$KOMP/imports
Plugins=$QT/plugins
Libraries=$QT/lib
QTCONF
# Ein eigener X-Server mit dem Dummy-Treiber, 480x854 wie das Telefon.
ANZEIGE=${PROBE_DISPLAY:-:7}
if ! [ -e "/tmp/.X11-unix/X${ANZEIGE#:}" ]; then
    # Ohne Sitz auf der Konsole verweigert Xorg /dev/tty0; dann mit sudo.
    /usr/lib/Xorg "$ANZEIGE" -config "$WURZEL/tools/probe/n950.conf" -logfile "$AUS/xorg.log" \
        -noreset -nolisten tcp -keeptty -novtswitch -sharevts >/dev/null 2>&1 &
    sleep 2
    if ! [ -e "/tmp/.X11-unix/X${ANZEIGE#:}" ]; then
        sudo -n /usr/lib/Xorg "$ANZEIGE" -config "$WURZEL/tools/probe/n950.conf" -logfile "$AUS/xorg.log" \
            -noreset -nolisten tcp -keeptty -novtswitch -sharevts >/dev/null 2>&1 &
        sleep 3
    fi
fi
# Die Bilder braucht die Oberflaeche aus meego/qml/bilder (tools/bilder.sh).
[ -d meego/qml/bilder ] || sh tools/bilder.sh
HOME="$AUS/heim" DISPLAY=$ANZEIGE M_FORCE_LOCAL_THEME=1 LD_LIBRARY_PATH="$QT/lib" \
    QML_IMPORT_PATH="$AUS/imports" \
    "$AUS/probe" "$DIENST" "$WURZEL/meego/qml/main.qml" "$@" 2>&1 \
    | grep -vE "LocalThemeDaemonClient|^\s*$|Cannot open file|Failed to get image from provider|Window.qml:110|wf-dienst: .* ok in|netz: .*Wurzelzertifikate|bereit \(|^netz: "
