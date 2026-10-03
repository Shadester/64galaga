#include "video.h"
#include "assets.h"
#include "game.h"                                  /* NAL and EBN: 40 aliens and 8 bombs */

#define CUSTOM ((volatile u16 *)0xdff000)
#define W(reg) (CUSTOM[(reg) / 2])
#define L(reg) (*(volatile u32 *)(0xdff000 + (reg)))
#define DMACONR W(0x002)

/* A bitmap is 448 pixels wide (the screen has 64 pixels of guard on each side: a sprite needs no clipping at the sides, and the playfield below
 * the hud can be shown scrolled by up to 48 pixels): 56 bytes a row of a plane, NPL planes a line (32 colours). */
#define NPL 5
#define STRIDE 56
#define ROWB (STRIDE * NPL)
#define GUARD 64
#define BITMAP_BYTES (ROWB * SCREEN_H)
#define MAX_RECTS 96
#define MAX_OBJ (NAL + 3 + 4 + EBN)                /* sprite slots (main.c): aliens, ship, dual, captive, player shots, bombs */
#define MAX_TEXTS 8
#define MAX_TEXT_CELLS 26                   /* a text of 23 characters, two cells more */

typedef struct { s16 xw, wd, y, h; } Rect;       /* words from the left of the bitmap, width in words, lines */
typedef struct {
    Rect rect[MAX_RECTS];                         /* what the CPU drew (text, beam): cleared at the start of the next use of this bitmap */
    int nrect;
} Dirty;

typedef struct { Rect r; int skip; u8 has; } Place;  /* where an Obj is in a bitmap (computed once, when it is drawn) */

extern volatile u32 vbl_count;
static u32 published;                             /* vbl_count when a bitmap was handed to the copper: it is shown at the next vertical blank */
#define NBMP 3                                    /* three bitmaps: one shown, one waiting for its vertical blank, one drawn into: no waiting */
static u16 bitmap[NBMP][BITMAP_BYTES / 2];
static Dirty dirty[NBMP];
static Obj drawn[NBMP][MAX_OBJ];                  /* the sprites that a bitmap shows */
static Place placed[NBMP][MAX_OBJ];
Obj want[MAX_OBJ];                                /* the sprites of this frame (video_bob in video.h writes them) */
static int back;                                  /* the bitmap that is drawn into */
static int shown = 0, pending = -1;               /* the bitmap on the screen; the one handed to the copper at the last video_end, not yet shown */
#define COPLEN 160
static u16 copper[NBMP][COPLEN];                  /* a copper list for each bitmap (see build_copper) */
static int cop_title[NBMP];                       /* the palette that is in a list: 1 title, 0 game */
static int scroll_d;                              /* this frame: the playfield below the hud is shown shifted to the right by this many pixels */
static const u16 no_sprite[2] = {0, 0};          /* a sprite list with nothing in it */
static void stars_init(void);
static int cop_pal, cop_bpl, cop_spr, cop_bpl2, cop_con1;   /* indexes in the copper list: the palette values, the bitplane pointers (hud, playfield), the sprite pointers, BPLCON1 of the playfield */

/* What the frame asks for. Nothing is drawn until video_end: a sprite that has not changed since this bitmap was drawn last
 * is not drawn again (the formation moves once in about 9 ticks), unless something else is cleared or drawn over it. */
typedef struct { char s[24]; s16 x, y, colour; } TextReq;
static TextReq text_req[MAX_TEXTS];
static int ntext;
static struct { s16 x, y, rows, phase; } beam_req;                   /* rows 0: no beam */
static Rect old_ov[MAX_RECTS], new_ov[MAX_RECTS];                    /* rects of text and beam: cleared at the start / drawn now */
static int nold_ov, nnew_ov;

static void wait_blit(void) {
    (void)DMACONR;
    while (DMACONR & 0x4000) ;
}
void video_wait_blitter(void) { wait_blit(); }

static void copper_set_palette(int b, const u16 *pal) {
    int i;
    for (i = 0; i < 32; ++i) copper[b][cop_pal + 2 * i] = pal[i];
}

