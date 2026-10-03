#!/usr/bin/env python3
"""Make src/assets.h: the pictures of the Amiga game.

  * sprites ("bobs") for the blitter: 5 bitplanes, interleaved (one row = plane 0 .. plane 4), one word of
    padding on the right (the blitter shifts the picture into it), and a mask in the same layout. The alien art comes from
    ../c64/src/art.asm (via thumby/tools/gen_assets.py): 12 multicolour pixels wide, doubled in both directions (the C64 sprites
    are expanded in y): 24 pixels wide on the Amiga screen, as on the C64. The art is in the top rows of the 21 of a C64 sprite.
  * the game palette (32 colours, tools/art.py) and the title picture (320 x 178, its own 32 colours: pens 0, 1, 2 are black, white and red)
  * the 5 x 7 font, in 8 x 8 cells
  * the sound effects (8-bit samples, made here) and the jingles (thumby/Galaga/jingles/*.rtttl, as notes)

Usage: python3 tools/gen_assets.py [preview.png]"""
import os
import sys

from PIL import Image, ImageEnhance

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
TH = os.path.join(ROOT, '..', 'thumby')
sys.path.insert(0, os.path.join(TH, 'tools'))
import gen_assets as T  # noqa: E402  (builds the sprite art on import)

import art  # noqa: E402  (tools/art.py: the palette and the pixel art)

NPL = 5                                                            # bitplanes: 32 colours
PEN = art.PEN
COLOURS = art.COLOURS


