# Our rules against the arcade Galaga

The C reference (`psp/game.c`), the PSP, Amiga, Thumby Color, PICO-8 and Lynx play by the arcade rules. The old rules of the C64 game are gone from
the code. The C64 game (6502 assembly) still has them until it is rewritten (see below): 40 enemies do not fit there (8 sprites a line, the arcade
rows have 10 bees).

The C64 game (6502) cannot show the arcade's rows of 10. For it `psp/game.c` has a second layout, `-DRULES_ARCADE32`: the arcade's scheduler
(sortie timers, stage table, escorts by the wingman table), aimed bombs (at most 4, no bombs from the aliens that fly in), beam by stage,
respawn rules and challenge scoring (100 a hit, 10,000 for all 32) on the C64's layout, fly-in splines and steering dive. It is the reference
for the C64 assembly (`psp/tests/test_arcade32.c` tests it). The Lynx plays the full arcade rules with 40 aliens, checked against `psp/game.c`
by `tools/compare_6502.py`.

Status: the entry (rows 1-6), the dive scheduler, the escorts and the bombs (rows 7-11, 13-15) are in `psp/game.c` behind
`-DRULES_ARCADE`; the old rules are still the default. `tools/gen_arcade.py` makes the data (`psp/arcade_data.h`).
`tools/compare_arcade.py` checks the dives against the model: for stages 1, 2, 4, 5, 8, 9 and 12 the first 10 launches (who, with
whom) are the same, and the times differ by less than 45 frames. The formation swing and breathing (row 6), the challenge stages (17: five groups of 8 on the arcade paths, 100 for each enemy,
10,000 for all 40), the beam (12: it grows for 10 x p6 frames, takes the ship during 64 frames, and goes) and the respawn (24: the
ship comes back when nothing flies any more, and entry waves that have not started wait for it) are done too. The hit boxes (22) stay as they are: they are made for our sprite sizes
and are within a pixel or two of the arcade boxes scaled to our screen. Not done: the bonus bee (16) and the extra flyers of the stage 4+
entry waves (the model's "transients": 6 to 20 enemies that fly a path, leave and do not join the formation; they are in
`arc_w*` with slot -1). They need up to 20 more sprites, and the transformed enemies need the art in `c64/src/art_transform.asm`.
Known differences: a boss's bonus counts the escorts that are still
alive (the model fixes it when the sortie starts); a captive fighter in the formation is not modelled.

## Sources

- **Ours:** `c64/src/*.asm` (the C64 game) and `psp/game.c` (the C reference of the other ports). The two agree on the rules in this
  document (the tables are the same: `c64/src/data.asm:211-216` and `psp/game.c:90-92`).
- **Arcade:** `tomcoolpxl/cool8-cpu`, `tools/galaga_paths.py` and `tools/galaga_dives.py` (MIT licence). It is a Python model of the
  arcade program, made from the commented disassembly `hackbar/galaga`. Line references below are to `galaga_dives.py` (`dives:`) and
  `galaga_paths.py` (`paths:`). The model has no randomness in the attack phase.
- **Not checked yet:** the model has not been compared with video. Numbers marked (?) come from public descriptions, not from the model.

## Graphics and sound

All ours. We do not copy arcade sprites, fonts, pictures or sounds. We use only numbers (rules, timers, tables, flight paths).
The alien art stays the art of the C64 game (`c64/src/art.asm`).

## Rules

"Limit" = a platform may keep our rule when the hardware cannot do the arcade rule.

