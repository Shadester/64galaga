#!/usr/bin/env python3
"""Generate the title picture: src/title.bin and src/title_font.asm.

The picture is a C64 multicolor bitmap (160x200 pixels of 2x1 screen pixels, 16 fixed colours,
per 4x8 cell the background plus at most 3 colours):
  - the GALAGA logo, resampled from assets/title-source.png (made with Codex / gpt-image);
  - the game's own aliens, ship and shot, taken pixel for pixel from src/art.asm and placed on
    whole cells, so they look exactly as in play and all aliens of a row are identical;
  - a starfield of lone pixels in empty cells, and the "HI-SCORE" / "PRESS FIRE" lines, drawn
    with a tiny 3x7 font. The six hi-score digits are drawn by the game at run time from the
    10 glyphs written to src/title_font.asm.

src/title.bin is loaded at $5800 (see src/main.asm):
  $5800  colour RAM data (1000 bytes, padded to 1024)
  $5c00  screen matrix (1000 bytes, padded to 1024): colours of bit pairs %01 (high nibble) / %10
  $6000  bitmap (8000 bytes)
Usage: python3 tools/gen_title.py [preview.png]
"""
import itertools
import sys
import numpy as np
from PIL import Image

SRC = 'assets/title-source.png'
W, H = 160, 200                      # multicolor pixels
CONTENT_W = 133                      # the source is 4:3; a multicolor pixel is 2x1 screen pixels
TEXT_ROWS = (21, 23)                 # character rows of the hi-score line and the PRESS FIRE line
LABEL_COL, DIGITS_COL = 12, 21       # hi-score: "HI-SCORE" at 12..19, six digits at 21..26
WHITE, CYAN, YELLOW = 1, 3, 7

PALETTE = [(0x00, 0x00, 0x00), (0xff, 0xff, 0xff), (0x68, 0x37, 0x2b), (0x70, 0xa4, 0xb2),
           (0x6f, 0x3d, 0x86), (0x58, 0x8d, 0x43), (0x35, 0x28, 0x79), (0xb8, 0xc7, 0x6f),
           (0x6f, 0x4f, 0x25), (0x43, 0x39, 0x00), (0x9a, 0x67, 0x59), (0x44, 0x44, 0x44),
           (0x6c, 0x6c, 0x6c), (0x9a, 0xd2, 0x84), (0x6c, 0x5e, 0xb5), (0x95, 0x95, 0x95)]

# The C64 has no bright orange or yellow: steer the logo's colours to the closest useful entries
# (source colour -> palette index) so that yellow, orange and red stay three distinct colours.
ANCHORS = [((0xf0, 0xe0, 0x30), 7), ((0xf0, 0x90, 0x20), 8), ((0xb0, 0x10, 0x20), 2),
           ((0x50, 0xa0, 0xf0), 14), ((0x30, 0x30, 0xb0), 6), ((0x60, 0xe0, 0x80), 13)]


FONT = {
    '0': "### #.# #.# #.# #.# #.# ###", '1': ".#. ##. .#. .#. .#. .#. ###",
    '2': "### ..# ..# ### #.. #.. ###", '3': "### ..# ..# ### ..# ..# ###",
    '4': "#.# #.# #.# ### ..# ..# ..#", '5': "### #.. #.. ### ..# ..# ###",
    '6': "### #.. #.. ### #.# #.# ###", '7': "### ..# ..# .#. .#. .#. .#.",
    '8': "### #.# #.# ### #.# #.# ###", '9': "### #.# #.# ### ..# ..# ###",
    'H': "#.# #.# #.# ### #.# #.# #.#", 'I': "### .#. .#. .#. .#. .#. ###",
    '-': "... ... ... ### ... ... ...", 'S': "### #.. #.. ### ..# ..# ###",
    'C': "### #.. #.. #.. #.. #.. ###", 'O': "### #.# #.# #.# #.# #.# ###",
    'R': "##. #.# #.# ##. #.# #.# #.#", 'E': "### #.. #.. ##. #.. #.. ###",
    'P': "### #.# #.# ### #.. #.. #..", 'F': "### #.. #.. ##. #.. #.. #..",
}


def nearest(rgb):
    """Index of the nearest C64 colour (or anchor) for an (n, 3) array."""
    pal = np.array(PALETTE + [a for a, _ in ANCHORS], dtype=np.int32)
    ids = np.array(list(range(16)) + [i for _, i in ANCHORS])
    d = ((rgb[:, None, :].astype(np.int32) - pal[None, :, :]) ** 2).sum(axis=2)
    return ids[d.argmin(axis=1)]