/* The copper list of a bitmap: the setup, the palette, the bitplane pointers for the hud (lines 0 .. TOP - 1, never scrolled), the sprite pointers, then
 * at the end of the line TOP - 1 (in the horizontal blank) the pointers and BPLCON1 for the playfield, which is shown scrolled by scroll_d.
 * The fetch starts one word early (DDFSTRT 0x30): the first word is hidden, and BPLCON1 delays the picture to the right by 0 .. 15 pixels. */
static void build_copper(int b) {
    u16 *c = copper[b];
    int i;
#define MOVE(reg, val) (*c++ = (reg), *c++ = (val))
    MOVE(0x100, 0x5200);                          /* BPLCON0: 5 bitplanes, lores, colour */
    MOVE(0x102, 0); MOVE(0x104, 4);               /* BPLCON1, BPLCON2 */
    MOVE(0x108, ROWB - 42); MOVE(0x10a, ROWB - 42);   /* BPL1MOD, BPL2MOD: the rest of the line of the planes (21 words are fetched) */
    MOVE(0x092, 0x30); MOVE(0x094, 0xd0);         /* DDFSTRT, DDFSTOP */
    MOVE(0x08e, 0x2c81); MOVE(0x090, 0x2cc1);     /* DIWSTRT, DIWSTOP: 320 x 256, PAL */
    cop_pal = c - copper[b] + 1;
    for (i = 0; i < 32; ++i) MOVE(0x180 + 2 * i, 0);
    cop_bpl = c - copper[b] + 1;
    for (i = 0; i < NPL; ++i) { MOVE(0xe0 + 4 * i, 0); MOVE(0xe2 + 4 * i, 0); }
    cop_spr = c - copper[b] + 1;
    for (i = 0; i < 8; ++i) { MOVE(0x120 + 4 * i, (u32)no_sprite >> 16); MOVE(0x122 + 4 * i, (u32)no_sprite & 0xffff); }
    *c++ = ((0x2c + TOP - 1) << 8) | 0xd9; *c++ = 0xfffe;     /* WAIT: the end of the last hud line, after the fetch */
    cop_bpl2 = c - copper[b] + 1;
    for (i = 0; i < NPL; ++i) { MOVE(0xe0 + 4 * i, 0); MOVE(0xe2 + 4 * i, 0); }
    cop_con1 = c - copper[b] + 1;
    MOVE(0x102, 0);
    *c++ = 0xffff; *c++ = 0xfffe;                 /* the end */
#undef MOVE
}

void video_init(void) {
    int i, b;
    for (b = 0; b < NBMP; ++b) {
        build_copper(b);
        copper_set_palette(b, game_palette);
        for (i = 0; i < NPL; ++i) {
            u32 p = (u32)bitmap[b] + GUARD / 8 - 2 + i * STRIDE;
            copper[b][cop_bpl + 4 * i] = p >> 16; copper[b][cop_bpl + 4 * i + 2] = p & 0xffff;
            copper[b][cop_bpl2 + 4 * i] = p >> 16; copper[b][cop_bpl2 + 4 * i + 2] = p & 0xffff;
        }
    }
    L(0x080) = (u32)copper[0];                    /* COP1LC */
    W(0x088) = 0;                                 /* COPJMP1 */
    stars_init();
    W(0x096) = 0x8fe0;                            /* DMACON: set, master, bitplanes, copper, blitter, sprites, and the blitter before the CPU */
    back = 1;
    shown = 0;
}

/* The playfield (below the hud) is shown shifted to the right by d pixels (-48 .. 48): the formation sways without being drawn again. Call it
 * in every frame, before the sprites: they are drawn at x - d. */
void video_scroll(int d) { scroll_d = d; }

static void clear_rect(const Rect *r) {
    wait_blit();
    W(0x040) = 0x0100;                            /* BLTCON0: D only, all minterm bits 0 = clear */
    W(0x042) = 0;
    W(0x066) = STRIDE - 2 * r->wd;                /* BLTDMOD */
    L(0x054) = (u32)bitmap[back] + r->y * ROWB + r->xw * 2;     /* BLTDPT */
    W(0x058) = ((r->h * NPL) << 6) | r->wd;         /* BLTSIZE: starts the blitter */
}

static int static_mode;                           /* drawing the static layer: it is drawn at once and not cleared in every frame */

