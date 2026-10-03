# galaga for the terminal (Rust)

Rust, one crate (`crossterm`). `README.md` has the controls, options and commands.
The rules (`src/game.rs`) are a translation of `../psp/game.c` (the arcade rules, 40 aliens), with the same names and order.
A change in `psp/game.c` needs the same change in `game.rs`: `tests/test_lockstep.py` compares the state after every tick with the C reference
(it builds `../thumby/tests/c_trace.c` and runs `examples/trace.rs`) and shows the first field that differs.

## Build, run, test

```sh
cargo run --release -- --autoplay
python3 tests/test_lockstep.py 30000          # 8 scenarios, every tick equal to the C reference
python3 tests/test_terminal.py                # pseudo-terminal checks
cargo test --release
```

- The generated files are committed (`src/arcade_data.rs`, `src/art.rs`): run `tools/gen_arcade_rs.py` when `../psp/arcade_data.h` changes.
- To look at the screen without a terminal window, run the binary in a pseudo-terminal, read it with `pyte` and draw the cells (`tools/make_gif.py`
  has the code). A pseudo-terminal child that you kill must have its master closed first (`os.close(fd)`), or the kill does not end it.
- The browser version: `src/web.rs` has plain `extern "C"` exports (no wasm-bindgen), `tools/build_web.sh` builds `docs/tui/galaga.wasm` (committed), `docs/tui/index.html`
  draws the cells on a canvas. Build the library with `--no-default-features` (the feature `terminal` is `crossterm`). `tests/test_web.py` needs playwright
  (the scratchpad venv has it). The page picks the biggest cells (up to 12 x 24 CSS pixels) that still give the biggest picture (160 x 52 cells).
  After a change of the rules or the renderer: `tools/build_web.sh`, run the tests, commit `docs/tui/galaga.wasm` too.
- Never push without the user's OK (global rule).

## How it works

- 50 ticks a second (`TICK_HZ`), a fixed step in `main.rs`; the screen is drawn at most every 33 ms, and only the cells that changed are written (`term.rs`).
- The play area is 320 x 200 game pixels (C64 sprite coordinates, x 24..343, y 50..249). `render::layout` picks the scale k (2, 3 or 4 game pixels for
  a canvas pixel) that fits the window; two canvas pixels are one cell (the half block `▀`: upper = foreground, lower = background).
- Sprites are the 16 x 16 art of `psp/art.h` (the colour letters), reduced to the size of the canvas with a box filter and cached for each size.
- Keys: a terminal gives no key release without the kitty keyboard protocol. `input.rs` uses the releases when the terminal has the protocol
  (`supports_keyboard_enhancement`), else a hold time (`HOLD_FIRST`, `HOLD_REPEAT`). Fire is a pulse of one tick for each press or repeat.
- The terminal is restored on exit and on a panic (`term::restore`, the panic hook). `crossterm` asks the terminal about the keyboard protocol at
  start-up and waits for the answer: a terminal that does not answer delays the start by about 2 seconds.

## Conventions

- Comments explain why and are short. README text is in Simplified Technical English. Keep commits small. Do not push without asking.