def sample(idx, x0, x1, y0, y1, w, h):
    """Source box -> w x h multicolor pixels (most common non-black colour; mostly black = background)."""
    out = np.zeros((h, w), dtype=np.uint8)
    xs = np.linspace(x0, x1, w + 1).astype(int)
    ys = np.linspace(y0, y1, h + 1).astype(int)
    for y in range(h):
        for x in range(w):
            block = idx[ys[y]:max(ys[y + 1], ys[y] + 1), xs[x]:max(xs[x + 1], xs[x] + 1)].ravel()
            cnt = np.bincount(block, minlength=16)
            if cnt[0] >= 0.75 * block.size:
                continue
            cnt[0] = 0
            out[y, x] = cnt.argmax()
    return out


ART = 'src/art.asm'
SPRITE_COLORS = (7, 3)               # shared multicolor 1 / 2 (src/sprites.asm: yellow, cyan)
LOGO_COLORS = {2, 7, 8}              # red shadow, yellow, orange
LOGO_ROWS = 48                       # the logo sits in the top 6 character rows


def sprite_rows(label):
    """The 21 rows (3 bytes each) of a sprite in src/art.asm."""
    rows, on = [], False
    for line in open(ART):
        line = line.strip()
        if line.startswith(label + ':'):
            on = True
        elif on and line.startswith('!byte'):
            rows.append([int(b.strip()[1:], 2) for b in line.split(';')[0][5:].split(',')])
            if len(rows) == 21:
                break
    return rows


def put_multicolor(canvas, label, own, x, y):
    """A multicolor sprite of the game, one multicolor pixel per sprite pixel pair, at (x, y)."""
    for dy, row in enumerate(sprite_rows(label)):
        bits = (row[0] << 16) | (row[1] << 8) | row[2]
        for dx in range(12):
            v = (bits >> (22 - 2 * dx)) & 3
            if v:
                canvas[y + dy, x + dx] = (SPRITE_COLORS[0], own, SPRITE_COLORS[1])[v - 1]


def put_ship(canvas, x, y):
    """The hires player ship: pairs of pixels become one (double width) multicolor pixel."""
    for dy, row in enumerate(sprite_rows('player_sprite')[:14]):
        bits = (row[0] << 16) | (row[1] << 8) | row[2]
        for dx in range(12):
            if (bits >> (23 - 2 * dx)) & 3:
                canvas[y + dy, x + dx - 2] = 1