static void add_dirty(int xw, int wd, int y, int h) {      /* the CPU drew here: clear it when this bitmap is used again */
    Dirty *d = &dirty[back];
    Rect *r;
    if (d->nrect >= MAX_RECTS) return;
    r = &d->rect[d->nrect++];
    r->xw = xw; r->wd = wd; r->y = y; r->h = h;
}

/* A bitmap that was handed to the copper is on the screen after the next vertical blank: from then on it is the shown one. This must be
 * checked whenever a bitmap is chosen or handed over, or the bitmap on the screen could be taken for a free one. */
static void settle_display(void) {
    if (pending >= 0 && vbl_count != published) { shown = pending; pending = -1; }
}

void video_begin(void) {
    Dirty *d;
    int i;
    settle_display();
    for (back = 0; back == shown || back == pending; ++back) ;                          /* the third one is free */
    d = &dirty[back];
    nold_ov = d->nrect;
    for (i = 0; i < d->nrect; ++i) { old_ov[i] = d->rect[i]; clear_rect(&d->rect[i]); }
    d->nrect = 0;
    for (i = 0; i < MAX_OBJ; ++i) want[i].id = -1;
    ntext = nnew_ov = 0;
    beam_req.rows = 0;
}

/* The hud (score, lives) changes seldom: it is drawn again in a bitmap only when the numbers have changed. */
static int static_key[NBMP][4] = {{-1, -1, -1, -1}, {-1, -1, -1, -1}, {-1, -1, -1, -1}};

int video_static_begin(int a, int b, int c, int d) {
    int *k = static_key[back];
    Rect top = {0, STRIDE / 2, 0, TOP};
    if (k[0] == a && k[1] == b && k[2] == c && k[3] == d) return 0;
    k[0] = a; k[1] = b; k[2] = c; k[3] = d;
    clear_rect(&top);
    wait_blit();
    static_mode = 1;
    return 1;
}

void video_static_end(void) { static_mode = 0; }

/* ---- the stars: hardware sprites 4 and 5 (the CPU is too slow to draw them: it gets few memory cycles while the screen is shown).
 * Each sprite channel shows many stars: a list of one-pixel objects, one below the other. Like in the arcade game, the stars
 * move down in fixed columns, in two layers (1 and 2 pixels a tick). Sprites 4 and 5 use the colours 25, 26 and 27 (mid, dim, bright). ---- */
#define STAR_N 12                                 /* stars in a layer */
#define STAR_H (SCREEN_H - 16 - TOP)              /* the stars stay between the hud and the lives */
#define STAR_HOFF 128                             /* hardware sprite position of the left edge of the screen (to check in the emulator) */
static s16 star_base[2][STAR_N], star_x[2][STAR_N];
static u8 star_col[2][STAR_N];
static u16 star_list[NBMP][2][STAR_N * 4 + 2];
static int star_scroll[2] = {-1, -1};             /* the offset of the layers (-1: no stars, the title screen) */

static void stars_init(void) {
    u32 r = 12345;
    int g, i;
    for (g = 0; g < 2; ++g)
        for (i = 0; i < STAR_N; ++i) {
            r = r * 1103515245u + 12345u;
            star_base[g][i] = i * (STAR_H / STAR_N) + ((r >> 16) % 9);                   /* ascending, at least 4 lines apart */
            star_x[g][i] = (r >> 20) % SCREEN_W;
            star_col[g][i] = g ? ((r >> 12) & 1 ? 3 : 1) : ((r >> 12) & 3 ? 2 : 1);      /* layer 0: dim; layer 1: bright and mid */
        }
}

/* The scroll offsets of the two layers, 0 .. STAR_H - 1 (the CPU is slow: no division here); a negative one: no stars */
void video_stars(int slow, int fast) {
    star_scroll[0] = slow; star_scroll[1] = fast;
}

