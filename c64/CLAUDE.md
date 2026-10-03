# 64galaga

Galaga clone for the Commodore 64 in 6502 assembly (ACME). PAL timing. `README.md` has the
feature list, controls and the explanation of the sprite multiplexer.
The rules are the arcade's (`../ARCADE.md`) on a layout of 32 aliens: `src/arcade.asm` translates `../psp/game.c`
built with `-DRULES_ARCADE32` (the reference). Keep the names and the order of that C code, and check a change
with `python3 ../tools/compare_6502.py c64 SCENARIO` (see below).

## Build, run, test

```sh
make                      # build/galaga.prg (exomizer), build/galaga.d64, and docs/galaga.prg (committed!)
make run                  # VICE with the .d64 (WASD + Space, see .vice/vicerc)
tests/run.sh [case ...]   # screenshot tests, headless VICE (-console: no window, no focus grab)
tests/run.sh --update [case ...]   # regenerate tests/ref/*.png after an intended change
python3 tools/make_gif.py # re-record docs/gameplay.gif: title screen, then autoplay (about 5 minutes)
```

- Run `tests/run.sh` **one instance at a time**: the cases share `build/test/` and `hs.d64`.
  A full run takes about 3 minutes (too long for one foreground tool call: run it in the background).
- Every case builds with debug flags (`-DAUTOPLAY=1 -DHALT=n ...`, listed in `README.md` and
  at the top of `src/main.asm`). `HALT=n` freezes the game after n frames so the screenshot is exact.
  Frame-based cases are best **after the fly-in** (about 800 frames with an invulnerable ship, 1200 when the
  ship is hit and the entering aliens ram it): during it the picture can depend on raster timing (it was stable
  in the runs so far).
- `tests/cmp.py` allows 64 different pixels (raster jitter). `cmp.py --game` rejects a blank or
  BASIC screenshot (VICE autostart sometimes misses); `run.sh` retries, also on `--update`.
  Always look at new references before you commit them.
- `python3 ../tools/compare_6502.py c64 SCENARIO` (`list` shows them: a32_entry, a32_shoot, a32_chal, a32_dive, a32_dive2, a32_long,
  a32_play, a32_capture, a32_rescue) builds the game with `-DHALT=65535` (that only makes the loop counter `halt_cnt`), runs it
  in VICE with the binary monitor (`tools/vice.py`), stops at the label `tick_mark` after each pass of the game loop, and
  compares the state at the checkpoints with the C reference: game state, score, lives, ship, every alien (state, position,
  escort), shots and bombs. The two must be equal. `TICKS=a,b,c` sets other checkpoints, to find the first tick that differs.
  Where the C64 needs a shortcut for the CPU (shots tested every 2nd tick, half of the aliens tested for rams), the C reference
  does the same under `RULES_ARCADE32`.
- VICE needs `frames*40000+20M` cycles (`-limitcycles`) or the game may not reach its `HALT`.
- After any change to `src/`: `make` so that `docs/galaga.prg` (the browser link of the README)
  matches the source. Never push without the user's OK (global rule).

## Memory map

| Range | Content |
|-------|---------|
| `$0801` | BASIC stub, `SYS 2064` |
| `$0810-$2fff` | code and variables (`!error` guard at `$3000`) |
| `$3000-$33ff` | sprite art (`art.asm`), pointers `$c0..$cf` |
| `$3400-` | `arcade_wave.asm`, `entry.asm`, `arcade.asm` (+ `arcade_data.asm`), `hiscore.asm`, `title_font.asm` |
| `$5800-$7f3f` | title picture: colours `$5800`, screen matrix `$5c00`, bitmap `$6000` (`title.bin`) |
| `$7f40-$9fff` | the flight paths (`arcade_paths.asm`, one byte a step; guard at `$a000`) |

The title screen switches VIC to bank 1 (`$dd00`) with a multicolor bitmap; the game uses bank 0
and text mode. `leave_title` undoes it.

