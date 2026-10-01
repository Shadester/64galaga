# galaga for the Atari Lynx

Port of the C64 game (`../c64`, the reference for the rules) to the Atari Lynx in 6502 assembly (ca65/ld65).
`README.md` has the features, controls, build commands, debug flags and the source layout.

## Build, run, test

```sh
make                      # build/galaga.lnx (needs cc65: tools/setup-macos.sh)
make run                  # Gearlynx window (tools/run.sh sets BiosPath in Gearlynx's config.ini)
tests/run.py [case ...]   # screenshot tests, headless Gearlynx, 4 cases at a time (about 4 minutes)
tests/run.py --update [case ...]   # regenerate tests/ref/*.png after an intended change; look at them first
python3 tools/make_gif.py # re-record docs/gameplay.gif
```

- The boot ROM must be in `lynxboot.img` (git-ignored, copyrighted). `LYNX_BIOS` overrides the path.
- Every test case builds with `-D HALT=n`: the game freezes after n frames, so the screenshot is exact. Gearlynx is
  deterministic, the compare allows 8 different pixels. `BOOT` in `tests/run.py` is the number of emulated frames
  before the game starts (about 150: 400 is a safe margin).
- `tools/dbg.py ROM FRAMES label[:size] ...` prints memory by label. Only exported labels are in `build/galaga.lbl`:
  add a name to the `.export` line of `src/game.s` when you need one.
- `make clean` after you change `CAFLAGS`: the Makefile does not see them.
- Never push without the user's OK (global rule).

## Hardware facts that bit us

- **Suzy and the CPU:** poll `SPRSYS` for "sprite engine busy" only after `stz CPUSLEEP`: the emulator advances the
  engine while the CPU sleeps. Then `stz SDONEACK`, or the next frame's sleep never ends (`frame_end`).
- **No interrupts:** the CPU keeps I set. A pending timer interrupt wakes the CPU from `CPUSLEEP` while Suzy draws
  and the engine stops. The vertical blank is polled in the timer 2 done bit (`TIM2CTLB` bit 3, `flip`).
- **Literal sprite lines lose their last pixel** in Gearlynx. Pad every line with one extra byte (`gen_art.py`).
  A line is: offset byte (count including itself), data bytes, and `0` ends the sprite.
- **Sprite sizes** are 8.8 fixed point. The screen clear is one pixel scaled to 160 x 102 (`bgscb`).
- **The loader sums the segment sizes** (`defdir.s`): padding that ld65 adds between segments is not loaded. The
  flight path tables need a page-aligned start, so `STARTUP` is padded to a page in `start.s` (`align` in
  `lynx.cfg`) and `.align 256` sits inside `CODE`.
- **Coordinates:** the game keeps C64 values. `view.s` turns them into screen pixels: `(x - 24) / 2`, `(y - 50) / 2`
  as signed 16-bit numbers. A sprite is drawn at that position plus its crop offset (`sprite_dx`, `sprite_dy`).
- **Messages** replace C64 screen RAM text: `print msg, SCREEN_RAM+row*40+col, colour` (a macro in `game.s`) adds one.
  `clear_stage_row` and `clear_result` remove the messages of those C64 rows. Numbers go through the `num_*` buffers.
- **EEPROM:** cc65's `lynx_eeread_93c46` / `lynx_eewrite_93c46` from `lynx.lib` with stubs for `popax` and `ptr1`.
  The `.lnx` header (`header.s`) says 93C46. Gearlynx saves it to `galaga.sav` on a clean exit. A read of that file
  at the next start did not work in the headless test run: not verified.
- **Sound:** a voice makes a square wave with `FEED = $80`: Hz = 41667 / (reload + 1). The jingle notes are the C64's
  SID words, converted by the `jnote` macro. Not heard, only checked in the register dump.

## Conventions

- The modules in `src/game/` are the C64 modules with ACME syntax turned into ca65 syntax. Keep the C64 labels and
  comments, so a change in the C64 code can be carried over.
- Comments explain why, are short, and match the surrounding style. README text is in Simplified Technical English.
- Keep commits small. Do not push without asking.