static void build_stars(int b) {
    int g, k;
    for (g = 0; g < 2; ++g) {
        u16 *l = star_list[b][g];
        int n = 0, off = star_scroll[g], first = 0;
        if (off >= 0) {
            while (first < STAR_N && star_base[g][first] + off < STAR_H) ++first;          /* from here the stars wrapped to the top: they come first */
            for (k = 0; k < STAR_N; ++k) {
                int j = first + k, y, v, hs;
                if (j >= STAR_N) j -= STAR_N;
                y = star_base[g][j] + off;
                if (y >= STAR_H) y -= STAR_H;
                v = 0x2c + TOP + y;                                                         /* the beam line of the sprite */
                hs = STAR_HOFF + star_x[g][j];
                l[n++] = (v & 255) << 8 | (hs >> 1 & 255);                                  /* SPRxPOS */
                l[n++] = ((v + 1) & 255) << 8 | (v >> 8 & 1) << 2 | ((v + 1) >> 8 & 1) << 1 | (hs & 1);     /* SPRxCTL: stop one line below */
                l[n++] = star_col[g][j] & 1 ? 0x8000 : 0;                                   /* the pixel: plane A, plane B */
                l[n++] = star_col[g][j] & 2 ? 0x8000 : 0;
            }
        }
        l[n++] = 0; l[n] = 0;
    }
}

/* ---- sprites ---- */

/* The words of the bitmap that a sprite covers, clipped at the top (the hud) and the bottom. 0: nothing to draw. */
static int obj_rect(const Obj *o, Rect *r, int *skip_out) {
    const SpriteInfo *s;
    int w, h, skip = 0, y, xb, xw, top = static_mode ? 0 : TOP;     /* the static layer (hud) is above the playfield */
    if (o->id < 0) return 0;
    s = &sprites[o->id];
    w = s->w; h = s->h; y = o->y; xb = o->x + GUARD; xw = xb >> 4;
    if (xb < 0 || xw + w > STRIDE / 2 - 1) return 0;           /* the guard of 32 pixels is enough for every sprite we draw */
    if (y < top) { skip = top - y; y = top; }
    if (skip >= h) return 0;
    if (y + (h - skip) > SCREEN_H) h = SCREEN_H - y + skip;
    if (h <= skip) return 0;
    r->xw = xw; r->wd = w + 1; r->y = y; r->h = h - skip;
    *skip_out = skip;
    return 1;
}

static void blit_obj(const Obj *o, const Rect *r, int skip) {
    const SpriteInfo *s = &sprites[o->id];
    int w = s->w, rowwords = (w + 1) * NPL, sh = (o->x + GUARD) & 15;
    const u16 *bob = sprite_words + s->bob + skip * rowwords, *mask = sprite_words + s->mask + skip * rowwords;
    u32 dst = (u32)bitmap[back] + r->y * ROWB + r->xw * 2;
    wait_blit();
    W(0x040) = 0x0fca | (sh << 12);               /* BLTCON0: A, B, C, D; D = A B + /A C (A the mask, B the picture, C the screen) */
    W(0x042) = sh << 12;                          /* BLTCON1: the shift of B */
    W(0x044) = 0xffff; W(0x046) = 0xffff;         /* BLTAFWM, BLTALWM */
    W(0x064) = 0; W(0x062) = 0;                   /* BLTAMOD, BLTBMOD */
    W(0x060) = STRIDE - 2 * (w + 1); W(0x066) = STRIDE - 2 * (w + 1);   /* BLTCMOD, BLTDMOD */
    L(0x050) = (u32)mask;
    L(0x04c) = (u32)bob;
    L(0x048) = dst; L(0x054) = dst;
    W(0x058) = ((r->h * NPL) << 6) | (w + 1);
}

/* the cells (a bit for each word column, a u32 for each 16 lines) that a rect touches */
static u32 cell_bits(const Rect *r) { return ((1UL << r->wd) - 1) << r->xw; }

static void mark_cells(u32 *mark, const Rect *r) {
    u32 bits = cell_bits(r);
    int row;
    for (row = r->y >> 4; row <= (r->y + r->h - 1) >> 4; ++row) mark[row] |= bits;
}

static int cells_marked(const u32 *mark, const Rect *r) {
    u32 bits = cell_bits(r);
    int row;
    for (row = r->y >> 4; row <= (r->y + r->h - 1) >> 4; ++row) if (mark[row] & bits) return 1;
    return 0;
}

