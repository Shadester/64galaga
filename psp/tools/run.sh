#!/bin/sh
# Build EBOOT.PBP (if sources changed) and run it in PPSSPP. Usage: run.sh
# PPSSPP=/path/to/binary overrides the emulator.
cd "$(dirname "$0")/.." || exit 1
make >/dev/null || exit 1
PPSSPP=${PPSSPP:-/Applications/PPSSPPSDL.app/Contents/MacOS/PPSSPPSDL}
exec "$PPSSPP" "$PWD/EBOOT.PBP"
