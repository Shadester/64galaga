#!/bin/sh
# Build the ADF (if the sources changed) and run it in FS-UAE (brew install --cask fs-uae-emulator): a window, an Amiga 500, the
# Kickstart replacement AROS that is inside FS-UAE (no copyrighted ROM). Close the window to stop.
#   KICKSTART=/path/to/rom   use a Kickstart ROM instead of AROS      EMULATOR=/path/to/fs-uae   another binary
cd "$(dirname "$0")/.." || exit 1
make >/dev/null || exit 1
EMU=${EMULATOR:-/Applications/FS-UAE.app/Contents/MacOS/fs-uae}
if [ ! -x "$EMU" ]; then
    echo "$EMU not found. Install it with: brew install --cask fs-uae-emulator" >&2
    echo "Or play in the browser: https://vamigaweb.github.io/#AROS=true#https://raw.githubusercontent.com/Shadester/galagas/master/amiga/docs/galaga.adz" >&2
    exit 1
fi
exec "$EMU" --amiga_model=A500 --kickstart_file="${KICKSTART:-internal}" --floppy_drive_0=build/galaga.adf \
    --fullscreen=0 --window_width=960 --window_height=720 --floppy_drive_volume=0
