#!/bin/sh
# Baut den Netzdienst (Rust) fuer ein Ziel.
#
#   tools/build-dienst.sh meego      # -> build/meego/wf-dienst
#   tools/build-dienst.sh armv7hl    # -> sailfish/prebuilt/armv7hl/wf-dienst
#   tools/build-dienst.sh aarch64    # -> sailfish/prebuilt/aarch64/wf-dienst
#   tools/build-dienst.sh pc         # -> build/pc/wf-dienst (zum Probieren)
set -e
cd "$(dirname "$0")/.."
. tools/rust.env
if [ ! -x "$CARGO_HOME/bin/cargo" ] || [ ! -d /tmp/rust/aarch64-linux-musl-cross ]; then
    sh tools/toolchain.sh
    . tools/rust.env
fi

case "$1" in
    meego)   ZIEL=armv7-unknown-linux-musleabi;   AUS=build/meego ;;
    armv7hl) ZIEL=armv7-unknown-linux-musleabihf; AUS=sailfish/prebuilt/armv7hl ;;
    aarch64) ZIEL=aarch64-unknown-linux-musl;     AUS=sailfish/prebuilt/aarch64 ;;
    pc)      ZIEL="";                             AUS=build/pc ;;
    *) echo "Ziel: meego | armv7hl | aarch64 | pc" >&2; exit 2 ;;
esac

mkdir -p "$AUS"
if [ -n "$ZIEL" ]; then
    cargo build --release --target "$ZIEL" --manifest-path dienst/Cargo.toml
    cp "$CARGO_TARGET_DIR/$ZIEL/release/wf-dienst" "$AUS/"
else
    cargo build --release --manifest-path dienst/Cargo.toml
    cp "$CARGO_TARGET_DIR/release/wf-dienst" "$AUS/"
fi
echo "== $AUS/wf-dienst ($(stat -c %s "$AUS/wf-dienst") B)"
