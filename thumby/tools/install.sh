#!/bin/sh
# Copy the game to a Thumby Color that is connected with USB (needs mpremote: pip install mpremote).
# It goes to /Games/Galaga. Without mpremote: copy the Galaga folder with the Thumby Color Code Editor
# (https://color.thumby.us/code/) or Thonny.
cd "$(dirname "$0")/../Galaga" || exit 1
command -v mpremote >/dev/null || { echo "mpremote not found: pip install mpremote" >&2; exit 1; }
mpremote fs mkdir :/Games/Galaga 2>/dev/null
mpremote fs mkdir :/Games/Galaga/jingles 2>/dev/null
for f in manifest.ini main.py game.py view.py sfx.py paths_data.py sprite_ids.py sprites.bmp beams.bmp title.bmp icon.bmp; do
    mpremote fs cp "$f" ":/Games/Galaga/$f" || exit 1
done
for f in jingles/*.rtttl; do
    mpremote fs cp "$f" ":/Games/Galaga/$f" || exit 1
done
echo "Installed: choose Galaga in the launcher."
