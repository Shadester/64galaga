# galagas

Galaga clones for three machines, written from the same game design.

| Project | Platform | Language | |
|---|---|---|---|
| [`c64/`](c64/) | Commodore 64 | 6502 assembly (ACME) | The original: sprite multiplexer, tractor beam, challenge stages. [Play in the browser](https://vc64web.github.io/#openROMS=true#https://raw.githubusercontent.com/Shadester/galagas/master/c64/docs/galaga.prg) |
| [`psp/`](psp/) | PlayStation Portable | C (PSPSDK) | A port of the C64 game's rules with pixel-art sprites, glow and particle effects, and synthesised sound |
| [`lynx/`](lynx/) | Atari Lynx | 65C02 assembly (ca65) | A port of the C64 game's code: the same rules and numbers at half the size, with the Lynx sprite engine instead of a multiplexer |

The PSP and Lynx games follow the C64 game's rules, so the C64 source is the reference for how the game should behave.
Each directory has its own README with build instructions.
