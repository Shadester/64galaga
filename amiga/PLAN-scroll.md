# Amiga: no cost for the formation sway (copper scroll) + assembly for the hot loops

## Context
The Amiga port (`amiga/`, pushed as `406c598`) runs the game at full speed but draws about 20 pictures a second in busy scenes. The worst
frame is the formation sway: every 9 ticks the 28 formation aliens move 3 pixels together, and 28 clears + 28 blits take about 34 ms.
User decisions: make the sway cheap with a **copper scroll** (the formation stays still in the bitmap; the display of the lines is shifted),
and use **assembly** for text drawing, the sprite bookkeeping and the alien draw loop (the 68000 does about 0.5 MIPS here).
The rules (`psp/game.c`) and the rule tests stay as they are.

## 1. Display: a scrolled playfield below the hud (`amiga/src/video.c`, `video.h`)
- Everything below the hud (`y >= TOP` = 28) is shown scrolled by `D` = `formDx` (-42..+42 pixels); the hud (lines 0..27) is not.
  Because every object is clipped at `TOP` anyway, **no sprite straddles the boundary**, so all sprites are drawn at `x - D` and nothing is split.
  A formation alien is at screen `slot_x + D`, so its bitmap x is the constant `slot_x`: it is not drawn again when the formation sways.
- Bitmap: guard 64 pixels each side (`GUARD 64`, `STRIDE 56`, `ROWB 280`): the shifted view and the sprites near the edges need it.
- Fetch: `DDFSTRT 0x30` (one word earlier), `DDFSTOP 0xd0`, `BPLxMOD = ROWB - 42`. For a shift `D`: fine scroll `f = D & 15` in `BPLCON1`
  (both nibbles), bitplane pointers at `base - 2 * (1 + (D >> 4))` bytes (floor). The exact offsets are **calibrated in the emulator** first
  (a test pattern, like the sprite `HSTART` calibration).
- One copper list for each of the 3 bitmaps, built in `video_end`: the header sets pointers and `BPLCON1` for the hud lines, then
  `WAIT` (line `TOP - 1`, horizontal position `0xd9`, in the horizontal blank) and the 10 pointer `MOVE`s + `BPLCON1` for the scrolled lines.
  `COP1LC` is written (one 32-bit write) when the line is between 8 and 300, so a half-written list is never read.
- API: `video_scroll(D)` in `video_begin` / `video_end`; text and the beam (`text_now`, `beam_now`) draw at `x - D`; `video_static_*` (hud) does not.
- The lives icons move from the bottom strip to the top hud (an icon and a number, right of the stage), because the bottom is scrolled.
  Remove the bottom strip clears (`video_static_begin`, `video_title`).

## 2. Assembly (`amiga/src/fast.s`, GNU as, called from C)
- **Text:** `gen_assets.py` makes a table of finished 8 x 9 cells for every character in each text colour (white, red, cyan): 5 planes, glyph +
  shadow already in (the shadow stays inside the 8-pixel cell). `text_now` becomes a loop of `move.b` stores in asm (about 0.15 ms a character
  instead of 1 ms). A cell replaces the pixels under it: texts are not drawn over sprites.
- **Sprite bookkeeping:** the per-slot change check (`want` against `drawn`), the cell marking / test, and the clear / blit loop of
  `draw_sprites` in asm, with the sprite table and the blitter base address in registers.
- **Alien draw loop:** `main.c draw()` turns 32 aliens into sprite requests (about 9 ms in C): an asm routine reads the `Alien` array of
  `psp/game.h` (offsets from `offsetof`, checked by a compile-time assert) and writes `want[]`.
- C versions stay (`-DNOASM`) as the reference: the tests build both and the pictures must be identical.

## 3. Tests and checks
- **Calibration (once):** a build that draws vertical lines every 16 pixels, shows them with `D` = 0, 1, 15, 16, 17, -1, -16, 42, -42: the lines must
  stay straight, and the left / right edges must be black.
- **Regression:** build the commit `406c598` (git worktree) and the new code, same `HALT` ticks (14 values, all scenarios): the pictures must be
  the same except the lives (move them to the same place with a flag, or mask the lives area). This proves the compensation (`x - D`) and the scroll.
- **Skip logic:** `-DNOSKIP` against the normal build at many ticks (existing `cmp` method), also with `-DNOASM`.
- `tests/test_selftest.py` (rules, unchanged), `tests/shots.py --update` and look at all references.
- **Speed:** `-DPROFILE -DHALT=900 -DAUTOPLAY -DTITLE_HOLD=0` (`LOOPS n Vm`): now about 345 loops; the goal is clearly more (fewer
  stumbles at the sway). Also real-time screenshots for flicker (many shots in a row, the digit trick used before).
- Re-record the GIF, `make web`; update `README.md`, `CLAUDE.md` (copper scroll, calibration numbers, asm files, lives at the top).
- Show the result before any commit (the user's rule); no push without asking.

## Risks
- The scroll formula and the copper timing are subtle: calibrate in the emulator (vAmiga is cycle-exact) before building on it. Fallback:
  the blitter copy of the formation rows (about 12 ms) with the same `video_scroll`-free design.
- Real hardware is untested: the horizontal blank has enough room for 11 copper `MOVE`s, but this is only checked in emulators.
- Assembly is harder to read: keep it small, commented, with the C version beside it, and tested for identical output.
