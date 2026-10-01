# Galaga for the Thumby Color

A port of the Galaga clone to the [Thumby Color](https://tinycircuits.com/products/thumby-color) (TinyCircuits): a small handheld with a 128 x 128 colour screen and a MicroPython game engine. The game is written in MicroPython for the [Tiny Game Engine](https://github.com/TinyCircuits/TinyCircuits-Tiny-Game-Engine).

![Gameplay: the title screen, then the autoplay build with stage intro, fly-in and a tractor beam](docs/gameplay.gif)

The rules are the rules of the PSP game (`../psp/game.c`, which follows the C64 game): `Galaga/game.py` is a line-by-line port, and a test runs both versions side by side and compares the whole game state after every tick.

## Status

- It runs and plays in the desktop version of the engine (macOS). The screenshot tests pass.
- **Not tried on a real Thumby Color yet.** The speed (the Python logic takes about 30 microseconds a tick on a Mac) and the sound (tones and RTTTL jingles, not heard yet) need a check on the device.

## Features

The same features as the other versions: 32-alien formation with fly-in waves and dives, bosses that take two hits, tractor beam capture, rescue and dual fighter, challenge stages with a 10,000 bonus, a shots / hits / ratio screen after each stage, bonus ships, title picture, jingles and sound effects, and the hi-score (saved with `engine_save`).

What is different:

- The screen is 128 x 128. The game keeps the C64 coordinates, and the picture is stretched to fill the square screen: x by 0.4, y by 0.56. The sprites are not stretched. They are 10 x 10 pixels, made from the C64 art by `tools/gen_assets.py`.
- The HUD (score, lives, hi-score, stage) is in the top 14 rows.
- The engine draws with nodes. `Galaga/view.py` decides what is on the screen, and `Galaga/main.py` only moves the nodes.

## Controls

| Thumby Color | Desktop | Action |
|---|---|---|
| LEFT / RIGHT | A / D | Move the ship |
| A or B | . or , | Fire, start the game |
| MENU | Return | Pause / resume (on the title screen: leave the game) |
| LB | Left Shift | Quit to the title screen (a new hi-score is kept) |

## Build and run

On macOS, `tools/setup-macos.sh` builds the desktop engine (TinyCircuits' MicroPython fork with the engine, and SDL2). It needs Homebrew and takes a few minutes. The engine is made for Linux. The script adds three flags for macOS (`-D__unix__=1`, the SDL paths, `-Wno-error`).

```sh
tools/setup-macos.sh     # once: builds build/mp-thumby/ports/unix/build-standard/micropython
tools/run.sh             # play in an SDL window; extra arguments: autoplay, stage=3, ... (see Galaga/main.py)
python3 tests/run.py     # screenshot tests (the desktop engine runs the game and grabs the screen)
python3 tests/test_game.py && python3 tests/test_lockstep.py   # rules; and the Python port against psp/game.c
python3 tools/make_gif.py   # record docs/gameplay.gif
```

### On the Thumby Color

Connect the device with USB and run `tools/install.sh` (it needs `mpremote`: `pip install mpremote`). The game goes to `/Games/Galaga`. You can also copy the `Galaga` folder with the [Code Editor](https://color.thumby.us/code/) or Thonny. Then choose Galaga in the launcher.

## Source layout

| File | Contents |
|---|---|
| `Galaga/game.py` | The rules: a port of `psp/game.c`. No engine imports |
| `Galaga/view.py` | What is on the screen: sprite slots, beam strips, stars, texts |
| `Galaga/main.py` | The engine part: nodes, input, main loop at 50 ticks a second, debug arguments |
| `Galaga/sfx.py` | Sound: tones and the jingles (`jingles/*.rtttl`) |
| `Galaga/paths_data.py`, `sprite_ids.py`, `*.bmp` | Generated: flight paths, sprite sheet, beam, title, icon |
| `tools/gen_paths.py` | Makes `paths_data.py` by running the path builder of `psp/game.c` |
| `tools/gen_assets.py` | Makes the pictures from `../c64/src/art.asm` and `assets/title-source.png` |
| `tools/rawframes.py`, `make_gif.py` | Frame dumps of the engine as images; the GIF |
| `tests/` | `test_game.py` (rules), `test_lockstep.py` + `c_trace.c` (against the C code), `run.py` + `ref/` (screenshots), `mp_check.py` (MicroPython gives the same results as CPython) |

The engine is GPL-3.0. The game only uses its Python API. No engine code or art is copied into this repository.