def rgb4(c):
    return (c[0] // 17) << 8 | (c[1] // 17) << 4 | c[2] // 17


def scaled(rows, sx, sy):
    out = []
    for r in rows:
        r = ''.join(ch * sx for ch in r)
        out += [r] * sy
    return out


def crop(rows):
    """Drops the empty rows at the bottom (the sprites of the C64 have 21 rows, the art is in the top part)."""
    while rows and not rows[-1].strip('.'):
        rows = rows[:-1]
    return rows


def planar(rows, mask):
    """rows of art letters -> words, interleaved planes, one padding word. mask: the same, 0 / 0xffff."""
    w = max(len(r) for r in rows)
    words_per_plane = (w + 15) // 16
    out = []
    for r in rows:
        r = r.ljust(words_per_plane * 16, '.')
        pens = [PEN[ch] for ch in r]
        for p in range(NPL):
            for k in range(words_per_plane):
                v = 0
                for b in range(16):
                    pen = pens[k * 16 + b]
                    bit = (1 if pen else 0) if mask else (pen >> p) & 1
                    v = v << 1 | bit
                out.append(v)
            out.append(0)                                           # padding word
    return words_per_plane, out


def sprite_list():
    c = T.c64_sprites()
    sp = []
    for name, own in (('bee', 'b'), ('bfly', 'r'), ('boss', 'g'), ('bossp', 'p')):
        base = 'boss' if name == 'bossp' else name
        for f in 'ab':
            sp.append((f'{name}_{f}', art.hand(f'{name}_{f}')))
    sp += [('ship', art.ship()), ('captive', art.captive()), ('pbul', art.PBUL), ('ebul', art.EBUL)]
    for n in (1, 2, 3):
        sp.append((f'expl{n}', art.alien(crop(T.recolour(c[f'expl{n}'], 'o')), 'O')))
    for n in (1, 2, 3, 4):                                         # the C64 draws these in hires: no doubling downwards
        rows = scaled(crop(T.recolour(c[f'pexp{n}'], 'o')), 2, 1)
        sp.append((f'pexp{n}', [r.replace('o', 'O').replace('c', 'C') for r in rows]))
    sp.append(('life', art.small_ship()))
    return sp


def title():
    """320 x 178, 32 colours. The palette is fitted without the dim star specks (they would take entries from the small aliens).
    Pens 0, 1, 2 are black, white and red (the text), pen 31 is the shadow of the text."""
    w, h = 320, 178
    src = Image.open(os.path.join(TH, 'assets', 'title-source.png')).convert('RGB').crop((0, 10, 1448, 815))
    src = ImageEnhance.Color(src.resize((w, h), Image.LANCZOS)).enhance(1.6)
    flat = lambda im: im.get_flattened_data() if hasattr(im, 'get_flattened_data') else im.getdata()
    bright = Image.new('RGB', src.size)
    bright.putdata([p if max(p) >= 120 else (0, 0, 0) for p in flat(src)])
    fit = bright.quantize(31, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    q = src.quantize(palette=fit, dither=Image.Dither.NONE)
    pal = [tuple(fit.getpalette()[i * 3:i * 3 + 3]) for i in range(31)]
    order = []
    for want in ((0, 0, 0), (255, 255, 255), (238, 34, 0)):
        order.append(min((i for i in range(31) if i not in order), key=lambda i: sum((a - b) ** 2 for a, b in zip(pal[i], want))))
    order += [i for i in range(31) if i not in order]
    colours = [pal[i] for i in order] + [art.COLOURS[art.PEN['t']]]
    colours[0], colours[1], colours[2] = (0, 0, 0), (255, 255, 255), (238, 34, 0)
    pen = {old: new for new, old in enumerate(order)}
    px = [pen[v] for v in flat(q)]
    words = []
    for y in range(h):                                              # interleaved planes, 20 words a plane
        for p in range(NPL):
            for k in range(20):
                v = 0
                for b in range(16):
                    v = v << 1 | (px[y * w + k * 16 + b] >> p & 1)
                words.append(v)
    return colours, words, px


def font():
    """Glyph rows for ASCII 32..95: 8 bytes each (the 5 x 7 glyphs of thumby, in the top-left of an 8 x 8 cell)."""
    out = []
    for c in range(32, 96):
        rows = T.FONT5X7.get(chr(c))
        g = [int(r, 2) << 3 for r in rows.split()] if rows else [0] * 7
        out += g + [0]
    return out



# ---- sound: 8-bit samples at 8000 Hz for the effects, and the jingles as (period, ticks) notes ----
RATE = 8000
PAULA = 3546895                                                    # the PAL clock: period = PAULA / sample rate


def lcg_noise(n, seed=12345):
    x, out = seed, []
    for _ in range(n):
        x = (x * 1103515245 + 12345) & 0x7fffffff
        out.append((x >> 8) / 0x7fffff * 2 - 1)
    return out


def sweep(n, f0, f1, amp, wave):
    out, ph = [], 0.0
    for i in range(n):
        ph += (f0 + (f1 - f0) * i / n) / RATE
        v = (1 if ph % 1 < 0.5 else -1) if wave == 'square' else (ph % 1) * 2 - 1
        out.append(v * amp * (1 - i / n))
    return out


def lowpass_noise(n, k, amp, tau, seed):
    out, y = [], 0.0
    for i, v in enumerate(lcg_noise(n, seed)):
        y += (v - y) * k
        out.append(y * amp * 2.5 * 2.718 ** (-i / tau))
    return out


def effects():
    shoot = sweep(800, 1600, 400, 0.7, 'square')
    expl = lowpass_noise(2400, 0.45, 0.9, 900, 7)
    hit = sweep(1600, 420, 140, 0.7, 'saw')
    death = [a + b for a, b in zip(lowpass_noise(4800, 0.15, 0.8, 2000, 99), sweep(4800, 70, 40, 0.3, 'square'))]
    swoop = sweep(2000, 900, 220, 0.5, 'saw')
    return [('shoot', shoot), ('explosion', expl), ('hit', hit), ('death', death), ('swoop', swoop)]


NOTE = {'c': 0, 'c#': 1, 'd': 2, 'd#': 3, 'e': 4, 'f': 5, 'f#': 6, 'g': 7, 'g#': 8, 'a': 9, 'a#': 10, 'b': 11}


def jingle(path):
    """RTTTL -> [(period, ticks)]: the voice plays a 16 byte wave, so the sample rate is 16 times the note frequency. 50 ticks a second."""
    import re
    _, defaults, body = open(path).read().strip().split(':')
    d = int(re.search(r'd=(\d+)', defaults).group(1))
    o = int(re.search(r'o=(\d+)', defaults).group(1))
    bpm = int(re.search(r'b=(\d+)', defaults).group(1))
    notes = []
    for tok in body.split(','):
        m = re.fullmatch(r'(\d*)([a-g]#?|p)(\d?)', tok.strip())
        ticks = round(4 * 60 / bpm / int(m.group(1) or d) * 50)
        if m.group(2) == 'p':
            notes.append((0, ticks))
        else:
            semi = 12 * (int(m.group(3) or o)) + NOTE[m.group(2)]
            f = 440 * 2 ** ((semi - 57) / 12)                      # c5 = semitone 60 (a4 = 57 = 440 Hz)
            notes.append((round(PAULA / (f * 16)), ticks))
    return notes


def arr(name, vals, typ='unsigned short', per=12, fmt='0x%04x'):
    lines = [f'static const {typ} {name}[{len(vals)}] = {{']
    for i in range(0, len(vals), per):
        lines.append('    ' + ', '.join(fmt % v for v in vals[i:i + per]) + ',')
    lines.append('};')
    return '\n'.join(lines)


def main():
    sp = sprite_list()
    out = ['/* Generated by tools/gen_assets.py: do not edit. */', '#ifndef ASSETS_H', '#define ASSETS_H', '']
    out.append('enum {  /* sprite ids */\n    ' + ', '.join('SPR_' + n.upper() for n, _ in sp) + ', SPR_COUNT\n};')
    words, table = [], []
    for name, art in sp:
        wpp, bob = planar(art, False)
        _, mask = planar(art, True)
        table.append((wpp, len(art), len(words), len(words) + len(bob)))
        words += bob + mask
    out.append(arr('sprite_words', words))
    out.append('typedef struct { unsigned char w, h; unsigned short bob, mask; } SpriteInfo;   /* w: words without the padding; bob, mask: index in sprite_words */')
    out.append('static const SpriteInfo sprites[SPR_COUNT] = {\n' + ',\n'.join('    {%d, %d, %d, %d}' % t for t in table) + ',\n};')
    out.append(arr('game_palette', [rgb4(c) for c in COLOURS], per=8))
    tcol, tw, tpx = title()
    out.append(arr('title_palette', [rgb4(c) for c in tcol], per=8))
    out.append('#define TITLE_H 178')
    out.append(arr('title_words', tw))
    out.append(arr('font_rows', font(), typ='unsigned char', per=16, fmt='0x%02x'))
    eff = effects()
    data, table = [], []
    for name, smp in eff:
        table.append((len(data), len(smp) // 2))                  # offset in bytes, length in words
        data += [max(-127, min(127, round(v * 127))) & 255 for v in smp]
        if len(data) % 2:
            data.append(0)
    out.append('enum { SFX_SHOOT, SFX_EXPLOSION, SFX_HIT, SFX_DEATH, SFX_SWOOP, SFX_COUNT };')
    out.append(arr('sfx_data', data, typ='unsigned char', per=16, fmt='0x%02x').replace(' = {', ' __attribute__((aligned(2))) = {', 1))   # Paula reads words
    out.append('static const unsigned short sfx_table[SFX_COUNT][2] = {' + ', '.join('{%d, %d}' % t for t in table) + '};   /* byte offset, words */')
    out.append('#define SFX_RATE_PERIOD %d   /* Paula period for the 8000 Hz samples */' % round(PAULA / RATE))
    jn, jt = [], []
    for k, name in enumerate(('stage', 'over', 'capture', 'rescue', 'bonus')):
        notes = jingle(os.path.join(TH, 'Galaga', 'jingles', name + '.rtttl'))
        jt.append((len(jn), len(notes)))
        jn += notes
    out.append('/* the jingles, in the order of the Game.snd bits JG_STAGE .. JG_BONUS: (period, ticks) of each note, period 0 = a rest */')
    out.append('static const unsigned short jingle_notes[%d][2] = {' % len(jn) + ', '.join('{%d, %d}' % n for n in jn) + '};')
    out.append('static const unsigned short jingle_table[5][2] = {' + ', '.join('{%d, %d}' % t for t in jt) + '};   /* first note, count */')
    out += ['', '#endif', '']
    open(os.path.join(ROOT, 'src', 'assets.h'), 'w').write('\n'.join(out))
    print('src/assets.h', sum(len(o) for o in out), 'bytes,', len(sp), 'sprites,', len(words) * 2, 'bytes of sprite data')
    if len(sys.argv) > 1:                                           # preview: sprites 3x on the left, the title below
        im = Image.new('RGB', (960, 700), (30, 30, 30))
        x = y = 4
        for name, art in sp:
            for yy, r in enumerate(art):
                for xx, ch in enumerate(r):
                    if ch != '.':
                        for dy in range(3):
                            for dx in range(3):
                                im.putpixel((x + xx * 3 + dx, y + yy * 3 + dy), COLOURS[PEN[ch]])
            x += max(len(r) for r in art) * 3 + 8
            if x > 800:
                x, y = 4, y + 70
        tim = Image.new('RGB', (320, 178))
        tim.putdata([tcol[p] for p in tpx])
        im.paste(tim.resize((640, 356), Image.NEAREST), (4, 300))
        im.save(sys.argv[1])


main()
