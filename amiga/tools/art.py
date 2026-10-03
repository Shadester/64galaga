"""Pixel art of the Amiga game, at 1-pixel resolution, in a 32-colour palette (5 bitplanes).

The aliens start from the C64 art (12 multicolour pixels wide, from ../c64/src/art.asm): it is doubled with an edge-smoothing
algorithm (Scale2x, so diagonals stay diagonals) and shaded (light where the sprite meets the background at the upper left,
dark at the lower right). The ship, the captive and the small things are drawn by hand as text rows.
Every letter of the art is one palette entry (PALETTE); '.' is transparent."""

# letter, rgb. The index of a letter is its place in this list (0 is the background, black).
PALETTE = [
    ('K', (0, 0, 0)),                 # 0 black (also an opaque black in a sprite)
    ('w', (255, 255, 255)),           # 1 white
    ('R', (238, 34, 0)),              # 2 text red
    ('a', (36, 56, 190)), ('b', (68, 102, 255)), ('c', (150, 182, 255)),        # 3-5 blue: dark, mid, light (the bee, the ship)
    ('d', (150, 16, 0)), ('e', (238, 40, 8)), ('f', (255, 140, 110)),           # 6-8 red (the butterfly, the ship)
    ('g', (0, 110, 44)), ('h', (0, 204, 68)), ('i', (150, 255, 160)),           # 9-11 green (the boss)
    ('j', (110, 30, 140)), ('k', (204, 68, 221)), ('l', (236, 176, 248)),       # 12-14 purple (the boss, hit)
    ('m', (190, 96, 130)), ('n', (255, 150, 184)), ('o', (255, 216, 232)),      # 15-17 pink (the captive)
    ('y', (255, 255, 0)), ('Y', (200, 150, 0)),                                 # 18-19 yellow, dark yellow
    ('C', (0, 204, 221)), ('D', (0, 120, 140)),                                 # 20-21 cyan, dark cyan
    ('O', (255, 136, 0)), ('P', (176, 68, 0)),                                  # 22-23 orange, dark orange
    ('S', (206, 206, 226)), ('s', (132, 132, 164)),                             # 24-25 light grey, mid grey (the ship)
    ('1', (60, 60, 96)), ('2', (210, 210, 240)), ('3', (30, 30, 52)),           # 26-28: stars (hardware sprites 4 and 5 use colours 25, 26, 27: mid, dim, bright), 28 spare
    ('B', (40, 90, 210)), ('L', (140, 190, 255)),                               # 29-30 the beam
    ('t', (40, 40, 70)),                                                        # 31 text shadow
]
PEN = {'.': 0}
for i, (ch, _) in enumerate(PALETTE):
    PEN[ch] = i
COLOURS = [rgb for _, rgb in PALETTE]
assert len(PALETTE) == 32

BODY = {'b': 'abc', 'r': 'def', 'g': 'ghi', 'p': 'jkl', 'n': 'mno', 'w': 'sSw', 'O': 'POy'}   # kind -> dark, mid, light letters
ACCENT = {'y': 'yY', 'c': 'CD'}                               # bright, dark


def scale2x(g):
    """Scale2x (AdvMAME2x): doubles a picture and keeps the diagonals smooth. g: rows of one-character cells."""
    h, w = len(g), len(g[0])

    def at(x, y):
        return g[min(max(y, 0), h - 1)][min(max(x, 0), w - 1)] if 0 <= x < w and 0 <= y < h else '.'
    out = []
    for y in range(h):
        r0, r1 = [], []
        for x in range(w):
            p, a, b, c, d = at(x, y), at(x, y - 1), at(x + 1, y), at(x - 1, y), at(x, y + 1)
            e0 = a if (c == a and c != d and a != b) else p
            e1 = b if (a == b and a != c and b != d) else p
            e2 = c if (d == c and d != b and c != a) else p
            e3 = d if (b == d and b != a and d != c) else p
            r0 += [e0, e1]
            r1 += [e2, e3]
        out += [r0, r1]
    return out


def shade(g, own, radius=3, t1=0.08):
    """Kinds ('.', 'o' own colour, 'y', 'c') -> art letters. The sprite is lit from the upper left: the height of the surface is the
    blurred shape, and the slope towards the light decides the tone (light, mid, dark). That rounds the body."""
    h, w = len(g), len(g[0])

    def solid(x, y):
        return 1.0 if 0 <= x < w and 0 <= y < h and g[y][x] != '.' else 0.0
    n = (2 * radius + 1) ** 2

    def height(x, y):
        return sum(solid(x + i, y + j) for i in range(-radius, radius + 1) for j in range(-radius, radius + 1)) / n
    rows = []
    for y in range(h):
        r = ''
        for x in range(w):
            k = g[y][x]
            if k == '.':
                r += '.'
                continue
            slope = (height(x + 1, y) - height(x - 1, y)) + (height(x, y + 1) - height(x, y - 1))     # > 0: faces the light
            tone = 2 if slope > t1 else 0 if slope < -t1 else 1
            if k == 'o' or k in BODY:
                r += BODY[own if k == 'o' else k][tone]
            elif k == 'x':                                       # the dark / light tone of the body, whatever the light says
                r += BODY[own][0]
            elif k == 'z':
                r += BODY[own][2]
            elif k in ACCENT:
                br, dk = ACCENT[k]
                r += dk if tone == 0 else br
            else:                                                # any other letter is a colour of the palette
                r += k
        rows.append(r)
    return rows


