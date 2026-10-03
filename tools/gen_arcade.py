#!/usr/bin/env python3
"""Make psp/arcade_data.h: the numbers of the arcade Galaga that the ports use (see ARCADE.md).

The numbers come from tomcoolpxl/cool8-cpu (MIT), tools/galaga_paths.py and tools/galaga_dives.py: a Python model of the arcade
program, made from the disassembly hackbar/galaga. The model is not in this repo. Put a checkout of it somewhere and run:

    ARCADE_REF=/path/to/cool8-cpu python3 tools/gen_arcade.py [preview.png]

What is made (rank 3, the normal arcade setting):
  - the entry flight paths, as integer steps per game tick (50 Hz, our coordinates), one for each path the 26 stages use;
  - for each of the 18 stage rows, the launch list of the entry waves (tick, formation slot, path);
  - the 40 formation slots (x, y) in our coordinates;
  - the attack parameters of each stage (`stage_parms`) and the three timer tables;
  - the first 26 stages: which row, and whether it is a challenge stage.
Our coordinates: C64 sprite coordinates (x 24..343, y 50..249), the top left corner of a 24 x 21 sprite.
The arcade screen (224 x 288, sprites 16 x 16) is scaled in X by 320 / 224; Y is bent so that the formation rows are 28 px apart (`warp_y`).
No picture or sound of the arcade is used.
"""
import os
import sys

ref = os.environ.get('ARCADE_REF')
if not ref:
    sys.exit('set ARCADE_REF to a checkout of tomcoolpxl/cool8-cpu')
sys.path.insert(0, os.path.join(ref, 'tools'))
import galaga_paths as gp          # noqa: E402
import galaga_dives as gd          # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
RANK = 3
STAGES = 26
SX = 320 / 224
TICK = 5 / 6                       # arcade frames (60 Hz) -> game ticks (50 Hz)
SPRITE_W, SPRITE_H = 24, 21        # C64 sprite; the arcade one is 16 x 16


# The arcade rows are 12..16 px apart, our sprites are 21 px high: the formation rows must be 28 px apart. So Y is not scaled
# by one factor: it is bent between these knots (arcade Y of the five rows -> our Y), above and below them with their own slope.
Y_KNOTS = [(76, 72), (92, 100), (104, 128), (116, 156), (128, 184)]
Y_ABOVE, Y_BELOW = 1.0, 0.4
BREATH_Y = 0.8                   # the rows breathe 0.8 px for each arcade px (they are 28 px apart already, and the ship is below)


def warp_y(y):
    if y <= Y_KNOTS[0][0]:
        return Y_KNOTS[0][1] + (y - Y_KNOTS[0][0]) * Y_ABOVE
    for (a0, b0), (a1, b1) in zip(Y_KNOTS, Y_KNOTS[1:]):
        if y <= a1:
            return b0 + (y - a0) * (b1 - b0) / (a1 - a0)
    return Y_KNOTS[-1][1] + (y - Y_KNOTS[-1][0]) * Y_BELOW


def to_ours(x, y):
    """Sprite register (x, y) of the arcade -> top left corner of our sprite."""
    return (24 + (x - 17 + 8) * SX - SPRITE_W / 2, warp_y(y))


# --- slots: our index -> arcade object. 0..3 boss, 4..19 butterfly, 20..39 bee
BOSS = list(range(0x30, 0x38, 2))
RED = list(range(0x40, 0x60, 2))
BEE = list(range(0x08, 0x30, 2))
SLOT_OBJ = BOSS + RED + BEE
OBJ_SLOT = {o: i for i, o in enumerate(SLOT_OBJ)}


def home(obj):
    return to_ours(*gp.Formation().origin_xy(obj))


def final_segment_start(track):
    """Index where the last path segment (the straight run to the slot) begins: our own homing replaces it."""
    idx = [i for i, r in enumerate(track) if r['event'] and 'seg' in r['event']]
    return idx[-1] if idx and track[-1]['event'] == 'HOME' else len(track)