/* A sprite of the static layer (the lives): drawn at once. */
void video_static_bob(int id, int x, int y) {
    Obj o = {id, x, y};
    Rect r;
    int skip;
    if (obj_rect(&o, &r, &skip)) blit_obj(&o, &r, skip);
}

static void beam_now(void);

static void draw_sprites(void) {
    Place *pl = placed[back];
    Obj *dr = drawn[back];
    Rect oldr[MAX_OBJ];                           /* where a sprite was, if it changed (the CPU is slow: nothing is copied or computed twice) */
    u8 oldhas[MAX_OBJ], keep[MAX_OBJ];
    int s, i, again, changed = 0;
    for (s = 0; s < MAX_OBJ; ++s) {
        Obj *o = &dr[s], *n = &want[s];
        if (n->id == o->id && (n->id < 0 || (n->x == o->x && n->y == o->y))) {      /* the same sprite at the same place */
            keep[s] = pl[s].has;
            oldhas[s] = 0;
            continue;
        }
        oldhas[s] = pl[s].has;
        if (oldhas[s]) oldr[s] = pl[s].r;
        *o = *n;
        pl[s].has = obj_rect(n, &pl[s].r, &pl[s].skip);
        keep[s] = 0;
        ++changed;
    }
#ifdef NOSKIP                                     /* test: draw every sprite in every frame */
    for (s = 0; s < MAX_OBJ; ++s) { if (keep[s]) { oldhas[s] = 1; oldr[s] = pl[s].r; } keep[s] = 0; }
    changed = 1;
#endif
    if (changed || nold_ov || nnew_ov) {
        /* A sprite that stays is drawn again only if something is cleared or drawn over it. The screen is a grid of cells of 16 x 16
         * pixels: the cells that a changed sprite or a text touches are marked, and a sprite that stays is checked against the marks. */
        u32 mark[SCREEN_H / 16];
        for (i = 0; i < SCREEN_H / 16; ++i) mark[i] = 0;
        for (i = 0; i < nold_ov; ++i) mark_cells(mark, &old_ov[i]);
        for (i = 0; i < nnew_ov; ++i) mark_cells(mark, &new_ov[i]);
        for (s = 0; s < MAX_OBJ; ++s) {
            if (keep[s]) continue;
            if (oldhas[s]) mark_cells(mark, &oldr[s]);
            if (pl[s].has) mark_cells(mark, &pl[s].r);
        }
        do {
            again = 0;
            for (s = 0; s < MAX_OBJ; ++s) {
                if (!keep[s] || !cells_marked(mark, &pl[s].r)) continue;
                keep[s] = 0;                      /* it is cleared and drawn again, and so it marks its cells too */
                oldhas[s] = 1; oldr[s] = pl[s].r;
                mark_cells(mark, &pl[s].r);
                again = 1;
            }
        } while (again);
    }
    for (s = 0; s < MAX_OBJ; ++s) if (oldhas[s]) clear_rect(&oldr[s]);
    wait_blit();
    if (beam_req.rows) beam_now();                /* the beam is behind the sprites: drawn first (CPU) */
    for (s = 0; s < MAX_OBJ; ++s) if (!keep[s] && pl[s].has) blit_obj(&dr[s], &pl[s].r, pl[s].skip);
}

/* ---- text and the beam: the CPU draws them, after the sprites (the text) or before (the beam) ---- */

static int text_words(int xb, int n, int *wd) {           /* words that a text covers: a shift and the shadow make it two cells wider */
    *wd = ((xb + (n + 2) * 8 - 1) >> 4) - (xb >> 4) + 1;
    return xb >> 4;
}

/* The usual case (x a multiple of 8, no shift): text in whole cells, with a shadow of one pixel to the lower right (colour 31). */
static void text_aligned(const char *s, int x, int y, int colour) {
    int n = 0, xb, c, r, pl;
    u8 *row;
    for (; s[n]; ++n) ;
    xb = (x + GUARD) & ~7;
    for (r = 0; r < 9; ++r) {                     /* 8 rows of glyph and one of shadow */
        int carry = 0;
        row = (u8 *)bitmap[back] + (y + r) * ROWB + (xb >> 3);
        for (c = 0; c <= n; ++c, ++row) {
            int ch = c < n ? s[c] - 32 : -1;
            u8 main = 0, above = 0, sh;
            if (ch >= 0 && ch < 64) {
                if (r < 8) main = font_rows[ch * 8 + r];
                if (r > 0) above = font_rows[ch * 8 + r - 1];
            }
            sh = (above >> 1 | carry << 7) & ~main;          /* the shadow is the glyph of the row above, one pixel to the right */
            carry = above & 1;
            if (!(main | sh)) continue;
            for (pl = 0; pl < NPL; ++pl)
                row[pl * STRIDE] |= (colour >> pl & 1 ? main : 0) | (31 >> pl & 1 ? sh : 0);
        }
    }
}


