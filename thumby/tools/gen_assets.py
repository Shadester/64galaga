#!/usr/bin/env python3
"""Generate the textures of the Thumby Color game (8-bit indexed BMPs: the engine loads 1/4/8/16-bit BMPs):

  Galaga/sprites.bmp   12 x 12 cells, 8 per row: aliens, ship, bullets, explosions (sprite ids: Galaga/sprite_ids.py)
  Galaga/beams.bmp     tractor beam strips: 4 colour phases across, 4 rows down, 36 x 4 pixel cells
  Galaga/title.bmp     the title picture (from assets/title-source.png, the C64 title picture)
  Galaga/icon.bmp      the launcher icon (38 pixels high)
  Galaga/font.bmp      the 5 x 7 font (the engine's built-in font has digits that are not on the baseline)

The alien, bullet and explosion art is decoded from ../c64/src/art.asm and squeezed from 12 to 10 columns (one column
dropped on each side of the body, so the wings keep their shape). Pen 0 (black) is transparent: the engine's
transparent_color is black. Usage: python3 tools/gen_assets.py [preview.png]
"""
import os
import re
import sys

from PIL import Image, ImageEnhance

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
C64_ART = os.path.join(ROOT, '..', 'c64', 'src', 'art.asm')
OUT = os.path.join(ROOT, 'Galaga')
CELL = 12
PAL = {'.': 0, 'w': 1, 'r': 2, 'b': 3, 'c': 4, 'y': 5, 'g': 6, 'p': 7, 'o': 8, 'l': 9, 'f': 10}
COLOURS = [(0, 0, 0), (255, 255, 255), (238, 34, 0), (68, 102, 255), (0, 204, 221), (255, 255, 0), (0, 204, 68),
           (204, 68, 221), (255, 136, 0), (153, 187, 255), (255, 170, 204)]


def c64_sprites():
    """name -> rows of 12 chars: . transparent, y yellow, o own colour, c cyan (the multicolour sprites)."""
    parts = re.split(r'^(\w+_sprite):\s*$', open(C64_ART).read(), flags=re.M)
    out = {}
    for i in range(1, len(parts), 2):
        if parts[i].startswith('player'):
            continue
        rows = [[int(x, 2) for x in re.findall(r'%([01]{8})', l)]
                for l in re.findall(r'!byte\s+((?:%[01]{8}(?:,\s*)?)+)', parts[i + 1])]
        rows = [r for r in rows if len(r) == 3]
        out[parts[i][:-7]] = [''.join('.yoc'[(r[0] << 16 | r[1] << 8 | r[2]) >> (22 - 2 * k) & 3] for k in range(12))
                              for r in rows]
    return out


def recolour(rows, own):
    m = {'.': '.', 'y': 'y', 'c': 'c', 'o': own}
    return [''.join(m[ch] for ch in r) for r in rows]


def squeeze(rows, drop_row=None):
    """12 -> 10 columns (drop columns 1 and 10), optionally drop one row, crop empty rows."""
    rows = [''.join(r[i] for i in (0, 2, 3, 4, 5, 6, 7, 8, 9, 11)) for k, r in enumerate(rows) if k != drop_row]
    rows = [r for r in rows]
    while rows and not rows[0].strip('.'):
        rows.pop(0)
    while rows and not rows[-1].strip('.'):
        rows.pop()
    return rows


def halve(rows):
    """Merge row pairs (the upper pixel wins): the tall player explosions."""
    rows = rows + ['.' * len(rows[0])] * (len(rows) % 2)
    return [''.join(a if a != '.' else b for a, b in zip(rows[i], rows[i + 1])) for i in range(0, len(rows), 2)]


SHIP = ['....w....',
        '....w....',
        '...wcw...',
        '...www...',
        '..bwwwb..',
        '.rbwwwbr.',
        '.rbbwbbr.',
        'wrbbbbbrw',
        '.rr.b.rr.']
CAPTIVE = [r.translate(str.maketrans('wbrc', 'fryw')) for r in SHIP]       # red and pink
LIFE = ['..w..', '..w..', '.bwb.', 'bwwwb', 'rb.br']                      # the lives icon of the HUD
PBUL = ['c', 'c', 'l', 'l', 'c']
EBUL = ['yy', 'rr', 'rr', 'rr', 'rr', 'yy']

c = c64_sprites()
SPRITES = []                                                              # (name, rows)
for name, own in (('bee', 'b'), ('bfly', 'r'), ('boss', 'g'), ('bossp', 'p')):
    base = 'boss' if name == 'bossp' else name
    for f in 'ab':
        SPRITES.append((f'{name}_{f}', squeeze(recolour(c[f'{base}_{f}'], own), 9 if name == 'bee' else None)))
