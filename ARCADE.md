# Our rules against the arcade Galaga

The C reference (`psp/game.c`), the PSP, Amiga, Thumby Color, PICO-8 and Lynx play by the arcade rules, with 40 aliens. The C64 game (6502) plays them
too, but on its own layout of 32 aliens: it cannot show the arcade's rows of 10 (8 sprites a line).

For the C64 `psp/game.c` has a second layout, `-DRULES_ARCADE32`: the arcade's scheduler (sortie timers, stage table, escorts by the wingman
table), aimed bombs (at most 4, no bombs from the aliens that fly in), beam by stage, respawn rules and challenge scoring (100 a hit, 10,000 for
all 32) on the C64's layout, fly-in paths (`psp/paths32.h`, made by `c64/tools/gen_paths.py`), sideways swing and steering dive. Where the 6502 needs
a shortcut (a shot is tested every 2nd tick, half of the aliens are tested for rams, the fly-in delays count in steps of 2 ticks) the C code does
the same under this switch. It is the reference of the C64 assembly (`c64/src/arcade.asm`): `tools/compare_6502.py c64` runs both and compares the
state at checkpoints; `psp/tests/test_arcade32.c` tests the C code. The Lynx plays the full arcade rules with 40 aliens, checked against
`psp/game.c` the same way.

Status: the rules of the table below are in `psp/game.c` (the default; the C64 layout is `-DRULES_ARCADE32`) and in all ports. `tools/gen_arcade.py` makes the data (`psp/arcade_data.h`).
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