/* Text with a shift: 8 x 8 cells, with a shadow of one pixel to the lower right (colour 31). x is exact: the glyphs are shifted by x mod 8 (the playfield is
 * shown scrolled, so a message must be drawn at x - the scroll). */
static void text_shifted(const char *s, int x, int y, int colour) {
    int n = 0, xb, c, r, pl, sh;
    u8 *row;
    u8 mrow[MAX_TEXT_CELLS], srow[MAX_TEXT_CELLS];
    for (; s[n]; ++n) ;
    xb = (x + GUARD) & ~7;
    sh = (x + GUARD) & 7;
    for (r = 0; r < 9; ++r) {                     /* 8 rows of glyph and one of shadow */
        for (c = 0; c < n + 2; ++c) mrow[c] = srow[c] = 0;
        for (c = 0; c < n; ++c) {
            int ch = s[c] - 32;
            u16 v;
            if (ch < 0 || ch >= 64) continue;
            if (r < 8) { v = (u16)(font_rows[ch * 8 + r] << 8) >> sh; mrow[c] |= v >> 8; mrow[c + 1] |= v & 255; }
            if (r > 0) { v = (u16)(font_rows[ch * 8 + r - 1] << 8) >> (sh + 1); srow[c] |= v >> 8; srow[c + 1] |= v & 255; }   /* the glyph of the row above, one pixel right */
        }
        row = (u8 *)bitmap[back] + (y + r) * ROWB + (xb >> 3);
        for (c = 0; c < n + 2; ++c, ++row) {
            u8 m = mrow[c], sd = srow[c] & ~m;
            if (!(m | sd)) continue;
            for (pl = 0; pl < NPL; ++pl)
                row[pl * STRIDE] |= (colour >> pl & 1 ? m : 0) | (31 >> pl & 1 ? sd : 0);
        }
    }
}

static void text_now(const char *s, int x, int y, int colour) {
    int n = 0, wd, xw;
    for (; s[n]; ++n) ;
    if ((x + GUARD) & 7) text_shifted(s, x, y, colour); else text_aligned(s, x, y, colour);
    if (!static_mode) { xw = text_words((x + GUARD) & ~7, n, &wd); add_dirty(xw, wd, y, 9); }
}

void video_text(const char *s, int x, int y, int colour) {
    TextReq *t;
    int n, wd, xw, i;
    if (static_mode) { wait_blit(); text_now(s, x, y, colour); return; }
    x -= scroll_d;
    if (ntext >= MAX_TEXTS || nnew_ov >= MAX_RECTS) return;
    t = &text_req[ntext++];
    for (n = 0; s[n] && n < 23; ++n) t->s[n] = s[n];
    t->s[n] = 0;
    t->x = x; t->y = y; t->colour = colour;
    xw = text_words((x + GUARD) & ~7, n, &wd);
    i = nnew_ov++;
    new_ov[i].xw = xw; new_ov[i].wd = wd; new_ov[i].y = y; new_ov[i].h = 9;
}

static const u8 beam_colours[4] = {20, 30, 1, 30};           /* cyan, light blue, white, light blue */

/* the beam: rows of 8 pixel cells that get wider, with a checkerboard in the colours of beam_colours */
static void beam_rect(int r, Rect *out) {
    int cells = 2 * r + 5, xb = beam_req.x - cells * 4 + GUARD;
    out->xw = xb >> 4; out->wd = ((xb + cells * 8 - 1) >> 4) - (xb >> 4) + 1; out->y = beam_req.y + r * 8; out->h = 8;
}

