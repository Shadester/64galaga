# galagas

Galaga clones for two machines, written from the same game design.

| Project | Platform | Language | |
|---|---|---|---|
| [`c64/`](c64/) | Commodore 64 | 6502 assembly (ACME) | The original: sprite multiplexer, tractor beam, challenge stages. [Play in the browser](https://vc64web.github.io/#openROMS=true#https://raw.githubusercontent.com/Shadester/galagas/master/c64/docs/galaga.prg) |
| [`psp/`](psp/) | PlayStation Portable | C (PSPSDK) | A port of the C64 game's rules with pixel-art sprites, glow and particle effects, and synthesised sound |

The PSP game follows the C64 game's rules, so the C64 source is the reference for how the game should behave.
Each directory has its own README with build instructions.
