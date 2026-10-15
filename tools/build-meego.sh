#!/bin/sh
# Baut alles fuer das N9/N950 nach build/meego/:
#
#   wf-dienst    Netzdienst (Rust, statisch gegen musl, armel/softfloat)
#   wegfinder    Oberflaeche (Qt 4.7, QML 1, Harmattan-Komponenten)
#
#   tools/build-meego.sh
#
# Die Oberflaeche mit MADDEs GCC 4.4.1 gegen den Harmattan-Sysroot: das ist
# der Compiler, mit dem das Qt auf dem Geraet gebaut ist, also passt die
# C++-Laufzeit (C++98). moc kommt aus dem Simulator-Qt desselben SDK
# (4.7.4, gleiche moc-Revision wie auf dem Geraet).
set -e
cd "$(dirname "$0")/.."
WURZEL=$(pwd)
mkdir -p build/meego

python3 icons/make-icons.py
sh tools/bilder.sh

if [ ! -x build/meego/wf-dienst ] || [ -n "$(find dienst/src dienst/Cargo.toml -newer build/meego/wf-dienst 2>/dev/null)" ]; then
    sh tools/build-dienst.sh meego
fi

MADDE=${MADDE:-$HOME/QtSDK/Madde}
CXX=${CXX_HARMATTAN:-$MADDE/toolchains/arm-2009q3-67-arm-none-linux-gnueabi-x86_64-unknown-linux-gnu/arm-2009q3-67/bin/arm-none-linux-gnueabi-g++}
SYSROOT=${SYSROOT:-$MADDE/sysroots/harmattan_sysroot_10.2011.34-1_slim}
MOC=${MOC:-$HOME/QtSDK/Simulator/Qt/gcc/bin/moc}
if [ ! -x "$CXX" ]; then
    echo "== Harmattan-C++ fehlt ($CXX) -- nur der Dienst wurde gebaut" >&2
    exit 0
fi
QTINC=$SYSROOT/usr/include/qt4
CXXFLAGS="--sysroot=$SYSROOT -O2 -Wall -DQT_NO_DEBUG -I$QTINC"
for m in QtCore QtGui QtNetwork QtDeclarative; do
    CXXFLAGS="$CXXFLAGS -I$QTINC/$m"
done
LDFLAGS="--sysroot=$SYSROOT -Wl,-O1 -Wl,--as-needed -s -L$SYSROOT/usr/lib"

OBJ=/tmp/wf-meego-obj
mkdir -p "$OBJ"
"$MOC" meego/src/Dienst.h -o "$OBJ/moc_Dienst.cpp"
OBJE=""
for q in meego/main.cpp meego/src/Dienst.cpp "$OBJ/moc_Dienst.cpp"; do
    o="$OBJ/$(basename "$q" .cpp).o"
    "$CXX" $CXXFLAGS -I"$WURZEL/meego" -c "$q" -o "$o"
    OBJE="$OBJE $o"
done
"$CXX" $LDFLAGS -o build/meego/wegfinder $OBJE -lQtDeclarative -lQtGui -lQtCore -lpthread
echo "== wegfinder fertig ($(stat -c %s build/meego/wegfinder) B)"