- **Ours:** `psp/game.c` (the C reference) and the ports, which follow it (the 6502 games are checked against it by `tools/compare_6502.py`).
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
| 1 | Enemies in a stage | 40: 4 bosses, 16 butterflies, 20 bees (`paths:198`, home table: boss row 4, butterfly rows 2 x 8, bee rows 2 x 10) | 40 on all ports but the C64; 32 on the C64 (4 / 14 / 14; rows 4, 7, 7, 7, 7) | **Same**, except on the C64 (limit: 8 sprites a line) |
| 2 | Formation layout | 10 columns for bees, 8 for butterflies, 4 for bosses | The arcade's slots scaled to our screen (`arc_slot`); 7 columns, 26 px apart on the C64 | Same (C64: follows from 1) |
| 3 | Entry waves | 5 groups of 8 (`DB_ATTK_WAV_IDS`, `paths:150`); the wave table of a stage comes from `stage_row` / `build_wave_table` (`paths:1060-1130`); each group has its own path and who flies in it | The model's wave tables (`arc_row`, `arc_w*`), 5 groups of 8; on the C64 4 groups of 8 with a delay per slot | **Same**, except on the C64 (limit) |
| 4 | Entry paths | Byte-code paths (`PATH_TABLES`, `paths:40`), run by `fly()` | Generated from the model (`arc_path`, `tools/gen_arcade.py`); the C64 has 4 own splines (`c64/tools/gen_paths.py`) | **Same**, except on the C64 (limit: memory) |
| 5 | Enemy fire during the entry | Per object bit `D_2908` (`dives:94`) and by stage (`hdr1`): a few enemies may drop bombs while they fly in | A few enemies drop bombs as they fly in (`arc_entry_bomb`, `hdr1`); none on the C64 | **Same**, except on the C64 (limit: sprites, CPU). (?) stage 1: no fire |
| 6 | Formation movement | Sway left/right while the entry runs, then "breathing" (expand/contract) (`paths:507-540`) | Sway while the entry runs, then breathing (`arc_breath`); on the C64 a sway of +-42 px | **Same**, except on the C64 |
| 7 | Dive scheduler | Three timers (boss, butterfly, bee), reload from tables by stage and time (`D_08CD`, `D_08EB`, `D_0909`; `dives:50-60`, `f_1B65` `dives:424`). A sortie waits when `flying >= max bombers` | Three timers, tables by stage and time, a sortie waits when `flying >= max bombers` (`arc_frame`), on the arcade's 60 Hz clock (6 frames for every 5 ticks) | **Same** |
| 8 | Max divers at once | Stage 1: 2, stage 2: 2 then 3, stage 6: 3, stage 9: 3 then 4 (`attack_param_table`, p4 -> p5) | From the stage table (p4, p5) | **Same** |
| 9 | Difficulty steps | By stage (stages after 26 reuse the rows of stage 23..26) (`stage_parms`, `paths:1088`); 4 ranks | The stage table (stage 27 on repeats 23..26). `diff` only sets the sway speed and the dive speed of the C64 layout | **Same** |
| 10 | Boss and escorts | A boss takes 2 wingmen, 1 or 0, by who is alive (`case_bmbr_boss` `dives:466`, `j_1CAE`); the escort chosen from a table of 6 | The wingman table (`arc_sortie_boss`; on the C64 the right six butterflies of the upper row) | **Same** |
| 11 | Capture sortie | Every second boss sortie tries to capture, if no captive is in formation (`wingm & 1`, `dives:468`) | Every second boss sortie tries to capture if no captive is in formation and the ship is not dual | **Same** |
| 12 | Beam | Starts aiming, then beam for `20 * parm6 + 65` frames; `parm6` = 12 / 9 / 6 by stage (`dives:581`) | Grows for 10 x p6 frames, holds 53 ticks (the ship is taken), shrinks; p6 = 12 / 9 / 6 / 3 by stage | **Same** |
| 13 | Enemy bombs | Up to 8 at a time, aimed at the ship at the drop (`_drop_bomb` `dives:388`), speed 2-3 px/frame; flags by stage and number of enemies (`D_0909`) | Up to 8 (4 on the C64), aimed at the ship at the drop, fall 2-3 px a tick, flags by stage and number of enemies | **Same**, except the number on the C64 (limit) |
| 14 | Bombs by position | Dropped when the enemy is below y `0x4C` in the dive path (`dives:379`) | No bombs below y 163 (the arcade's 97 of 288 lines above the ship, scaled to 200 lines); the sideways speed is at most 0.6 of the fall speed (`dives:402`: the model limits the rate to `0x60`) | **Same** (scaled) |
| 15 | Continuous bombing | When enemies left `< parm7` (6..9), bombs every 2 counts (`dives:241,726`) | When enemies left `< p7`, bombs every 2 counts | **Same** |
| 16 | Bonus bee ("clone attack") | From stage 4 on (`parms[10]`, `paths:1100`), not in challenge stages: after `0xC0` counts one enemy turns to a bonus colour and dives alone (`f_1A80` `dives:531`) | None | **Missing** |
| 17 | Challenge stage | Stage 3, 7, 11, ... (`(stage+1) & 3 == 0`, `paths:1074`). 5 groups of 8 on set paths (`D_CHALLG_STG_DAT`), 100 per enemy (?), 10,000 for all 40 (?) | Stage 3, 7, 11, ... 5 groups of 8 on the arcade paths (4 groups of 8 on the C64), 100 for each enemy, 10,000 for all | **Same** (?: the values come from public descriptions), except the groups on the C64 |
| 18 | Points | Bee 50 / 100, butterfly 80 / 160, boss 150 / 400 (shot in formation / diving), diving boss with 1 / 2 escorts alive 800 / 1600; captured fighter shot in a dive +1000 (`SCORE_PER_COUNT`, `D_1CFD`; `dives:70,63`) | Same | **Same** |
| 19 | Boss hit points | The first hit turns the boss blue; the second kills it (`hit_enemy`, `dives:603`) | `hp` 2 | **Same** |
| 20 | Bonus ships | 20,000 and 70,000, then every 70,000 (?) | Same | Same |
| 21 | Player shots | 2 on the screen (?) | 2 per ship, 4 with dual | Check (?) |
| 22 | Hit boxes | `rocket_hits`: dx -5..+5, dy -3..+2 (in half pixels); `fighter_touches`: dx +-6, dy -3..+3 (`dives:97-120`) | Boxes of 18 x 16 px for the shot, 16 px for the ship; within a pixel or two of the arcade boxes scaled to our screen | Different on purpose: they are made for our sprite sizes |
| 23 | Rescue and dual fighter | Dual ship by rescue; the captive flies down and joins (?) | The captive flies down and joins | Same (?) |
| 24 | Respawn | Timer `game_tmrs[2]` + 30 ticks (max 120) after a death, enemies wait until the ship is back (`dives:689`); the stage waits with the READY text | 107 ticks dead, then READY until nothing flies (80 ticks), sorties restart slowly (`tmr2 + 30`, max 120), entry waves that have not started wait | **Same** |
| 25 | Speed of the machine | 60 Hz | 50 Hz (`ticks`); all our speeds are in pixels per tick | **Decision needed** (open point 1) |
| 26 | Screen | 224 x 288, portrait | C64 play area 320 x 200 landscape (`x 24..343, y 50..249`) | Limit: we scale the layout |

## Platform limits (first look; measure before you decide)

- **C64 (6502, 8 sprites with a multiplexer):** 44 virtual sprites in total; the fly-in already runs at 25 frames a second in places
  (`c64/README.md`). 40 enemies need rows of 10 sprites, and the VIC-II draws 8 in a line. **Keep 32**; the arcade numbers are used wherever
  they cost no CPU. The **Lynx** (Suzy draws a chain of sprites, no limit of 8) plays 40 (`lynx/CLAUDE.md`).
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
