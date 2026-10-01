<p align="center">
  <img src="docs/logo.png" alt="GALAGA" width="560">
</p>

<p align="center">
  <b>One arcade shooter, three machines.</b><br>
  Galaga clones for the Commodore 64, the PlayStation Portable, the Atari Lynx and the Thumby Color, written from the same game design.
</p>

<p align="center">
  <a href="https://vc64web.github.io/#openROMS=true#https://raw.githubusercontent.com/Shadester/galagas/master/c64/docs/galaga.prg"><b>▶ Play the C64 version in your browser</b></a>
</p>

<table>
  <tr>
    <td width="360"><a href="c64/"><img src="c64/docs/gameplay.gif" width="340" alt="Commodore 64"></a></td>
    <td>
      <h3><a href="c64/">Commodore 64</a></h3>
      <i>6502 assembly (ACME)</i><br><br>
      The original. A raster interrupt sprite multiplexer shows 44 sprites on 8 hardware sprites.
      Tractor beam capture, escorts, challenge stages, a title picture and SID sound.
    </td>
  </tr>
  <tr>
    <td width="360"><a href="psp/"><img src="psp/docs/gameplay.gif" width="340" alt="PlayStation Portable"></a></td>
    <td>
      <h3><a href="psp/">PlayStation Portable</a></h3>
      <i>C (PSPSDK)</i><br><br>
      A port of the C64 rules in C, with pixel-art sprites, a glow and particle renderer and synthesised sound.
    </td>
  </tr>
  <tr>
    <td width="360"><a href="lynx/"><img src="lynx/docs/gameplay.gif" width="340" alt="Atari Lynx"></a></td>
    <td>
      <h3><a href="lynx/">Atari Lynx</a></h3>
      <i>65C02 assembly (ca65)</i><br><br>
      A port of the C64 code to the Lynx: the same rules and numbers at half the size.
      The Suzy sprite engine replaces the multiplexer. The hi-score is saved in the cartridge EEPROM.
    </td>
  </tr>
  <tr>
    <td width="360"><a href="thumby/"><img src="thumby/docs/gameplay.gif" width="256" alt="Thumby Color"></a></td>
    <td>
      <h3><a href="thumby/">Thumby Color</a></h3>
      <i>MicroPython (Tiny Game Engine)</i><br><br>
      A port of the PSP rules to a 128 x 128 handheld, written in MicroPython. The rules run side by side with
      the C original in a test.
    </td>
  </tr>
</table>

All three have the same game: 32 aliens that fly in and dive, bosses that take two hits and capture your ship, a dual fighter when you rescue it, challenge stages with a perfect-clear bonus, and difficulty that rises every stage.

The C64 source is the reference for how the game must behave. The PSP, Lynx and Thumby Color games follow its rules.
Each directory has its own README with build instructions.
