# 64galaga

A Galaga clone for the Commodore 64, written in 6502 assembly ([ACME](https://sourceforge.net/projects/acme-crossass/)).

![Gameplay screenshot](docs/screenshot.png)

## Features

- 32-alien formation in 5 rows: 4 bosses, 14 butterflies, 14 bees, with wing-flap animation
- Aliens dive out of formation, steer towards you and fire back
- **Tractor beam capture:** a boss can capture your ship. Shoot that boss while it dives to free the ship and fly a **dual fighter** with double firepower. Shoot it while it is still in formation and the captive is lost
- Bosses take two hits
- Arcade scoring: 50/100 (bee), 80/160 (butterfly), 150/400 (boss, formation/diving), 1,000 for a rescue
- Bonus ship at 20,000 and 70,000 points, then every 70,000
- Stage intro, respawn invulnerability, title screen, hi-score, game over
- Scrolling starfield, jingles and sound effects (SID)
- Raster interrupt sprite multiplexer: up to 44 virtual sprites on the 8 hardware sprites, with a hires player ship among multicolor sprites

## Build and run

Requires [ACME](https://sourceforge.net/projects/acme-crossass/) and the [VICE](https://vice-emu.sourceforge.io/) emulator (`x64sc`).

```sh
make          # builds build/galaga.prg
make run      # builds and starts it in VICE
```

The `.prg` also runs on real hardware (`LOAD"*",8,1` then `RUN`).

## Controls

| Key | Action |
|-----|--------|
| A / D | Move left / right |
| Space | Fire, start the game |

A joystick in port 2 works as well. In VICE, use a keyset mapped to joystick port 2 (see `.vice/vicerc` for a WASD + Space example).

## Debug build flags

Pass to ACME (`acme -f cbm -DAUTOPLAY=1 -o out.prg src/main.asm`) for headless testing:

| Flag | Effect |
|------|--------|
| `AUTOPLAY` | Synthetic joystick input: sweeps left and right and fires |
| `NOFIRE` | With `AUTOPLAY`: no shooting during play |
| `DUAL` | Start with a dual fighter |
| `CAPTURE` | With `AUTOPLAY`: a boss always dives to capture, and the ship shoots it once it carries the captive |

## Source layout

`src/main.asm` holds the BASIC stub, start-up and the main loop, and includes the modules in memory order:

| File | Contents |
|------|----------|
| `constants.asm` | Hardware registers, constants, macros |
| `states.asm` | Title, stage intro, play, dying, captured, game over |
| `screen.asm` | Screen and colours, text, HUD, starfield |
| `sprites.asm` | Sprite setup, formation setup, game to multiplexer sprite copy |
| `player.asm` | Joystick, player movement, shooting |
| `enemies.asm` | Formation sway, enemy movement, dives, enemy bullets |
| `combat.asm` | Collision detection |
| `capture.asm` | Tractor beam, capture, rescue |
| `progress.asm` | Hits, scoring, player death, stage progression |
| `sound.asm` | SID effects and jingles |
| `multiplexer.asm` | Raster interrupt sprite multiplexer |
| `data.asm` | Variables and tables |
| `art.asm` | Sprite art, copied to `$3000` at start-up |
