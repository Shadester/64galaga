#!/bin/sh
# Build and run the game in VICE: a window, not full screen. A and D move, Space fires (joystick port 2 on a keyset: .vice/vicerc).
# Extra arguments go to x64sc (e.g. -warp). The hi-score is saved on build/galaga.d64 until the next build makes a new disk.
cd "$(dirname "$0")/.." || exit 1
make >/dev/null || exit 1
exec x64sc -config .vice/vicerc +VICIIfull -VICIIdsize -VICIIfilter 0 "$@" -autostart build/galaga.d64
