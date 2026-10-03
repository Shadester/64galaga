#!/bin/sh
# Build the WebAssembly module of the browser version: docs/tui/galaga.wasm (committed). Needs: rustup target add wasm32-unknown-unknown
cd "$(dirname "$0")/.." || exit 1
cargo build --release --lib --no-default-features --target wasm32-unknown-unknown -q || exit 1
mkdir -p ../docs/tui
cp target/wasm32-unknown-unknown/release/galaga_tui.wasm ../docs/tui/galaga.wasm
ls -l ../docs/tui/galaga.wasm | awk '{print $5, "bytes: docs/tui/galaga.wasm"}'
