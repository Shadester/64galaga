#!/usr/bin/env bash
# Screenshot regression tests: build each case with its debug flags, run it
# headless in VICE for a fixed number of cycles, compare the last frame with
# tests/ref/<case>.png (tests/cmp.py: a few dozen pixels of raster jitter are fine).
# Usage: tests/run.sh [--update] [case ...]
set -uo pipefail
cd "$(dirname "$0")/.."

# name|ACME flags|game loops until the game freezes (-DHALT), so the screenshot is exact|disk
# VICE runs frames*20000+10M cycles: a loop that overruns a frame (many divers) needs up to 2x.
# disk: 'new' attaches a fresh blank disk, 'keep' the disk of the previous 'new' case
# (hs-save writes the hi-score file, hs-load must show it on the title screen).
CASES='
title||100
entry|-DAUTOPLAY=1 -DNOFIRE=1|230
settled|-DAUTOPLAY=1 -DNOFIRE=1|700
play|-DAUTOPLAY=1|400
challenge|-DAUTOPLAY=1 -DSTAGE=3|500
explode|-DAUTOPLAY=1 -DNOFIRE=1 -DDIEAT=400|425
ready|-DAUTOPLAY=1 -DNOFIRE=1 -DDIEAT=400|520
hard|-DAUTOPLAY=1 -DNOFIRE=1 -DDIFF=8|800
pause|-DAUTOPLAY=1 -DNOFIRE=1 -DPAUSEAT=500|540
capture|-DAUTOPLAY=1 -DCAPTURE=1|3000
result|-DAUTOPLAY=1 -DFEW=1|700
gameover|-DAUTOPLAY=1 -DNOFIRE=1 -DHALTOVER=1|20000
hs-save|-DAUTOPLAY=1 -DLIVES=1 -DDIEAT=600 -DHALTOVER=1|1000|new
hs-load||100|keep
'

update=0
[ "${1:-}" = "--update" ] && { update=1; shift; }
out=build/test
mkdir -p "$out" tests/ref
fail=0
while IFS='|' read -r name flags frames disk; do
    [ -z "$name" ] && continue
    [ $# -gt 0 ] && [[ " $* " != *" $name "* ]] && continue
    acme -f cbm $flags -DHALT=$frames -o "$out/$name.prg" src/main.asm || { echo "BUILD $name"; fail=1; continue; }
    drive=()
    if [ "$disk" = new ]; then rm -f "$out/hs.d64"; c1541 -format test,01 d64 "$out/hs.d64" >/dev/null 2>&1; fi
    [ -n "$disk" ] && drive=(-8 "$out/hs.d64")
    # VICE's autostart occasionally misses the READY prompt: one retry
    for try in 1 2; do
        rm -f "$out/$name.png"
        # +sound: VICE can stall on a Bluetooth default audio device
        x64sc -default +sound -warp -autostartprgmode 1 ${drive[@]+"${drive[@]}"} -VICIIdsize -VICIIfilter 0 \
            -limitcycles $((frames * 20000 + 10000000)) \
            -exitscreenshot "$PWD/$out/$name.png" -autostart "$out/$name.prg" >/dev/null 2>&1
        [ $update = 0 ] && python3 tests/cmp.py "$out/$name.png" "tests/ref/$name.png" && break
    done
    if [ ! -f "$out/$name.png" ]; then echo "FAIL $name (no screenshot)"; fail=1
    elif [ $update = 1 ]; then cp "$out/$name.png" "tests/ref/$name.png"; echo "UPDATED $name"
    elif python3 tests/cmp.py "$out/$name.png" "tests/ref/$name.png"; then echo "PASS $name"
    else echo "FAIL $name (see $out/$name.png)"; fail=1; fi
done <<< "$CASES"
exit $fail
