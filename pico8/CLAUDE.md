# galaga for PICO-8

Lua cart. `README.md` has the status, controls, commands and the layout.
The rules are a port of `../thumby/Galaga/game.py`, which ports `../psp/game.c` (the reference; it follows the C64 game).

## Build, run, test

```sh
python3 tools/gen_assets.py          # galaga.p8 (sprites, title, sound); run it after you change the art or the sound
python3 tests/test_lockstep.py [n] [scenario ...]   # game.lua in headless PICO-8 against psp/game.c: 6 scenarios with the arcade rules (the default), 4 (c64-*) with the C64 rules
python3 tools/gen_arcade_p8.py       # arcade_data.lua and tests/trace.p8 from psp/arcade_data.h (run it, then tools/gen_assets.py, when the arcade data change)
pico8 -windowed 1 -run galaga.p8 -p "autoplay stage=3"
```

- A change in `psp/game.c` needs the same change in `game.lua` (and in `thumby/Galaga/game.py`): the lockstep test shows the first tick that differs. The arcade rules are the default (`arcade=true` in `game.lua`), the C64 rules are the start argument `c64`.
- Generated and committed: `galaga.p8`, `galaga.p8.png`, `paths.lua`, `arcade_data.lua`, `tests/trace.p8`.
- Never push without the user's OK (global rule).

## PICO-8 (what the manual does not say)

- **0 is true.** Flags in `game.lua` are booleans. Compare counters (`invuln>0`), never test them.
- **`>>`, `<<`, `&` work on the raw 16.16 bits.** For integers use `\` (floor division) instead of `>>`. `&` with small integers is fine (`i&7`). `n>>16` makes the number whose raw bits are `n`: that is how score, hi-score and the RNG hold 32-bit values. Bit operators bind tighter than `==`, as in Lua 5.3.
- **No `instr`, no `timeout` on macOS.** `pico8 -x cart.p8 -p "args"` runs a cart headless: `printh` goes to stdout, and the first stdout line is `RUNNING: ...`. Read the arguments with `split(stat(6)," ")`.
- **Token limit:** `pico8 -export x.p8.png galaga.p8` fails above 8192 tokens. Data goes in strings (`paths.lua`, `arcade_data.lua`) and the sheet. `python3 tools/p8_tokens.py game.lua main.lua paths.lua arcade_data.lua` counts them (about 7000 now).
- **Code size:** the export also fails ("could not compress code") when the compressed code is too big. The arcade flight paths (19000 steps) are a bit stream in the free map (0x2000..) and sprite sheet rows 24..63 (0x600..), read by `rb` / `rv` in `game.lua`.
- **A bit counter passes 32767:** numbers are 16.16: an integer above 32767 wraps. `rb` counts the byte and the bit apart. The same for any counter that can pass this (a bit position in a 5000 byte blob did).
- **`#include` in an included file is not processed:** `tests/trace.p8` lists every file; `trace.lua` has no `#include`.
- **Screenshots and GIFs:** `extcmd("screen")` and `extcmd("video")` write to `~/Desktop` (not to `-home`), and `extcmd("shutdown")` does not close a windowed run: kill the process after the file is there. The window is full screen unless `windowed 1` is in the `config.txt` of the home folder. Run the cart from its own folder.
- **Sheet:** gfx rows 64..127 hold the title picture; rows 24..63 and the map hold the arcade flight paths. Pen 0 is transparent. Print lower case text: it shows as capitals.
- **Sound:** pitch 0..63 (C-0 .. D#-5), so the jingles are one octave below the RTTTL files. Channels: 0 shoot / hit, 1 explosions, 2 jingles, 3 swoop and beam hum.

## Conventions

- Code that mirrors `game.c` keeps its names (`alien_hit`, `update_collisions`, ...). Comments explain why and are short.
- README text is written in Simplified Technical English. Keep commits small. Do not push without asking.
