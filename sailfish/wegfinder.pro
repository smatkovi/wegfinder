# wegfinder fuer Sailfish OS: die Oberflaeche. Der Netzdienst (Rust) kommt
# fertig gebaut aus prebuilt/<arch>/ (tools/build-dienst.sh) und wird in der
# spec installiert.
TARGET = wegfinder

CONFIG += sailfishapp c++11
QT += dbus

isEmpty(VERSION) {
    VERSION = 0.1.1
}
DEFINES += APP_VERSION=\\\"$$VERSION\\\"
DEFINES += NETZDIENST=\\\"/usr/libexec/wegfinder/wf-dienst\\\"

# Die Bruecke zum Netzdienst ist dieselbe wie auf dem N9 (Qt 4 und Qt 5 aus
# einer Quelle).
INCLUDEPATH += ../meego/src
SOURCES += src/main.cpp src/Karten.cpp ../meego/src/Dienst.cpp
HEADERS += src/Karten.h ../meego/src/Dienst.h

# Die Hilfsfunktionen teilen sich beide Oberflaechen.
wfjs.files = ../meego/qml/wf.js
wfjs.path = /usr/share/wegfinder/qml
INSTALLS += wfjs

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172

OTHER_FILES += rpm/wegfinder.spec wegfinder.desktop
