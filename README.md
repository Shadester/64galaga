<p align="center">
  <img src="docs/logo.png" alt="GALAGA" width="560">
</p>

<p align="center">
  <b>One arcade shooter, three machines.</b><br>
  Galaga clones for the Commodore 64, the PlayStation Portable and the Atari Lynx, written from the same game design.
</p>

<p align="center">
  <a href="https://vc64web.github.io/#openROMS=true#https://raw.githubusercontent.com/Shadester/galagas/master/c64/docs/galaga.prg"><b>▶ Play the C64 version in your browser</b></a>
</p>

<table align="center">
  <tr>
    <td align="center"><a href="c64/"><img src="c64/docs/gameplay.gif" width="320" alt="Commodore 64"></a></td>
    <td align="center"><a href="psp/"><img src="psp/docs/gameplay.gif" width="320" alt="PlayStation Portable"></a></td>
    <td align="center"><a href="lynx/"><img src="lynx/docs/gameplay.gif" width="320" alt="Atari Lynx"></a></td>
  </tr>
  <tr>
    <td align="center"><b><a href="c64/">Commodore 64</a></b><br>6502 assembly (ACME)</td>
    <td align="center"><b><a href="psp/">PlayStation Portable</a></b><br>C (PSPSDK)</td>
    <td align="center"><b><a href="lynx/">Atari Lynx</a></b><br>65C02 assembly (ca65)</td>
  </tr>
</table>

## The three games

| | Platform | What is special |
|---|---|---|
| [**`c64/`**](c64/) | Commodore 64 | The original. A raster interrupt sprite multiplexer shows 44 sprites on 8 hardware sprites. Tractor beam capture, escorts, challenge stages, a title picture and SID sound. |
| [**`psp/`**](psp/) | PlayStation Portable | A port of the C64 rules in C, with pixel-art sprites, a glow and particle renderer and synthesised sound. |
| [**`lynx/`**](lynx/) | Atari Lynx | A port of the C64 code to the Lynx: the same rules and numbers at half the size. The Suzy sprite engine replaces the multiplexer. The hi-score is saved in the cartridge EEPROM. |

All three have the same game: 32 aliens that fly in and dive, bosses that take two hits and capture your ship, a dual fighter when you rescue it, challenge stages with a perfect-clear bonus, and difficulty that rises every stage.

The C64 source is the reference for how the game must behave. The PSP and Lynx games follow its rules.
Each directory has its own README with build instructions.