def convert():
    """The logo of the source picture, then the game's own aliens, ship, shot and stars.

    The aliens are the sprites of the game (the same pixels and colours as in play), placed on
    whole 4x8 cells, so every alien of a row converts identically and needs no colour
    compromises. The logo is resampled from the source picture."""
    src = Image.open(SRC).convert('RGB')
    sw, sh = src.size
    idx = nearest(np.asarray(src).reshape(-1, 3)).reshape(sh, sw)
    x0 = (W - CONTENT_W) // 2
    full = np.zeros((H, W), dtype=np.uint8)
    full[:, x0:x0 + CONTENT_W] = sample(idx, 0, sw, 0, sh, CONTENT_W, H)
    canvas = np.zeros((H, W), dtype=np.uint8)
    logo = full[:LOGO_ROWS]
    canvas[:LOGO_ROWS] = np.where(np.isin(logo, list(LOGO_COLORS)), logo, 0)
    for label, own, count, y in (('boss_a_sprite', 5, 4, 56), ('bfly_a_sprite', 2, 7, 72),
                                 ('bfly_a_sprite', 2, 7, 88), ('bee_a_sprite', 14, 7, 104),
                                 ('bee_a_sprite', 14, 7, 120)):
        for i in range(count):
            put_multicolor(canvas, label, own, (W - count * 16) // 2 + i * 16 + 2, y)
    put_ship(canvas, 76, 146)
    put_multicolor(canvas, 'bullet_sprite', 14, 74, 132)      # the ship's shot
    rng = np.random.default_rng(64)               # stars: lone pixels in empty cells, like the game's
    empty = [(r, c) for r in range(25) for c in range(40)
             if r not in TEXT_ROWS and not canvas[r * 8:r * 8 + 8, c * 4:c * 4 + 4].any()]
    for n in rng.choice(len(empty), 70, replace=False):
        r, c = empty[n]
        canvas[r * 8 + rng.integers(8), c * 4 + rng.integers(4)] = rng.choice([1, 1, 15, 12, 11])
    return canvas


def glyph(ch):
    return [row for row in FONT[ch].split()]


def draw_text(canvas, colors, text, col, row, color):
    """3x7 glyphs in 4x8 cells (colour %11 from colour RAM); returns nothing."""
    for i, ch in enumerate(text):
        if ch == ' ':
            continue
        for gy, line in enumerate(glyph(ch)):
            for gx, c in enumerate(line):
                if c == '#':
                    canvas[row * 8 + gy, (col + i) * 4 + gx] = color
        colors[(row, col + i)] = color


def legalise(canvas):
    """Per 4x8 cell: background + the 3 colours that lose the least. Returns screen, colour RAM
    and bitmap bytes."""
    screen = bytearray(1024)
    colram = bytearray(1024)
    bitmap = bytearray(8000)
    pal = np.array(PALETTE, dtype=np.int32)
    dist = ((pal[:, None, :] - pal[None, :, :]) ** 2).sum(axis=2)
    for r in range(25):
        for c in range(40):
            cell = canvas[r * 8:r * 8 + 8, c * 4:c * 4 + 4]
            cnt = np.bincount(cell.ravel(), minlength=16)
            cnt[0] = 0
            cand = [int(i) for i in np.argsort(-cnt, kind='stable')[:7] if cnt[i] > 0]
            best = (0, [])
            best_err = None
            for subset in itertools.combinations(cand, min(3, len(cand))):
                allowed = [0] + list(subset)
                err = sum(int(cnt[v]) * min(dist[v][a] for a in allowed) for v in cand)
                if best_err is None or err < best_err:
                    best_err, best = err, subset
            keep = list(best)
            slot = {0: 0}
            for n, col in enumerate(keep):
                slot[col] = n + 1                     # 1: screen high nibble, 2: low nibble, 3: colour RAM
            allowed = [0] + keep
            screen[r * 40 + c] = ((keep[0] if len(keep) > 0 else 0) << 4) | (keep[1] if len(keep) > 1 else 0)
            colram[r * 40 + c] = keep[2] if len(keep) > 2 else 0
            for y in range(8):
                byte = 0
                for x in range(4):
                    v = int(cell[y, x])
                    if v not in slot:                 # drop to the nearest colour the cell has
                        v = min(allowed, key=lambda a: dist[v][a])
                    cell[y, x] = v
                    byte = (byte << 2) | slot[v]
                bitmap[(r * 40 + c) * 8 + y] = byte
    return screen, colram, bitmap


def main():
    canvas = convert()
    texts = {}
    draw_text(canvas, texts, "HI-SCORE", LABEL_COL, TEXT_ROWS[0], CYAN)
    draw_text(canvas, texts, "PRESS FIRE", 15, TEXT_ROWS[1], YELLOW)
    for i in range(6):                                # the digits are drawn by the game; reserve their colour
        texts[(TEXT_ROWS[0], DIGITS_COL + i)] = WHITE
    screen, colram, bitmap = legalise(canvas)
    for (r, c), color in texts.items():               # text cells: glyph pixels are colour %11
        colram[r * 40 + c] = color
    # glyph pixels were drawn as palette colours; in text cells they must be slot 3
    for (r, c), color in texts.items():
        for y in range(8):
            byte = 0
            for x in range(4):
                v = canvas[r * 8 + y, c * 4 + x]
                byte = (byte << 2) | (3 if v else 0)
            bitmap[(r * 40 + c) * 8 + y] = byte
        screen[r * 40 + c] = 0
    with open('src/title.bin', 'wb') as f:
        f.write(colram[:1024] + screen[:1024] + bitmap)
    lines = ["; Hi-score digit glyphs for the title picture (multicolor bitmap, colour %11), 8 bytes each.",
             "; Generated by tools/gen_title.py: do not edit.", "title_digits:"]
    for d in "0123456789":
        rows = []
        for line in glyph(d) + ["..."]:
            byte = 0
            for x in range(4):
                byte = (byte << 2) | (3 if x < 3 and line[x] == '#' else 0)
            rows.append("$%02x" % byte)
        lines.append("    !byte " + ",".join(rows) + "   ; " + d)
    open('src/title_font.asm', 'w').write("\n".join(lines) + "\n")
    if len(sys.argv) > 1:                             # preview as the C64 would show it (2x1 pixels)
        im = Image.new('RGB', (W, H))
        im.putdata([PALETTE[v] for v in canvas.ravel()])
        im.resize((W * 2 * 2, H * 2), Image.NEAREST).save(sys.argv[1])


main()
