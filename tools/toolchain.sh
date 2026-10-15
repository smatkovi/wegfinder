#!/bin/sh
# Richtet Rust und die musl-Cross-Toolchains unter /tmp/rust ein.
#
# /tmp ist ein tmpfs: nach einem Neustart ist alles weg, dieses Skript baut
# es in wenigen Minuten wieder auf.
set -e
. "$(dirname "$0")/rust.env"

if [ ! -x "$CARGO_HOME/bin/cargo" ]; then
    echo "== rustup"
    mkdir -p "$(dirname "$CARGO_HOME")"
    curl -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh
    sh /tmp/rustup-init.sh -y --no-modify-path --profile minimal --default-toolchain stable
fi
rustup target add armv7-unknown-linux-musleabi armv7-unknown-linux-musleabihf aarch64-unknown-linux-musl

cd /tmp/rust
for t in arm-linux-musleabi-cross armv7l-linux-musleabihf-cross aarch64-linux-musl-cross; do
    if [ ! -d "$t" ]; then
        echo "== $t"
        curl -sSfLO "https://musl.cc/$t.tgz"
        tar xzf "$t.tgz"
        rm -f "$t.tgz"
    fi
done
. "$(dirname "$0")/rust.env" 2>/dev/null || true
echo "== Toolchain bereit"
