#!/bin/sh
# Baut die Sailfish-RPMs fuer armv7hl und aarch64 nach build/.
#
#   tools/build-sailfish.sh                # beide Ziele
#   tools/build-sailfish.sh aarch64        # nur eines
#
# Erst der Netzdienst (Rust, statisch) je Architektur nach
# sailfish/prebuilt/<arch>/, dann die Oberflaeche mit mb2 in der
# Platform-SDK-Chroot. Gebaut wird gegen SailfishOS 5.1.0.11 (wie
# wienzufuss). Anderes Ziel: SFOS_ZIEL=SailfishOS-5.2.0.15.
set -e
cd "$(dirname "$0")/.."
WURZEL=$(pwd)
SDK=${SFOS_SDK:-/srv/sailfishos/sdks/sfossdk/sdk-chroot}
ZIEL=${SFOS_ZIEL:-SailfishOS-5.1.0.11}
ARCHS=${1:-"armv7hl aarch64"}
VERSION=$(sed -n 's/^Version: *//p' sailfish/rpm/wegfinder.spec | head -1)
mkdir -p build

python3 icons/make-icons.py
sh tools/bilder.sh

for arch in $ARCHS; do
    if [ ! -x "sailfish/prebuilt/$arch/wf-dienst" ] || \
       [ -n "$(find dienst/src dienst/Cargo.toml -newer "sailfish/prebuilt/$arch/wf-dienst" 2>/dev/null)" ]; then
        sh tools/build-dienst.sh "$arch"
    fi
    # In-place-Bau: die Makefiles des vorigen Ziels zeigen auf dessen qmake.
    ( cd sailfish && rm -rf Makefile* .qmake.stash *.o moc_* wegfinder installroot RPMS )
    echo "== mb2 $ZIEL-$arch"
    # --no-fix-version: sonst setzt mb2 in einer Git-Arbeitskopie eine Version
    # aus "git describe" ein (0.1.0+main.<datum>.<hash>) statt der aus der spec.
    "$SDK" bash -c "cd '$WURZEL/sailfish' && mb2 --no-fix-version -t '$ZIEL-$arch' build" > "build/mb2-$arch.log" 2>&1 || {
        tail -30 "build/mb2-$arch.log" >&2
        echo "== mb2 fuer $arch gescheitert, Protokoll: build/mb2-$arch.log" >&2
        exit 1
    }
    cp "sailfish/RPMS/wegfinder-$VERSION-1.$arch.rpm" build/
    echo "== build/wegfinder-$VERSION-1.$arch.rpm ($(stat -c %s "build/wegfinder-$VERSION-1.$arch.rpm") B)"
done
( cd sailfish && rm -rf Makefile* .qmake.stash *.o moc_* wegfinder installroot RPMS )
