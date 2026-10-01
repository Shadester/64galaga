# galaga for the Thumby Color

MicroPython game for the TinyCircuits Tiny Game Engine. `README.md` has the status, controls, build commands and the layout.
The rules are a port of `../psp/game.c` (the reference for this port; it follows the C64 game).

## Build, run, test

```sh
tools/setup-macos.sh                 # once: the desktop engine in build/ (not in git)
tools/run.sh [autoplay stage=3 ...]  # SDL window
python3 tests/test_game.py           # the rules
python3 tests/test_lockstep.py [n]   # game.py against psp/game.c, every tick, 4 scenarios (needs cc)
python3 tests/run.py [--update] [case ...]   # screenshots; look at new refs before you commit them
```

- A change in `psp/game.c` needs the same change in `Galaga/game.py`: the lockstep test shows the first tick that differs.
  `tools/gen_paths.py` makes `paths_data.py` again if the paths change.
- Generated and committed: `Galaga/paths_data.py`, `sprite_ids.py`, `*.bmp` (`tools/gen_assets.py`).
- Never push without the user's OK (global rule).

## The engine (what the docs do not say)

- **Build on macOS:** the engine tests `__unix__` (`-D__unix__=1`), `-I/opt/homebrew/include` for SDL2, `-Wno-error` for new clang.
- **Screenshots:** `engine_draw.front_fb()` is a framebuf of the frame that was drawn last. `main.py record=FILE:EVERY:COUNT`
  writes it as RGB565 (`tools/rawframes.py` reads it). Node changes show in the *next* `engine.tick()`: the dump is one
  iteration late on purpose. `screencapture` of the SDL window does not work without screen-recording permission.
- **Coordinates:** the centre of the screen is (0, 0), y grows downward. A node's position is its centre.
- **Sprite sheets:** `Sprite2DNode` animates by default: pass `playing=False` or `frame_current_x` is changed under you
  (the sprites then show the wrong cells). Pen 0 (black) is the transparent colour. Hide a node with `opacity = 0.0`.
- **Textures** are 8-bit BMPs from Pillow (`P` mode). `FontResource` needs a special bitmap: the game uses the built-in font.
- **RTTTL** sounds are loaded from a file (`RTTTLSoundResource("jingles/stage.rtttl")`), not from a string.
- **Saves:** `engine_save._init_saves_dir()` must be called before `set_location` when the game is not started by the
  launcher (the desktop run). `main.py` does that. The tests use `nosave`.
- **Speed:** the logic is kept flat (lists and ints, no allocation per tick). `view.py` changes nodes only when a value changed.

## Conventions

- Code that mirrors `game.c` keeps its names (`alien_hit`, `update_collisions`, ...). Comments explain why and are short.
- README text is written in Simplified Technical English. Keep commits small. Do not push without asking.