SPRITES += [('ship', SHIP), ('captive', CAPTIVE), ('pbul', PBUL), ('ebul', EBUL)]
for n in (1, 2, 3):
    SPRITES.append((f'expl{n}', squeeze(recolour(c[f'expl{n}'], 'o'))))
for n in (1, 2, 3, 4):
    SPRITES.append((f'pexp{n}', squeeze(halve(recolour(c[f'pexp{n}'], 'o')))))
SPRITES.append(('life', LIFE))
NAMES = [n for n, _ in SPRITES]


def palette_bytes(colours):
    flat = [v for col in colours for v in col]
    return flat + [0] * (768 - len(flat))


def sheet():
    cols = 8
    rows = (len(SPRITES) + cols - 1) // cols
    im = Image.new('P', (cols * CELL, rows * CELL), 0)
    im.putpalette(palette_bytes(COLOURS))
    for i, (name, art) in enumerate(SPRITES):
        w, h = max(len(r) for r in art), len(art)
        ox, oy = i % cols * CELL + (CELL - w) // 2, i // cols * CELL + (CELL - h) // 2
        for y, r in enumerate(art):
            for x, ch in enumerate(r):
                if ch != '.':
                    im.putpixel((ox + x, oy + y), PAL[ch])
    return im, cols


def beams():
    """4 colour phases across, 4 rows down: row r is 2 * (r + 2) + 1 cells of 3 x 4 pixels, centred in 36 pixels."""
    im = Image.new('P', (4 * 36, 4 * 4), 0)
    im.putpalette(palette_bytes(COLOURS))
    for phase in range(4):
        for r in range(4):
            cells = 2 * (r + 2) + 1
            x0 = phase * 36 + (36 - cells * 3) // 2
            for k in range(cells):
                pen = PAL['blcl'[(k + r + phase) & 3]]
                for y in range(4):
                    for x in range(3):
                        if (x + y + k) % 2 == 0:
                            im.putpixel((x0 + k * 3 + x, r * 4 + y), pen)
    return im


