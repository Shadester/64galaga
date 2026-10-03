#!/usr/bin/env python3
"""Make galaga.p8: the sprite sheet, the title picture and the sound effects (the Lua files are included, not copied).

  gfx rows 0..23    20 sprites in 12 x 12 cells, 10 per row (ids: SPRITE_NAMES, the same order as thumby's sprite_ids.py)
  gfx rows 64..127  the title picture, 128 x 64, dithered to the PICO-8 palette (this half of the sheet is also the map: not used)
  sfx 0..4          shoot, explode, hit, death, swoop
  label             the title picture (the cart's picture in the .p8.png)
  gfx rows 24..63   the flight paths of the arcade rules (with the map memory: tools/gen_arcade_p8.py)
  sfx 8..12         the jingles (thumby/Galaga/jingles/*.rtttl), one note per 16th

The sprite art comes from thumby/tools/gen_assets.py (which decodes ../c64/src/art.asm). Usage: python3 tools/gen_assets.py [preview.png]
"""
import os
import random
import re
import sys

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
TH = os.path.join(ROOT, '..', 'thumby')
sys.path.insert(0, os.path.join(TH, 'tools'))
import gen_assets as T  # noqa: E402  (builds the sprite art on import)
import gen_arcade_p8 as A  # noqa: E402  (the flight paths of the arcade rules: a blob in the free rows 24..63 and in the map)

# thumby art letters -> PICO-8 colours
PEN = {'.': 0, 'w': 7, 'r': 8, 'b': 12, 'c': 6, 'y': 10, 'g': 11, 'p': 14, 'o': 9, 'l': 6, 'f': 15}
PAL = ['000000', '1D2B53', '7E2553', '008751', 'AB5236', '5F574F', 'C2C3C7', 'FFF1E8',
       'FF004D', 'FFA300', 'FFEC27', '00E436', '29ADFF', '83769C', 'FF77A8', 'FFCCAA']
CELL, COLS = 12, 10


def gfx():
    px = [[0] * 128 for _ in range(128)]
    for i, (name, art) in enumerate(T.SPRITES):
        w, h = max(len(r) for r in art), len(art)
        ox, oy = i % COLS * CELL + (CELL - w) // 2, i // COLS * CELL + (CELL - h) // 2
        for y, r in enumerate(art):
            for x, ch in enumerate(r):
                px[oy + y][ox + x] = PEN[ch]
    pal = Image.new('P', (1, 1))
    pal.putpalette([int(c[k:k + 2], 16) for c in PAL for k in (0, 2, 4)] + [0] * (768 - 48))
    src = Image.open(os.path.join(TH, 'assets', 'title-source.png')).convert('RGB').crop((0, 10, 1448, 815))
    q = src.resize((128, 64), Image.LANCZOS).quantize(palette=pal, dither=Image.Dither.FLOYDSTEINBERG)
    for y in range(64):
        for x in range(128):
            px[64 + y][x] = q.getpixel((x, y))
    return px


NOTE = {'c': 0, 'c#': 1, 'd': 2, 'd#': 3, 'e': 4, 'f': 5, 'f#': 6, 'g': 7, 'g#': 8, 'a': 9, 'a#': 10, 'b': 11}


def sfx(speed, notes, loop=(0, 0)):
    """notes: (pitch, waveform, volume, effect) up to 32."""
    s = '01%02x%02x%02x' % (speed, *loop)
    for p, w, v, e in notes + [(0, 0, 0, 0)] * (32 - len(notes)):
        s += '%02x%x%x%x' % (p, w, v, e)
    return s


def jingle(path, speed):
    """RTTTL, one slot per 16th. One octave lower than written: PICO-8 stops at pitch 63 (D#5)."""
    head, defaults, body = open(path).read().strip().split(':')
    d = int(re.search(r'd=(\d+)', defaults).group(1))
    o = int(re.search(r'o=(\d+)', defaults).group(1))
    notes = []
    for tok in body.split(','):
        m = re.fullmatch(r'(\d*)([a-g]#?|p)(\d?)', tok.strip())
        dur = 16 // int(m.group(1) or d)
        pitch = 12 * (int(m.group(3) or o) - 1) + NOTE[m.group(2)]
        notes += [(pitch, 0, 5, 0)] * (dur - 1) + [(pitch, 0, 5, 5)]
    assert len(notes) <= 32, path
    return sfx(speed, notes)


def sounds():
    random.seed(3)
    out = {
        0: sfx(1, [(55 - 2 * i, 1, 5, 0) for i in range(12)]),                               # shoot
        1: sfx(3, [(random.randrange(18, 48), 6, 6 - i // 3, 0) for i in range(16)]),        # explosion
        2: sfx(2, [(44 - i, 4, 6, 0) for i in range(16)]),                                   # ship hit
        3: sfx(5, [(30 - i, 6, 7 - i // 3, 0) for i in range(20)]),                          # death
        4: sfx(2, [(42 - i, 2, 3, 0) for i in range(24)]),                                   # swoop and beam hum
    }
    for k, (name, speed) in enumerate((('stage', 17), ('over', 14), ('capture', 15), ('rescue', 13), ('bonus', 10))):
        out[8 + k] = jingle(os.path.join(TH, 'Galaga', 'jingles', name + '.rtttl'), speed)
    return out


def cart():
    px = gfx()
    blob = A.blob()
    A.place(px, blob)
    s = 'pico-8 cartridge // http://www.pico-8.com\nversion 42\n__lua__\n#include paths.lua\n#include arcade_data.lua\n#include game.lua\n#include main.lua\n'
    s += '__gfx__\n' + '\n'.join(''.join('%x' % v for v in row) for row in px) + '\n'
    snd = sounds()
    s += '__sfx__\n' + '\n'.join(snd.get(i, sfx(1, [])) for i in range(max(snd) + 1)) + '\n'
    label = [[0] * 128 for _ in range(32)] + px[64:] + [[0] * 128 for _ in range(32)]
    s += A.map_section(blob)
    s += '__label__\n' + '\n'.join(''.join('%x' % v for v in row) for row in label) + '\n'
    return s, px


if __name__ == '__main__':
    text, px = cart()
    open(os.path.join(ROOT, 'galaga.p8'), 'w').write(text)
    print('galaga.p8', len(text), 'bytes,', len(T.SPRITES), 'sprites')
    if len(sys.argv) > 1:
        im = Image.new('RGB', (128, 128))
        im.putdata([tuple(int(PAL[v][k:k + 2], 16) for k in (0, 2, 4)) for row in px for v in row])
        im.resize((512, 512), Image.NEAREST).save(sys.argv[1])
