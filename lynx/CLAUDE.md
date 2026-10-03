# galaga for the Atari Lynx

The Atari Lynx game in 6502 assembly (ca65/ld65). It plays by the arcade rules (`../ARCADE.md`; `src/game/arc.s` translates `../psp/game.c`, the reference). It started as a port of the C64 game (`../c64`); the C64 rules are gone.
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
  to add for the boot ROM (it takes about 60: 400 is a safe margin).
- `tools/dbg.py ROM FRAMES label[:size] ...` prints memory by label. Only exported labels are in `build/galaga.lbl`:
  add a name to the `.export` line of `src/game.s` when you need one.
- `python3 ../tools/compare_6502.py lynx SCENARIO` (arc_entry, arc_shoot, arc_chal, arc_dive, arc_dive2, arc_play, arc_capture, arc_rescue) runs a scripted game in the ROM (Gearlynx) and in the C reference `psp/game.c` and compares the
  game state at checkpoints (the state is read by label: the labels it needs are exported in `src/game.s`). `list` shows the scenarios. It reads the game's
  own tick counter (`frame`), so a slow frame does not break it.
- `make clean` after you change `CAFLAGS`: the Makefile does not see them.
- Never push without the user's OK (global rule).

## Hardware facts that bit us

- **Frame time is the number of sprites (SCBs):** a frame with about 90 or more SCBs (each is a Suzy job of its own) is not finished in 20 ms: the
  loop then runs at 25 Hz. The HUD was 38 glyph sprites; it is now one 160 x 11 picture (`hud_buf`, built again only when a number changes), so a
  frame has about 60-70 SCBs and 40 aliens fit (the static 40-alien test build: 70). `-DPROFILE=1` counts late frames, the most sprites of a frame and
  the sprites that did not fit (`late_frames`, `scb_peak`, `scb_over`, read with `tools/dbg.py`). `add_sprite` drops a sprite when the SCB pool
  (`MAX_SCB`) is full.
- The arcade rules are the only rules. Their data (`src/game/arcade_data.s`) is made by
  `tools/gen_arcade.py` from `../psp/arcade_data.h`; the flight paths are a bit stream (second differences, see the generator), 5.4 KB for 62 paths.
  The aliens' positions are signed 16-bit numbers (`ax_lo/hi`, `ay_lo/hi`): `arc_sync_aliens` makes the sprite tables from them each tick. MAIN ends at about
  `$928D` (1,100 bytes less since the C64 rules and the page padding were removed): it must stay below `$A000` (the frame buffer).

- **Suzy and the CPU:** poll `SPRSYS` for "sprite engine busy" only after `stz CPUSLEEP`: the emulator advances the
  engine while the CPU sleeps. Then `stz SDONEACK`, or the next frame's sleep never ends (`frame_end`).
- **No interrupts:** the CPU keeps I set. A pending timer interrupt wakes the CPU from `CPUSLEEP` while Suzy draws
  and the engine stops. The vertical blank is polled in the timer 2 done bit (`TIM2CTLB` bit 3, `flip`).
- **Literal sprite lines lose their last pixel** in Gearlynx. Pad every line with one extra byte (`gen_art.py`).
  A line is: offset byte (count including itself), data bytes, and `0` ends the sprite.
- **Sprite sizes** are 8.8 fixed point. The screen clear is one pixel scaled to 160 x 102 (`bgscb`).
- **The loader sums the segment sizes** (`defdir.s`): padding that ld65 adds between segments is not loaded, so no
  segment may be aligned (an `align` in `lynx.cfg` would move the code that follows).
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

- `arc.s` follows `../psp/game.c`: keep its names, and check a change with `compare_6502.py`. Some other modules (`states.s`, `player.s`, `hud.s`, ...) come from the C64 game: their labels and the C64 text positions stay.
- Comments explain why, are short, and match the surrounding style. README text is in Simplified Technical English.
- Keep commits small. Do not push without asking.