void video_beam(int x, int y, int rows, int phase) {
    int r;
    beam_req.x = x; beam_req.y = y; beam_req.rows = rows; beam_req.phase = phase;
    for (r = 0; r < rows && nnew_ov < MAX_RECTS; ++r) beam_rect(r, &new_ov[nnew_ov++]);
}

static void beam_now(void) {
    int r, k, line, pl;
    for (r = 0; r < beam_req.rows; ++r) {
        int cells = 2 * r + 5, xb = beam_req.x - cells * 4 + GUARD, yy = beam_req.y + r * 8;
        Rect rc;
        if (yy < TOP || yy + 8 > SCREEN_H) continue;
        for (k = 0; k < cells; ++k) {
            int col = beam_colours[(k + r + beam_req.phase) & 3];
            u8 *p = (u8 *)bitmap[back] + yy * ROWB + ((xb + k * 8) >> 3);
            for (line = 0; line < 8; ++line, p += ROWB)
                for (pl = 0; pl < NPL; ++pl)
                    if (col >> pl & 1) p[pl * STRIDE] |= (line + k) & 1 ? 0x55 : 0xaa;      /* a checkerboard */
        }
        beam_rect(r, &rc);
        add_dirty(rc.xw, rc.wd, rc.y, rc.h);
    }
}

static u8 has_title[NBMP];                                    /* the title picture is in this bitmap */

/* The title picture is copied once to each bitmap, and cleared when the game starts: it is not redrawn in every frame. */
void video_title(int on) {
    if (on && !has_title[back]) {
        wait_blit();
        W(0x040) = 0x09f0;                                     /* BLTCON0: A, D; D = A */
        W(0x042) = 0;
        W(0x044) = 0xffff; W(0x046) = 0xffff;
        W(0x064) = 0;                                          /* BLTAMOD */
        W(0x066) = STRIDE - 40;                                /* BLTDMOD: the guard of the bitmap */
        L(0x050) = (u32)title_words;
        L(0x054) = (u32)bitmap[back] + GUARD / 8;
        W(0x058) = ((TITLE_H * NPL) << 6) | 20;
        has_title[back] = 1;
        static_key[back][0] = -1;                              /* the title covers the hud: draw it again later */
    } else if (!on && has_title[back]) {
        Rect r = {0, STRIDE / 2, 0, TITLE_H};
        clear_rect(&r);
        has_title[back] = 0;
    }
}

void video_end(int title) {
    int i;
    wait_blit();
    draw_sprites();
    wait_blit();
    build_stars(back);
    for (i = 0; i < ntext; ++i) text_now(text_req[i].s, text_req[i].x, text_req[i].y, text_req[i].colour);
    if (cop_title[back] != title) { copper_set_palette(back, title ? title_palette : game_palette); cop_title[back] = title; }
    {
        int coarse = scroll_d >> 4, fine = scroll_d & 15;             /* floor: a negative shift is a smaller pointer and a bigger delay */
        u16 *c = copper[back];
        for (i = 0; i < NPL; ++i) {
            u32 p = (u32)bitmap[back] + GUARD / 8 - 2 + i * STRIDE, q = p - 2 * coarse + TOP * ROWB;   /* (the pointers go on from the next line, TOP) */
            c[cop_bpl + 4 * i] = p >> 16; c[cop_bpl + 4 * i + 2] = p & 0xffff;
            c[cop_bpl2 + 4 * i] = q >> 16; c[cop_bpl2 + 4 * i + 2] = q & 0xffff;
        }
        c[cop_con1] = fine * 0x11;
        for (i = 0; i < 2; ++i) {                  /* sprites 4 and 5: the stars of this bitmap */
            u32 p = (u32)star_list[back][i];
            c[cop_spr + 4 * (4 + i)] = p >> 16; c[cop_spr + 4 * (4 + i) + 2] = p & 0xffff;
        }
    }
    while (((W(0x004) & 1) << 8 | W(0x006) >> 8) < 8) ;       /* COP1LC is read at the vertical blank: not now (the first lines) */
    L(0x080) = (u32)copper[back];                  /* the copper runs this list from the next frame on; the list of the shown bitmap is not touched */
    settle_display();                              /* (a vertical blank may have come while we drew) */
    published = vbl_count;
    pending = back;
}

