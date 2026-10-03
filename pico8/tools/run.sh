#!/bin/sh
# Run the cart in PICO-8 in a window. Extra arguments go to PICO-8, e.g. -p "autoplay stage=3" (see README).
# PICO8=/path/to/pico8 overrides the binary.
cd "$(dirname "$0")/.." || exit 1
exec "${PICO8:-/Applications/PICO-8.app/Contents/MacOS/pico8}" -windowed 1 -run galaga.p8 "$@"
