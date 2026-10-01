#!/bin/sh
# Run the game in the desktop engine (an SDL window, 3x). Extra arguments go to main.py (see sys.argv there).
cd "$(dirname "$0")/../Galaga" || exit 1
MP=../build/mp-thumby/ports/unix/build-standard/micropython
[ -x "$MP" ] || { echo "Run tools/setup-macos.sh first." >&2; exit 1; }
exec "$MP" -X heapsize=2617152 main.py "$@"