def unwrap(track):
    """The arcade X is 8 bits and Y 9 bits: a path that leaves the screen wraps round. Make it continuous; stop at 'END'."""
    out, ox, oy = [], 0, 0
    for i, r in enumerate(track):
        if i and abs(r['x'] + ox - out[-1][0]) > 128:
            ox += 256 if out[-1][0] > r['x'] + ox else -256
        if i and abs(r['y'] + oy - out[-1][1]) > 256:
            oy += 512 if out[-1][1] > r['y'] + oy else -512
        out.append((r['x'] + ox, r['y'] + oy))
        if r['event'] and 'END' in r['event']:
            break
    return out


def resample(track, n_end):
    pts = [to_ours(x, y) for x, y in unwrap(track[:n_end])]
    out, t = [], 0.0
    while t <= len(pts) - 1:
        i = int(t)
        f = t - i
        j = min(i + 1, len(pts) - 1)
        out.append((pts[i][0] + (pts[j][0] - pts[i][0]) * f, pts[i][1] + (pts[j][1] - pts[i][1]) * f))
        t += 1 / TICK
    return out


def steps(pts):
    r = [(round(x), round(y)) for x, y in pts]
    return r[0], [(r[k + 1][0] - r[k][0], r[k + 1][1] - r[k][1]) for k in range(len(r) - 1)]


# Dive paths from the formation: label, arcade path name, the rows of the formation that use it (0 boss, 1..2 butterfly, 3..4 bee).
# A butterfly dive is the same as the model's until frame 105; then it aims at the ship (so the ship's position decides): we stop there
# and the game steers. The bee and boss dives do not depend on the ship.
DIVES = [('db_flv_atk_yllw', (3, 4), None), ('db_flv_atk_red', (1, 2), 105), ('db_flv_0411', (0, 1, 2), None)]
ROW_Y = [76, 92, 104, 116, 128]
OFF_Y = 255                     # our y where a diver has left the screen


def dive_tracks():
    f = gp.Formation()
    exemplar = {}
    for o in SLOT_OBJ:
        exemplar.setdefault((ROW_Y.index(f.origin_xy(o)[1]), (o >> 1) & 1, o < 0x30 or o >= 0x40, o), o)
    out = {}
    for li, (name, rows, cut) in enumerate(DIVES):
        for row in rows:
            for side in (0, 1):
                obj = next(o for (r, sd, _, o) in sorted(exemplar) if r == row and sd == side and
                           ((name != 'db_flv_atk_yllw') or o < 0x30) and ((name != 'db_flv_atk_red') or o >= 0x40) and
                           ((name != 'db_flv_0411') or o >= 0x30))
                m = gd.gp.simulate_dive(obj, name, fighter_x=0x7A, breathe=False)
                tr = m.tracks[obj]
                pts = resample(tr, cut or len(tr))
                for k, (x, y) in enumerate(pts):
                    if y >= OFF_Y:
                        pts = pts[:k + 1]
                        break
                out[(li, row, side)] = (steps(pts)[1], round(len(tr) * TICK))   # the steps, and the ticks of the whole dive incl. the way back
    return out