| # | Mechanic | Arcade | Ours | Result |
|---|----------|--------|------|--------|
| 1 | Enemies in a stage | 40: 4 bosses, 16 butterflies, 20 bees (`paths:198`, home table: boss row 4, butterfly rows 2 x 8, bee rows 2 x 10) | 32: 4 / 14 / 14 (`game.c:119`; rows 4, 7, 7, 7, 7) | **Different.** Limit on C64, Lynx. Change on Thumby, PICO-8, Amiga |
| 2 | Formation layout | 10 columns for bees, 8 for butterflies, 4 for bosses | 7 columns, 26 px apart (`game.c:72`) | Different (follows from 1) |
| 3 | Entry waves | 5 groups of 8 (`DB_ATTK_WAV_IDS`, `paths:150`); the wave table of a stage comes from `stage_row` / `build_wave_table` (`paths:1060-1130`); each group has its own path and who flies in it | 4 groups of 8 with 4 paths (A..D), launch delay per slot (`game.c:77-87`) | **Different.** Take the wave tables and paths from the model |
| 4 | Entry paths | Byte-code paths (`PATH_TABLES`, `paths:40`), run by `fly()` | 4 hand-made splines (`game.c:18-21`) | Different. Generate from the model |
| 5 | Enemy fire during the entry | Per object bit `D_2908` (`dives:94`) and by stage (`hdr1`): a few enemies may drop bombs while they fly in | None | Different. (?) Stage 1: no fire during the entry |
| 6 | Formation movement | Sway left/right while the entry runs, then "breathing" (expand/contract) (`paths:507-540`) | Sway only, +-42 px, speed by `diff` (`game.c:215-225`) | **Different.** Add breathing |
| 7 | Dive scheduler | Three timers (boss, butterfly, bee), reload from tables by stage and time (`D_08CD`, `D_08EB`, `D_0909`; `dives:50-60`, `f_1B65` `dives:424`). A sortie waits when `flying >= max bombers` | One timer, `diveInterval[diff]` (130..34 frames); 1 random alien, or a boss (`game.c:299-321`) | **Different.** Replace |
| 8 | Max divers at once | Stage 1: 2, stage 2: 2 then 3, stage 6: 3, stage 9: 3 then 4 (`attack_param_table`, p4 -> p5) | 1, 1, 2, 2, 3, 3, 4, 5 by `diff` (`game.c:91`) | **Different.** Ours starts lower and rises higher (5) |
| 9 | Difficulty steps | By stage (stages after 26 reuse the rows of stage 23..26) (`stage_parms`, `paths:1088`); 4 ranks | `diff` 1..8, +1 per combat stage | **Different.** Use the stage table |
| 10 | Boss and escorts | A boss takes 2 wingmen, 1 or 0, by who is alive (`case_bmbr_boss` `dives:466`, `j_1CAE`); the escort chosen from a table of 6 | Boss takes 2 butterflies `5+pick`, `6+pick` when the ship is captured or dual (`game.c:314-320`) | Different. Escorts also when no capture is running |
| 11 | Capture sortie | Every second boss sortie tries to capture, if no captive is in formation (`wingm & 1`, `dives:468`) | A random boss when no capture, no dual (`game.c:309,312`) | Different. Same idea |
| 12 | Beam | Starts aiming, then beam for `20 * parm6 + 65` frames; `parm6` = 12 / 9 / 6 by stage (`dives:581`) | Beam 180 ticks, grows in 4 steps (`game.c:281,368`) | Different. Use `parm6` |
| 13 | Enemy bombs | Up to 8 at a time, aimed at the ship at the drop (`_drop_bomb` `dives:388`), speed 2-3 px/frame; flags by stage and number of enemies (`D_0909`) | 3 at a time, sideways step 0 / +-1 every second tick, fixed fall speed 3 (`game.c:253-259,322-329`) | **Different.** Take the arcade bomb |
| 14 | Bombs by position | Dropped when the enemy is below y `0x4C` in the dive path (`dives:379`) | Dropped at y 100 and, if `diveShots=2`, at y 150 (`game.c:275`) | Different. In `-DRULES_ARCADE`: no bombs below y 163 (the arcade's 97 of 288 lines above the ship, scaled to 200 lines), and the sideways speed is at most 0.6 of the fall speed (`dives:402`: the model limits the rate to `0x60`) |
| 15 | Continuous bombing | When enemies left `< parm7` (6..9), bombs every 2 counts (`dives:241,726`) | None | **Missing** |
| 16 | Bonus bee ("clone attack") | From stage 4 on (`parms[10]`, `paths:1100`), not in challenge stages: after `0xC0` counts one enemy turns to a bonus colour and dives alone (`f_1A80` `dives:531`) | None | **Missing** |
| 17 | Challenge stage | Stage 3, 7, 11, ... (`(stage+1) & 3 == 0`, `paths:1074`). 5 groups of 8 on set paths (`D_CHALLG_STG_DAT`), 100 per enemy (?), 10,000 for all 40 (?) | Stage 3, 7, 11, ... 4 groups of 8, `100 * ((stage + 1) / 4)` per enemy up to 900, 10,000 for all 32 (`game.c:110-111`, `399`) | **Different:** the value per enemy (?), the count, the paths |
| 18 | Points | Bee 50 / 100, butterfly 80 / 160, boss 150 / 400 (shot in formation / diving), diving boss with 1 / 2 escorts alive 800 / 1600; captured fighter shot in a dive +1000 (`SCORE_PER_COUNT`, `D_1CFD`; `dives:70,63`) | Same (`game.c:190-194,198`) | **Same** |
| 19 | Boss hit points | The first hit turns the boss blue; the second kills it (`hit_enemy`, `dives:603`) | `hp` 2 (`game.c:121`) | **Same** |
| 20 | Bonus ships | 20,000 and 70,000, then every 70,000 (?) | Same (`game.c:102`) | Same |
| 21 | Player shots | 2 on the screen (?) | 2 per ship, 4 with dual (`game.c:168`) | Check (?) |
| 22 | Hit boxes | `rocket_hits`: dx -5..+5, dy -3..+2 (in half pixels); `fighter_touches`: dx +-6, dy -3..+3 (`dives:97-120`) | Boxes of 18 x 16 px for the shot, 16 px for the ship (`game.c:336,353`) | Different. Scale the arcade boxes |
| 23 | Rescue and dual fighter | Dual ship by rescue; the captive flies down and joins (?) | Same idea (`game.c:373-380`) | Same (?) |
| 24 | Respawn | Timer `game_tmrs[2]` + 30 ticks (max 120) after a death, enemies wait until the ship is back (`dives:689`); the stage waits with the READY text | 90 ticks "ready", 120 ticks invulnerable (`game.c:432,438`) | Different in the details |
| 25 | Speed of the machine | 60 Hz | 50 Hz (`ticks`); all our speeds are in pixels per tick | **Decision needed** (open point 1) |
| 26 | Screen | 224 x 288, portrait | C64 play area 320 x 200 landscape (`x 24..343, y 50..249`) | Limit: we scale the layout |

## Platform limits (first look; measure before you decide)

- **C64 / Lynx (6502, 8 sprites with a multiplexer):** 44 virtual sprites in total now; the fly-in already runs at 25 frames a second in places
  (`c64/README.md`). 40 enemies need 8 more sprites and more CPU. **Keep 32** until we measure. Use the arcade numbers where they cost no CPU
  (scoring, timers, number of divers, challenge value).
- **Thumby Color / PICO-8:** 40 sprites fit the screen (128 x 128). PICO-8 has a limit of 8192 tokens: the tables must be strings.
- **Amiga:** the blitter cost of a sprite is about 0.85 ms (`amiga/CLAUDE.md`). 8 more sprites add 7 ms to the worst frames. Do the copper
  scroll first (`amiga/PLAN-scroll.md`) or accept a lower frame rate in the sway.

## Open points

1. **Tick rate (decided).** All ports run the rules at 50 ticks a second (C64 and Amiga are PAL; Thumby, PICO-8 and Lynx also use 50). The
   arcade runs at 60 Hz. The generator resamples paths to 50 ticks and converts launch times by 5/6. Timers of the dive scheduler
   count arcade frames: step 3 runs them on a 60 Hz clock inside the 50 Hz tick, so they stay equal to the model.
2. **Difficulty rank (decided).** The arcade has 4 settings from easy to hard. We use rank 3, the normal one.
3. **Quality of the model.** It is built from a disassembly, not from play. Before step 3, play-check the first stages against video.
4. **Layout of 40 on 320 x 200 (decided in `tools/gen_arcade.py`).** X is scaled by 320 / 224. Y is bent (`warp_y`) so the five rows are
   28 px apart; paths follow the same bend, so they still end at the slots. The columns are 23 px apart (sprites 24 px): tight. The
   existing sway of +-42 px fits (x 27 .. 341 of 24 .. 343).
5. **The data licence.** The tables come from the arcade ROM. You decided to allow this for paths and wave data. The generator and
   the attribution stay in the repo; the ROM and the disassembly do not.
