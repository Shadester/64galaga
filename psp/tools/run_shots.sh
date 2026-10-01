#!/bin/sh
# Debug: build an AUTOPLAY EBOOT, run it in PPSSPP (software renderer so VRAM is readable) and
# leave BMP frames in ~/.config/ppsspp/PSP/shots. Usage: run_shots.sh "<extra cflags>" [seconds]
cd "$(dirname "$0")/.." || exit 1
INI=$HOME/.config/ppsspp/PSP/SYSTEM/ppsspp.ini
rm -f main.o game.o; make EXTRA_CFLAGS="-DAUTOPLAY $1" 2>&1 | grep -E "warning|error"
cp EBOOT.PBP "${TMPDIR}auto.PBP"; cp "$INI" "${TMPDIR}ppsspp.ini.bak"
sed -i '' 's/^SoftwareRenderer = False/SoftwareRenderer = True/' "$INI"
rm -rf "$HOME/.config/ppsspp/PSP/shots"
/Applications/PPSSPPSDL.app/Contents/MacOS/PPSSPPSDL "${TMPDIR}auto.PBP" >/dev/null 2>&1 &
sleep "${2:-25}"; pkill -f PPSSPPSDL; sleep 1
cp "${TMPDIR}ppsspp.ini.bak" "$INI"
ls "$HOME/.config/ppsspp/PSP/shots" | wc -l