## Code map

`main.asm` (start-up, main loop, includes) - `states.asm` (title, intro, play, dying, captured,
game over, result) - `player.asm` (joystick, P pause, RUN/STOP quit) - `enemies.asm` /
`entry.asm` / `challenge.asm` (formation, dive steps, fly-in, challenge paths) - `arcade.asm` (the dive
scheduler, escorts and bombs; tables in the generated `arcade_data.asm`) - `combat.asm`
(collisions) - `capture.asm` (tractor beam) - `progress.asm` (score, death, stages) -
`multiplexer.asm` + `sprites.asm` (sprites) - `screen.asm` (text, HUD, stars) - `hiscore.asm`
(disk file) - `data.asm`, `constants.asm`.

Generated, committed files (do not edit by hand): `src/arcade_data.asm`, `src/arcade_wave.asm`, `src/arcade_paths.asm` and `../psp/paths32.h`
(`tools/gen_arcade.py`, from `../psp/arcade_data.h`),
`src/title.bin` and `src/title_font.asm` (`tools/gen_title.py`, from `assets/title-source.png` and
`art.asm`). The title logo picture was made with Codex (`codex exec`, image tool).

## Things that bit us

- **The game is CPU-bound in the stage-1 fly-in and in challenge stages.** A PAL frame is 19.6k
  cycles. The sort plus both interrupts take about 8k. If `irq1` runs while the game loop has not
  finished, the last frame repeats (25 fps). Before you change the multiplexer or per-frame code,
  measure late frames: temporary `-DPROFILE` patch that counts `irq1` calls with
  `spr_update_flag = 0` and shows the count once at `HALT` (draw text every frame and you skew
  the result by 10k cycles). Use CIA2 timer A (`$dd04/$dd05`, start with `$dd0e = $11`) for
  routine timing, in `sei`/`cli`. Do not commit profile code. Baseline: fly-in 7-10 late frames
  by frame 700, challenge stage about 24.
- **Multiplexer rules** (`multiplexer.asm`): a sprite loads at `max(Y - IRQ_LEAD, previous user's
  Y + ART_TAIL)`. `ART_TAIL` must be larger than the tallest art (ship: 14 lines). A sprite that
  would start while its hardware sprite is still busy is left out, alternating with the older one on
  odd frames (`VS_NONE` is a hidden slot). The ship always wins. `VS_NONE` needs the extra
  table entry after each `spr_*` table.
- **Stars write colour RAM**, so they must not run under the title picture (`main.asm` skips them).
  `twinkle_stars` animates the title stars through the screen matrix nibble.
- **Drive error LED:** a missing hi-score file leaves error 62 in the drive; a real 1541 blinks
  until a command succeeds. `hs_clear_error` sends `I0`. `UJ` (reset) freezes the bus and reading
  the error channel hangs VICE true-drive mode: do not use them.
- **Hi-score file:** `save_hiscore` switches the KERNAL interrupt back on and stops the raster
  IRQ while the serial bus is busy; `init_raster` restarts it.
- **Branch range:** ACME branches reach only 127 bytes. The `sort_copy` and `game_loop` code
  already use `jmp` around long branches; expect "Target out of range" when you add code there.
- **Shell:** run multi-flag commands from scripts. `xargs -I` with long `bash -c` strings and
  unquoted flag variables break on macOS zsh.
- **Quit:** RUN/STOP (Esc in VICE) calls `check_quit`; `-DQUITAT=n` simulates it in tests.

## Conventions

- Comments explain why, are short, and match the surrounding style. Zone names match the routine
  name (`!zone name` before `name:`), labels inside use `.local`.
- Keep commits small, with a message that says what changed and why. Do not push without asking.
- New README text is written in Simplified Technical English (ASD-STE100), like the multiplexer
  section: short sentences, active voice, one word for one meaning.
