<p align="center">
  <img src="docs/logo.png" alt="GALAGA" width="560">
</p>

<p align="center">
  <b>One arcade shooter, six machines and a terminal.</b><br>
  Galaga clones for the Commodore 64, the PlayStation Portable, the Atari Lynx, the Thumby Color, PICO-8, the Commodore Amiga and the terminal, written from the same game design.
</p>

<p align="center">
  <b>Play in your browser:</b>
  <a href="https://vc64web.github.io/#openROMS=true#https://raw.githubusercontent.com/Shadester/galagas/12119bb5e0a705750db8a54e6f21cf0ca70cfa11/c64/docs/galaga.prg"><b>▶ C64</b></a> ·
  <a href="https://shadester.github.io/galagas/pico8/"><b>▶ PICO-8</b></a> ·
  <a href="https://shadester.github.io/galagas/lynx/"><b>▶ Atari Lynx Landscape</b></a> ·
  <a href="https://shadester.github.io/galagas/lynx/portrait.html"><b>▶ Atari Lynx Portrait</b></a> ·
  <a href="https://shadester.github.io/galagas/psp/"><b>▶ PSP</b></a> ·
  <a href="https://vamigaweb.github.io/#AROS=true#https://raw.githubusercontent.com/Shadester/galagas/master/amiga/docs/galaga.adz"><b>▶ Amiga</b></a> ·
  <a href="https://shadester.github.io/galagas/tui/"><b>▶ Terminal</b></a>
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
      The reference of the rules, in C: the arcade rules (and, with <code>-DRULES_ARCADE32</code>, the same rules on the C64 layout with 32 aliens). It has pixel-art sprites, a glow and particle renderer and synthesised sound.
    </td>
  </tr>
  <tr>
    <td width="360"><a href="lynx/"><img src="lynx/docs/gameplay.gif" width="340" alt="Atari Lynx Landscape"></a></td>
    <td>
      <h3><a href="lynx/">Atari Lynx Landscape</a></h3>
      <i>65C02 assembly (ca65)</i><br><br>
      A port of the C64 code to the Lynx: the same rules and numbers at half the size.
      The Suzy sprite engine replaces the multiplexer. The hi-score is saved in the cartridge EEPROM.
    </td>
  </tr>
  <tr>
    <td width="360"><a href="lynx/"><img src="lynx/docs/gameplay-portrait.gif" width="200" alt="Atari Lynx Portrait"></a></td>
    <td>
      <h3><a href="lynx/">Atari Lynx Portrait</a></h3>
      <i>65C02 assembly (ca65)</i><br><br>
      The same game in the arcade's own portrait shape: a second ROM with the field turned by 90 degrees and 8 x 8 pixel art.
      Hold the Lynx on its side; the emulator turns the picture back.
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
  <tr>
    <td width="360"><a href="pico8/"><img src="pico8/docs/gameplay.gif" width="256" alt="PICO-8"></a></td>
    <td>
      <h3><a href="pico8/">PICO-8</a></h3>
      <i>Lua (PICO-8 0.2.6b)</i><br><br>
      A port of the Thumby Color rules to the 128 x 128 fantasy console. The rules run side by side with
      the C original in a test.
    </td>
  </tr>
  <tr>
    <td width="360"><a href="amiga/"><img src="amiga/docs/gameplay.gif" width="340" alt="Commodore Amiga"></a></td>
    <td>
      <h3><a href="amiga/">Commodore Amiga</a></h3>
      <i>C and 68000 assembly (m68k-elf-gcc)</i><br><br>
      A bootable floppy that takes over the bare A500: blitter sprites, copper, Paula sound. The rules are
      <code>psp/game.c</code> itself, built without floats. A test runs it on the 68000 next to the Mac build.
    </td>
  </tr>
  <tr>
    <td width="360"><a href="tui/"><img src="tui/docs/gameplay.gif" width="340" alt="Terminal"></a></td>
    <td>
      <h3><a href="tui/">Terminal</a></h3>
      <i>Rust (crossterm)</i><br><br>
      Pixel art in half-block characters and 24-bit colour, in any terminal from 80 x 27 cells up. The rules are a
      translation of <code>psp/game.c</code>, and a test compares every tick with the C original.
    </td>
  </tr>
</table>

All of them have the same game: aliens that fly in and dive, bosses that take two hits and capture your ship, a dual fighter when you rescue it, challenge stages with a perfect-clear bonus, and difficulty that rises every stage.

The PSP, Thumby Color, PICO-8, Amiga and Atari Lynx games play by the rules of the arcade Galaga: 40 aliens, the arcade fly-in waves and flight paths, the dive scheduler with escorts, aimed bombs, a formation that swings and then breathes, and challenge stages of five waves. The C64 game plays the same rules with 32 aliens on its own fly-in paths (its 8 hardware sprites cannot show the arcade's rows of 10). The graphics and the sound are our own. The numbers (paths, wave lists, timers) come from a model of the arcade program ([tomcoolpxl/cool8-cpu](https://github.com/tomcoolpxl/cool8-cpu), MIT licence); [ARCADE.md](ARCADE.md) compares our rules with the arcade, rule by rule.

`psp/game.c` is the reference for the rules of all the games. The Thumby Color, PICO-8 and Amiga versions run next to it in a test, tick by tick. `tools/compare_6502.py` compares the Lynx game and the C64 game with it at checkpoints; for the C64 it is built with `-DRULES_ARCADE32` (32 aliens).
Each directory has its own README with build instructions.