def title():
    """128 x 71, 16 colours: pen 0 black, 1 white, 2 red are kept for the text; the rest is the picture."""
    w, h = 128, 71
    src = Image.open(os.path.join(ROOT, 'assets', 'title-source.png')).convert('RGB').crop((0, 10, 1448, 815))
    src = ImageEnhance.Color(src.resize((w, h), Image.LANCZOS)).enhance(2.0)      # keeps green and blue aliens apart
    q = src.quantize(32, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    pal = [tuple(q.getpalette()[i * 3:i * 3 + 3]) for i in range(32)]
    order = []
    for want in ((0, 0, 0), (255, 255, 255), (238, 34, 0)):
        order.append(min((i for i in range(32) if i not in order),
                         key=lambda i: sum((a - b) ** 2 for a, b in zip(pal[i], want))))
    order += [i for i in range(32) if i not in order]
    colours = [pal[i] for i in order]
    colours[0], colours[1], colours[2] = (0, 0, 0), (255, 255, 255), (238, 34, 0)
    pen = {old: new for new, old in enumerate(order)}
    out = Image.new('P', (w, h), 0)
    out.putpalette(palette_bytes(colours))
    out.putdata([pen[v] for v in q.get_flattened_data()])
    return out


FONT5X7 = {
    'A': '01110 10001 10001 11111 10001 10001 10001', 'B': '11110 10001 10001 11110 10001 10001 11110',
    'C': '01110 10001 10000 10000 10000 10001 01110', 'D': '11110 10001 10001 10001 10001 10001 11110',
    'E': '11111 10000 10000 11110 10000 10000 11111', 'F': '11111 10000 10000 11110 10000 10000 10000',
    'G': '01110 10001 10000 10111 10001 10001 01111', 'H': '10001 10001 10001 11111 10001 10001 10001',
    'I': '01110 00100 00100 00100 00100 00100 01110', 'J': '00111 00010 00010 00010 00010 10010 01100',
    'K': '10001 10010 10100 11000 10100 10010 10001', 'L': '10000 10000 10000 10000 10000 10000 11111',
    'M': '10001 11011 10101 10101 10001 10001 10001', 'N': '10001 11001 10101 10011 10001 10001 10001',
    'O': '01110 10001 10001 10001 10001 10001 01110', 'P': '11110 10001 10001 11110 10000 10000 10000',
    'Q': '01110 10001 10001 10001 10101 10010 01101', 'R': '11110 10001 10001 11110 10100 10010 10001',
    'S': '01111 10000 10000 01110 00001 00001 11110', 'T': '11111 00100 00100 00100 00100 00100 00100',
    'U': '10001 10001 10001 10001 10001 10001 01110', 'V': '10001 10001 10001 10001 10001 01010 00100',
    'W': '10001 10001 10001 10101 10101 10101 01010', 'X': '10001 10001 01010 00100 01010 10001 10001',
    'Y': '10001 10001 01010 00100 00100 00100 00100', 'Z': '11111 00001 00010 00100 01000 10000 11111',
    '0': '01110 10001 10011 10101 11001 10001 01110', '1': '00100 01100 00100 00100 00100 00100 01110',
    '2': '01110 10001 00001 00010 00100 01000 11111', '3': '11111 00010 00100 00010 00001 10001 01110',
    '4': '00010 00110 01010 10010 11111 00010 00010', '5': '11111 10000 11110 00001 00001 10001 01110',
    '6': '00110 01000 10000 11110 10001 10001 01110', '7': '11111 00001 00010 00100 01000 01000 01000',
    '8': '01110 10001 10001 01110 10001 10001 01110', '9': '01110 10001 10001 01111 00001 00010 01100',
    '-': '00000 00000 00000 11111 00000 00000 00000', '%': '11001 11010 00010 00100 01000 01011 10011',
    '!': '00100 00100 00100 00100 00100 00000 00100', '.': '00000 00000 00000 00000 00000 01100 01100',
    ':': '00000 01100 01100 00000 01100 01100 00000',
}


def font():
    """The engine's FontResource format: ASCII 32..125 side by side, 7 rows of glyphs; the bottom row marks the glyph widths
    with alternating colours. A glyph is 5 wide plus one blank column (a space is 4 wide). Every glyph sits on the same
    baseline (the engine's built-in font has digits that sit higher)."""
    widths = [4 if c == 32 else 6 for c in range(32, 126)]
    im = Image.new('P', (sum(widths) + 1, 8), 0)      # + 1: the engine counts colour changes, so it needs a mark after the last glyph
    im.putpalette(palette_bytes(COLOURS))
    x = 0
    for k, c in enumerate(range(32, 126)):
        rows = FONT5X7.get(chr(c))
        if rows:
            for y, r in enumerate(rows.split()):
                for gx, bit in enumerate(r):
                    if bit == '1':
                        im.putpixel((x + gx, y), 1)
        for gx in range(widths[k]):
            im.putpixel((x + gx, 7), 2 + k % 2)               # width marker: two colours, alternating per glyph
        x += widths[k]
    im.putpixel((x, 7), 2 + 94 % 2)
    return im


def icon():
    """38 x 38 launcher icon: a boss and the ship, both 2x."""
    im = Image.new('P', (38, 38), 0)
    im.putpalette(palette_bytes(COLOURS))
    for art, x0, y0 in ((dict(SPRITES)['boss_a'], 9, 0), (SHIP, 10, 19)):
        for y, row in enumerate(art):
            for x, ch in enumerate(row):
                if ch != '.':
                    for dy in range(2):
                        for dx in range(2):
                            im.putpixel((x0 + x * 2 + dx, y0 + y * 2 + dy), PAL[ch])
    return im


if __name__ == '__main__':
    im, cols = sheet()
    im.save(os.path.join(OUT, 'sprites.bmp'))
    beams().save(os.path.join(OUT, 'beams.bmp'))
    title().save(os.path.join(OUT, 'title.bmp'))
    icon().save(os.path.join(OUT, 'icon.bmp'))
    font().save(os.path.join(OUT, 'font.bmp'))
    ids = ['# Generated by tools/gen_assets.py: do not edit. Sprite ids: cell index in sprites.bmp (8 cells per row).']
    ids += [f'{n.upper():<8} = {i}' for i, n in enumerate(NAMES)]
    ids += [f'COLS = {cols}', 'CELL = 12', f'COUNT = {len(NAMES)}']
    open(os.path.join(OUT, 'sprite_ids.py'), 'w').write('\n'.join(ids) + '\n')
    print('sprites.bmp beams.bmp title.bmp sprite_ids.py', len(NAMES), 'sprites')
    if len(sys.argv) > 1:
        big = Image.new('RGB', (im.width * 6, im.height * 6 + 40 * 6))
        big.paste(im.convert('RGB').resize((im.width * 6, im.height * 6), Image.NEAREST), (0, 0))
        big.paste(beams().convert('RGB').resize((144 * 4, 16 * 4), Image.NEAREST), (0, im.height * 6))
        big.save(sys.argv[1])
