# Galaga for the Amiga

[**▶ Play it in your browser**](https://vamigaweb.github.io/#AROS=true#https://raw.githubusercontent.com/Shadester/galagas/master/amiga/docs/galaga.adz) (vAmigaWeb, with its own AROS ROM: no Kickstart needed)

A port of the Galaga clone to the Commodore Amiga 500 (68000, OCS chipset, PAL). It is a bootable floppy disk: the game starts from the boot block and takes over the whole machine. There is no AmigaOS in it.

![Gameplay: the title screen, then the autoplay build with stage intro, fly-in, a tractor beam and a capture](docs/gameplay.gif)

The rules are the rules of the PSP game, the arcade rules: the game uses `../psp/game.c` itself (the reference). It is compiled without floating point (the arcade paths are a table). A test runs the 68000 build in an emulator and compares the whole game state with the build on the Mac, for 15000 ticks.

## Status

It runs in vAmigaWeb. The rules, the pictures and the keyboard are tested there. **The sound has not been heard**: it is checked by reading the code only. It has not been tried on a real Amiga.

## Features

The same features as the other versions: 40-alien formation with fly-in waves and dives, bosses that take two hits, tractor beam capture, rescue and dual fighter, challenge stages with a 10,000 bonus, a shots / hits / ratio screen after each stage, bonus ships, title picture, jingles and sound effects.

What is different:

- The play area is 320 x 200 pixels, the same as the C64: the game keeps the C64 coordinates, and an alien is the C64 sprite (24 x 22 pixels). The hud (score, hi-score, stage and the lives) is above the play area. The copper shows the play area shifted to the left or right, so the formation sways without being drawn again.
- 32 colours, 5 bitplanes. The sprites are drawn at 1-pixel resolution and shaded (`tools/art.py`): the aliens, the ship and the other pictures are our own art (`psp/art.h`, the same as the other ports), made 1.5 times as big. Three screen buffers: the blitter draws the sprites in a buffer that is not shown. The aliens, the ship and the bullets are not hardware sprites, so there is no limit of 8 (and no multiplexer, unlike the C64).
- The beam is drawn with the CPU as checkerboard cells. The stars are hardware sprites (two layers, in fixed columns, as in the arcade game).
- Sound is made by Paula: 8-bit samples for the effects (made by `tools/gen_assets.py`) and a square wave for the jingles.
- **The hi-score is not saved.** It stays until you reset the machine. Writing to the floppy disk is too risky.

## Controls

| Keyboard | Joystick, port 2 | Action |
|---|---|---|
| Cursor left / right, or A / D | Left / right | Move the ship |
| Space, Z, X, Return or Ctrl | Fire button | Fire, start the game |
| P | | Pause / resume |
| Esc | | Quit to the title screen |

## Build and run

`tools/setup-macos.sh` installs everything with Homebrew: `m68k-elf-gcc`, `m68k-elf-binutils`, FS-UAE and Pillow. The tests also need a C compiler (`cc`).

```sh
make                 # build/galaga.adf: a 880 KB floppy disk image
tools/run.sh         # build, then run it in FS-UAE
make web             # docs/galaga.adz: the same, gzipped (for the link above)
python3 tools/gen_assets.py [preview.png]   # src/assets.h: sprites, title picture, font, sound
python3 tools/make_gif.py                   # record docs/gameplay.gif (about 2 minutes)
```

To play it, run `tools/run.sh`: it starts the `.adf` in FS-UAE (`brew install --cask fs-uae-emulator`) in a window, with the AROS replacement ROM that is inside FS-UAE. (`KICKSTART=file` uses a Kickstart ROM instead. vAmiga cannot take a disk from the command line.) On a real Amiga, write the ADF to a floppy disk.

The tests run the game in vAmigaWeb in a headless browser. Install it once: `pip install playwright pillow && playwright install chromium`.

```sh
python3 tests/test_selftest.py   # the 68000 against the Mac: 4 scenarios, 3000 ticks (a number as argument: more)
python3 tests/shots.py           # screenshot tests (--update after a change you want)
```

The game plays by the rules of the arcade Galaga (40 enemies, the arcade flight paths, dive scheduler and bombs; see `../ARCADE.md`).

Debug flags (`make EXTRA_CFLAGS="-DAUTOPLAY -DHALT=900"`): `AUTOPLAY` (the game plays itself), `HALT=n` (freeze after n ticks), `TITLE_HOLD=n` (ticks of the title screen in an autoplay build), `START_STAGE=n`, `FORCECAPTURE`, `SELFTEST=n`, `PROFILE` (with `HALT`: shows the loops of the main loop and the vertical blanks for the ticks: fewer loops = a slower picture).

## Source layout

| File | Contents |
|---|---|
| `src/game.c` | `psp/game.c` built without floating point |
| `src/main.c` | The main loop (one tick for each vertical blank), input, and what the game state looks like on the screen |
| `src/video.c` | Copper list, three bitmaps, blitter sprites (drawn again only when they change), text, the star sprites, the beam, the title picture, the hud that is drawn only when it changes |
| `src/audio.c` | Paula: effects on channels 0, 1 and 3, the jingles on channel 2 |
| `src/boot.s` | The boot block: loads the game into chip RAM and starts it in supervisor mode |
| `src/hw.s` | Start-up, the vertical-blank interrupt (50 Hz), the keyboard interrupt |
| `src/assets.h` | Generated: sprites, title picture, font, sound |
| `src/libc.c`, `src/inc/` | The few C library functions `psp/game.c` needs |
| `src/selftest.h` | The scripted game and its hash (the Mac and the 68000 both run it) |
| `tools/` | `setup-macos.sh`, `run.sh` (build and run in FS-UAE), `art.py` (palette and pixel art), `gen_assets.py`, `make_adf.py` (checksum of the boot block, the disk image), `make_gif.py` |
| `tests/` | `test_selftest.py` (+ `selftest_native.c`), `shots.py` + `ref/`, `vamiga.py` (runs an ADF in vAmigaWeb) |
