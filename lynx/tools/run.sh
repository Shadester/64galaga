#!/bin/sh
# Build and run the game in the Gearlynx window. LYNX_BIOS overrides the boot ROM (default lynx/lynxboot.img).
cd "$(dirname "$0")/.." || exit 1
B=${BUILD:-build}
make BUILD="$B" $MAKEARGS >/dev/null || exit 1
BIOS=$(cd "$(dirname "${LYNX_BIOS:-lynxboot.img}")" && pwd)/$(basename "${LYNX_BIOS:-lynxboot.img}")
[ -f "$BIOS" ] || { echo "Boot ROM not found: $BIOS (see README)" >&2; exit 1; }
INI="$HOME/Library/Application Support/Geardome/Gearlynx/config.ini"
[ -f "$INI" ] && sed -i '' "s|^BiosPath =.*|BiosPath = $BIOS|" "$INI"   # Gearlynx has no BIOS flag
exec /Applications/Gearlynx.app/Contents/MacOS/gearlynx -w "$PWD/$B/galaga.lnx"   # -w: window with the menu (Video: scaling)
