# Galaga for the Atari Lynx

A Galaga clone for the Atari Lynx, written in 6502 assembly ([ca65](https://cc65.github.io/), from the cc65 suite). It started as a port of the C64 clone in [`../c64`](../c64); it now plays by the rules of the arcade Galaga.

[**▶ Play it in your browser**](https://shadester.github.io/galagas/lynx/) (EmulatorJS; it needs no boot ROM)

![Gameplay: the title screen, then the autoplay build with stage intro, fly-in and a tractor beam](docs/gameplay.gif)

The rules are the rules of the arcade Galaga (see [`../ARCADE.md`](../ARCADE.md)): 40 aliens, the arcade flight paths, dive scheduler and bombs, a formation that swings and breathes, and challenge stages of five waves. They are a translation of `../psp/game.c`: `../tools/compare_6502.py` runs the same game in the ROM and in that C code and compares the state at checkpoints. The game runs in C64 sprite coordinates (x 24..343, y 50..249) at 50 ticks a second. The Lynx screen is 160 x 102 pixels, so the picture is the C64 picture at half size.

## Features

- 40-alien formation (4 bosses, 16 butterflies, 20 bees), fly-in waves on the arcade paths, dives with escorts, aimed bombs, bosses that take two hits
- Tractor beam capture, rescue of the captive, dual fighter
- Challenge stages (3, 7, 11, ...): five waves, 100 points a hit, 10,000 for a perfect clear
- Shots / hits / ratio screen, bonus ships at 20,000 and 70,000, game over
- Title picture, starfield, jingles and sound effects (the four Mikey voices)
- The hi-score is saved in the cartridge EEPROM (93C46)

What is different:

- An alien is 12 x 11 pixels. One pixel of the C64 sprite art is one pixel on the Lynx. The art is made from `../c64/src/art.asm` by `tools/gen_art.py`. The ship is new.
- There is no sprite multiplexer. The Suzy chip draws a chain of sprites, with no limit of 8. The game builds the chain again in every frame (`src/render.s`).
- The text is drawn with sprites (a 3 x 5 font). A message is a string with a position, in a short list. It stays on the screen until the game clears it.
- The tractor beam is drawn with checkerboard sprites. The C64 uses characters.

## Build and run

On macOS, `tools/setup-macos.sh` installs the tools with Homebrew: cc65 and the [Gearlynx](https://github.com/drhelius/Gearlynx) emulator. Python with Pillow is for the generators and the tests.

The emulator needs the Lynx boot ROM. It is copyrighted: you must dump it from your own Lynx. Put it in `lynx/lynxboot.img` (512 bytes, md5 `fcd403db69f54290b51035d82f835e7b`). Git ignores this file.

```sh
make               # build/galaga.lnx
make run           # build and start it in Gearlynx (tools/run.sh)
tests/run.py       # screenshot tests, headless Gearlynx; --update after an intended change
python3 tools/make_gif.py   # record docs/gameplay.gif
```

The web page is `../docs/lynx/index.html`, and the ROM there (`../docs/lynx/galaga.lnx`) is a copy of `build/galaga.lnx`: copy it again after a change. The `.lnx` file also runs in other Lynx emulators and on a Lynx with a flash cartridge. The hi-score is in the 93C46 EEPROM. Gearlynx writes it to `galaga.sav` when it exits.

## Controls

| Control | Action |
|---------|--------|
| D-pad left / right | Move the ship |
| A or B | Fire, start the game |
| Pause | Pause / resume |
| Option 1 | Quit to the title screen (a new hi-score is kept) |

## Tools

| Tool | Purpose |
|------|---------|
| `tools/gen_art.py` | Makes `src/art.s`, `src/art.inc` (the sprites) and `src/font.s` (the font). `--preview out.png` writes a picture of the sprites |
| `tools/gen_title.py` | Makes `src/title.s`: the title picture, from `assets/title-source.png` |
| `tools/gearlynx.py` | Runs a ROM in headless Gearlynx (its MCP server): steps frames, presses buttons, takes screenshots |
| `tools/dbg.py` | Prints the program counter and the values of labels after N frames |
| `tools/make_gif.py` | Records `docs/gameplay.gif` |
| `tools/run.sh`, `tools/setup-macos.sh` | Start the game in Gearlynx; install the tools |

The generated files are in the repository. You only run the generators when you change the art or the title picture.

## Debug build flags

Pass them to ca65: `make CAFLAGS="-D AUTOPLAY=1 -D HALT=300"`. 

| Flag | Effect |
|------|--------|
| `AUTOPLAY` | Synthetic input: sweeps left and right and fires |
| `NOFIRE` | With `AUTOPLAY`: no shooting during play |
| `HALT=n` | Freeze after n frames, so a screenshot is exact (used by the tests) |
| `HALTOVER` | Freeze on the game over screen |
| `PAUSEAT=n`, `QUITAT=n`, `DIEAT=n` | With `HALT`: press pause / quit, or hit the ship, at frame n |
| `LIVES=n`, `DIFF=n`, `STAGE=n`, `DUAL` | Start with n lives, at difficulty n, at stage n, with a dual fighter |
| `CAPTURE`, `FORCEPERFECT` | Test helpers: a scripted capture, a perfect challenge stage |
| `PROFILE` | Count late frames, the most sprites in a frame and the sprites that did not fit (labels `late_frames`, `scb_peak`, `scb_over`) |
| `GODMODE`, `GODBEAM`, `NODIVE` | Test helpers of `../tools/compare_6502.py`: the ship cannot be hit (GODBEAM: only by the beam), no sorties |

## Source layout

`src/game.s` is one translation unit. It includes the game modules from `src/game/`. The other files are separate objects.

| File | Contents |
|------|----------|
| `src/start.s`, `src/header.s` | Boot entry and the `.lnx` header (with the EEPROM type) |
| `src/render.s` | Palette, 50 Hz timing, the sprite chain, the buffer flip |
| `src/game.s` | Zero page, macros, main loop, state dispatch |
| `src/game/data.s` | Variables and tables |
| `src/game/states.s`, `player.s`, `progress.s`, `hud.s` | The game states, the ship, scoring, the HUD |
| `src/game/arc.s`, `arcade_data.s` | The arcade rules (`arcade_data.s` is made by `tools/gen_arcade.py` from `../psp/arcade_data.h`; the flight paths are a bit stream) |
| `src/game/challenge.s`, `capture.s` | The challenge result screen; the rescued ship's flight (the rest of both is in `arc.s`) |
| `src/game/sprites.s`, `view.s` | The virtual sprite tables, and drawing them (and the beam) |
| `src/game/hud.s` | Messages, HUD, starfield |
| `src/game/sound.s`, `hiscore.s` | Mikey voices; EEPROM |
| `src/art.s`, `src/font.s`, `src/title.s` | Generated data |