def alien(c64_rows, own):
    """c64_rows: the 12-character rows of a C64 sprite (. y o c), cropped at the bottom. -> 24 wide art, double the height."""
    return shade(scale2x([list(r) for r in c64_rows]), own)


# ---- the ship: the shape as kinds (w white, b blue, r red, c cyan, y yellow); the same shading as the aliens ----
SHIP_HALF = [
    ".........w",
    ".........w",
    "........ww",
    "........ww",
    ".......www",
    ".......wwc",
    ".......wwc",
    ".......wwc",
    "......wwwc",
    "......wwww",
    ".r....wwww",
    ".r....wwww",
    ".r...bwwww",
    ".rr..bbwww",
    ".rrb.bbbww",
    ".rbbbbbbbw",
    "rrbbbbbbbb",
    "rrbbbbbbbb",
    "rrbbbbbwbb",
    ".rbbb..wbb",
    "......rr.w",
    "......yy..",
]


def mirror(half):
    return [r + r[::-1] for r in half]


def ship(remap=None):
    g = [list(r) for r in mirror(SHIP_HALF)]
    if remap:
        g = [[remap.get(ch, ch) for ch in r] for r in g]
    return shade(g, 'b', radius=2, t1=0.08)


def captive():
    """The same ship, red and pink (the fighter that the boss has captured)."""
    return ship({'w': 'n', 'b': 'r', 'r': 'y'})


def mini(rows, factor=2):
    """Every `factor`-th pixel: the ship for the lives at the bottom."""
    g = [[ch for ch in r[::factor]] for r in rows[::factor]]
    return [''.join(r) for r in g]


def small_ship():
    g = [list(r) for r in mirror(SHIP_HALF)]
    g = [r[::2] for r in g[::2]]
    return shade(g, 'b', radius=1, t1=0.12)


PBUL = ['Cw', 'Cw', 'Cw', 'CC', 'CC', 'CC', 'DC', 'DC', 'D.', 'D.']
EBUL = ['.yy.', 'yyyy', 'yeey', 'yeey', 'deed', 'deed', 'deed', 'deed', '.dd.']

# ---- the aliens: our own 16 x 16 art of ../psp/art.h (the same pictures as the other ports), 1.5 times as big: 24 wide, as on the C64 ----
import os
import re

_H = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'psp', 'art.h')).read()
PSP = {m.group(1): re.findall(r'"([^"]*)"', m.group(2)) for m in re.finditer(r'static ArtRows art_(\w+) = \{(.*?)\};', _H, re.S)}
LETTER = {'y': 'y', 'Y': 'Y', 'c': 'C', 'w': 'w', 'k': 'K', 'o': 'O', 'r': 'e', 'b': 'b', 'g': 's'}
HALF12 = [0, 1, 1, 2, 3, 3, 4, 5, 5, 6, 7, 7]               # 8 columns of the left half -> 12 (every third one doubled), then mirrored


def from_psp(name, own):
    """The 16 x 16 art `name` (left half given) as 24 pixels wide, 1.5 times as high; m, M, n are the own colour's mid, light and dark tones."""
    rows = PSP[name]
    used = [y for y in range(16) if rows[y].strip('.')]
    rows = rows[used[0]:used[-1] + 1]
    tone = {'m': BODY[own][1], 'M': BODY[own][2], 'n': BODY[own][0]}
    ry = [i * 2 // 3 for i in range(len(rows) * 3 // 2)]
    out = []
    for y in ry:
        half = ''.join((tone.get(rows[y][x]) or LETTER.get(rows[y][x], '.')) for x in HALF12)
        out.append(half + half[::-1])
    return out


def hand(name):
    kind, f = name.split('_')
    base = {'bee': 'bee', 'bfly': 'bfly', 'boss': 'boss', 'bossp': 'boss'}[kind]
    own = {'bee': 'b', 'bfly': 'r', 'boss': 'g', 'bossp': 'p'}[kind]
    return from_psp(f'{base}_{f}', own)


def ship_psp(cols=(0, 1, 2, 3, 3, 4, 5, 6, 7, 7), height=22, remap=None):
    """The fighter of psp/art.h: 20 pixels wide (10 columns mirrored) and `height` rows. The art has its own shading, so it is not shaded again."""
    rows = PSP['player']
    used = [y for y in range(16) if rows[y].strip('.')]
    rows = rows[used[0]:used[-1] + 1]
    out = []
    for i in range(height):
        half = ''.join(LETTER.get(rows[i * len(rows) // height][x], '.') for x in cols)
        row = half + half[::-1]
        out.append(''.join((remap or {}).get(ch, ch) for ch in row))
    return out


def ship():
    return ship_psp()


def captive():
    """The same ship, red and pink (the fighter that the boss has captured)."""
    return ship_psp(remap={'w': 'n', 'b': 'e', 'e': 'y', 'C': 'o'})


def small_ship():
    return ship_psp(cols=(0, 1, 3, 4, 6, 7)[:5], height=11)


EXTRA = [ship(), captive(), small_ship()]