def main():
    rows = {}                      # (kind, row offset) -> first stage that uses it
    for st in range(1, STAGES + 1):
        k, off, _ = gp.stage_row(st, RANK)
        rows.setdefault((k, off), st)
    row_ids = {key: i for i, key in enumerate(rows)}
    paths, path_id = [], {}        # token -> index
    waves = []
    for key, st in rows.items():
        m, launches, _ = gp.simulate_stage(st, RANK)
        chal = key[0] == 'challenge'
        wl = []
        for x in launches:
            o = x['obj']
            tr = m.tracks[o]
            tok = x['token']
            if tok not in path_id:
                end = len(tr) if chal else final_segment_start(tr)
                start, st_ = steps(resample(tr, end))
                path_id[tok] = len(paths)
                paths.append((tok, start, st_))
            slot = OBJ_SLOT.get(o, -1)          # -1: a "transient", an extra enemy that is not part of the formation
            wl.append((round(x['tick'] * TICK), slot, path_id[tok]))
        waves.append((key, wl, gp.stage_row(st, RANK)[2][:2]))
    out = ['/* Generated by tools/gen_arcade.py: do not edit. See ARCADE.md.',
           ' * Numbers of the arcade Galaga from tomcoolpxl/cool8-cpu (MIT), a model made from the disassembly hackbar/galaga.',
           ' * Rank 3. Coordinates: C64 sprite coordinates. Paths: one step per game tick (50 Hz). */',
           '#define ARC_NPATH %d' % len(paths), '#define ARC_NSTAGE %d' % STAGES,
           '#define ARC_NROW %d' % len(waves), '']
    for i, (tok, start, st_) in enumerate(paths):
        out.append('static const signed char arc_p%d[] = {%s};' % (i, ','.join('%d,%d' % d for d in st_)))
    out.append('static const struct { short sx, sy, n, bt; const signed char *d; } arc_path[ARC_NPATH] = {')
    out += ['    {%d, %d, %d, %d, arc_p%d},' % (s[0], s[1], len(d), 68 if t & 1 else 8, i) for i, (t, s, d) in enumerate(paths)]
    out += ['};', '']
    out.append('/* 40 formation slots: 0..3 boss, 4..19 butterfly, 20..39 bee */')
    out.append('static const short arc_slot[40][2] = {')
    out += ['    {%d, %d},' % tuple(round(v) for v in home(o)) for o in SLOT_OBJ]
    out += ['};', '']
    out.append('/* entry launches of a row: tick, slot (-1 = transient), path */')
    for i, (key, wl, hdr) in enumerate(waves):
        out.append('static const short arc_w%d[][3] = {%s};' % (i, ','.join('{%d,%d,%d}' % w for w in wl)))
    out.append('/* hdr0: frames between two bombs of a flyer (255: none); hdr1: the bomb flags of an enemy that flies in and may drop bombs */')
    out.append('static const struct { char challenge; short n; const short (*l)[3]; unsigned char hdr0, hdr1; } arc_row[ARC_NROW] = {')
    out += ['    {%d, %d, arc_w%d, %d, %d},' % (key[0] == 'challenge', len(wl), i, hdr[0], hdr[1]) for i, (key, wl, hdr) in enumerate(waves)]
    out += ['};', '']
    out.append('/* stage 1.. : row, then the parameters p0..p10 of stage_parms (max bombers p4 -> p5, beam step p6, ...) */')
    out.append('static const unsigned char arc_stage[ARC_NSTAGE][12] = {')
    for st in range(1, STAGES + 1):
        k, off, _ = gp.stage_row(st, RANK)
        p = gp.stage_parms(st, RANK)
        out.append('    {%d, %s},' % (row_ids[(k, off)], ','.join(str(v) for v in p)))
    out += ['};', '']
    dv = dive_tracks()
    keys = sorted(dv)
    for i, k in enumerate(keys):
        out.append('static const signed char arc_d%d[] = {%s};' % (i, ','.join('%d,%d' % d for d in dv[k][0])))
    out.append('/* dive paths: steps per tick from the slot, in our coordinates; label (0 bee, 1 butterfly: stops where it aims, 2 boss and wingmen) */')
    out.append('static const struct { short n, total; const signed char *d; } arc_dive_path[] = {')
    out += ['    {%d, %d, arc_d%d},' % (len(dv[k][0]), dv[k][1], i) for i, k in enumerate(keys)]
    out += ['};']
    out.append('/* arc_dive[label][row][side]: index in arc_dive_path, or -1 */')
    out.append('static const signed char arc_dive[3][5][2] = {')
    for li in range(3):
        out.append('    {%s},' % ','.join('{%d,%d}' % tuple(keys.index((li, r, sd)) if (li, r, sd) in dv else -1 for sd in (0, 1)) for r in range(5)))
    out += ['};', '']
    out.append('/* of each slot: its row (0 boss .. 4 bee) and side (0 left, 1 right) */')
    f = gp.Formation()
    out.append('static const unsigned char arc_slot_row[40] = {%s};' % ','.join(str(ROW_Y.index(f.origin_xy(o)[1])) for o in SLOT_OBJ))
    out.append('static const unsigned char arc_slot_side[40] = {%s};' % ','.join(str((o >> 1) & 1) for o in SLOT_OBJ))
    out.append('/* which slots may drop bombs while they fly in (bit of d_2908) */')
    out.append('static const unsigned char arc_entry_bomb[40] = {%s};' % ','.join(str(gd.BOMB_FLAG.get(o, 0)) for o in SLOT_OBJ))
    out.append('/* the six butterflies that escort a boss, in the order of the arcade table (d_1d2c) */')
    out.append('static const unsigned char arc_wingmen[6] = {%s};' % ','.join(str(OBJ_SLOT[o]) for o in gd.D_1D2C_WINGMEN))
    out.append('')
    out.append('/* formation breathing: 64 steps of 4 arcade frames; the offset (our pixels) of the columns 0..4 (the right half is the mirror) and of the rows 0..4 */')
    out.append('static const signed char arc_breath[64][10] = {')
    fm = gp.Formation()
    fm.breathe_active = True
    base_c = [fm.spcoords[2 * i] for i in range(10)]
    base_r = [fm.spcoords[20 + 2 * i] | (fm.spcoords[21 + 2 * i] << 8) for i in range(6)]
    for fr in range(1, 257):
        fm.f_1DE6(fr)
        if fr & 3 == 0:
            cols = [fm.spcoords[2 * i] - base_c[i] for i in range(5)]
            rows = [(fm.spcoords[20 + 2 * i] | (fm.spcoords[21 + 2 * i] << 8)) - base_r[i] for i in range(1, 6)]
            out.append('    {%s},' % ','.join(str(v) for v in [round(c * SX) for c in cols] + [round(r * BREATH_Y) for r in rows]))
    out += ['};', '']
    out.append('static const unsigned char arc_slot_col[40] = {%s};' % ','.join(str((round(gp.Formation().origin_xy(o)[0]) - 49) // 16) for o in SLOT_OBJ))
    out.append('')
    out.append('/* sortie timer reloads (arcade counts of 16 frames) and bomb flags, as in the arcade tables */')
    for name, tab in (('arc_red_reload', gd.D_08CD), ('arc_bee_reload', gd.D_08EB), ('arc_bomb_tab', gd.D_0909)):
        out.append('static const unsigned char %s[] = {%s};' % (name, ','.join(str(v) for v in tab)))
    text = '\n'.join(out) + '\n'
    open(os.path.join(ROOT, 'psp', 'arcade_data.h'), 'w').write(text)
    print('psp/arcade_data.h', len(text), 'bytes;', len(paths), 'paths,', len(waves), 'rows')
    if len(sys.argv) > 1:
        preview(sys.argv[1], paths, waves)


def preview(fn, paths, waves):
    from PIL import Image, ImageDraw
    S = 2
    img = Image.new('RGB', (320 * S, 200 * S), (8, 8, 24))
    d = ImageDraw.Draw(img)
    for tok, (x, y), st_ in paths:
        pts = [(x, y)]
        for dx, dy in st_:
            pts.append((pts[-1][0] + dx, pts[-1][1] + dy))
        d.line([((px - 24) * S, (py - 50) * S) for px, py in pts], fill=(120 + tok * 37 % 135, 90 + tok * 71 % 165, 200))
    for o in SLOT_OBJ:
        x, y = home(o)
        d.rectangle([(x - 24) * S, (y - 50) * S, (x - 24 + SPRITE_W) * S, (y - 50 + SPRITE_H) * S], outline=(90, 90, 90))
    img.save(fn)


if __name__ == '__main__':
    main()
