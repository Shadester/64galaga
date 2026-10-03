#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "game.h"

#define PMAX 256
#define PATH_SPEED 2.6f
#define MIRROR_X 344
enum { P_A, P_B, P_C, P_D };
typedef struct { int sx, sy, n; signed char dx[PMAX], dy[PMAX]; } Path;
#ifdef RULES_ARCADE   /* paths, slots and wave lists of the arcade, made by tools/gen_arcade.py */
#include "arcade_data.h"
#define PATH_LEN(i) (arc_path[i].n)
static void paths_init(void) {}
#elif defined(GAME_PATHS_TABLE)   /* no floating point (Amiga): the same paths as a table, made by amiga/tools/gen_paths.py */
#include GAME_PATHS_TABLE   /* defines paths[] and an empty paths_init() */
#define PATH_LEN(i) (paths[i].n)
#else
#define PATH_LEN(i) (paths[i].n)
static Path paths[4];
static int paths_ready;

/* Control points from 64galaga tools/gen_paths.py. */
static const float ptA[][2] = {{60,30},{120,88},{196,128},{232,100},{200,66},{158,96},{176,156},{236,204},{290,246}};
static const float ptB[][2] = {{292,30},{236,72},{120,92},{62,132},{98,174},{206,188},{274,214},{296,246}};
static const float ptC[][2] = {{240,30},{206,84},{140,136},{90,122},{98,84},{150,78},{196,112}};
static const float ptD[][2] = {{24,96},{86,104},{150,138},{192,176},{158,198},{118,168},{140,124},{196,104}};

static void build_path(Path *p, const float (*src)[2], int n) {
    static float dense[700][2], out[PMAX + 1][2], pts[16][2];
    const float (*pt)[2] = (const float (*)[2])pts;
    int nd = 0, seg, k, j, no = 1;
    float cx, cy, lx = src[1][0] - src[0][0], ly = src[1][1] - src[0][1], ll = sqrtf(lx * lx + ly * ly);
    /* Lead-in: start 70 px before the first point so aliens fly in from off-screen. */
    pts[0][0] = src[0][0] - lx / ll * 70; pts[0][1] = src[0][1] - ly / ll * 70;
    memcpy(pts[1], src, n * sizeof *src); ++n;
    for (seg = 0; seg < n - 1; ++seg) {
        const float *p0 = pt[seg ? seg - 1 : 0], *p1 = pt[seg], *p2 = pt[seg + 1], *p3 = pt[seg + 2 < n ? seg + 2 : n - 1];
        for (k = 0; k < 60; ++k) {
            float t = k / 60.0f, t2 = t * t, t3 = t2 * t;
            dense[nd][0] = .5f * (2 * p1[0] + (p2[0] - p0[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (3 * p1[0] - p0[0] - 3 * p2[0] + p3[0]) * t3);
            dense[nd][1] = .5f * (2 * p1[1] + (p2[1] - p0[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (3 * p1[1] - p0[1] - 3 * p2[1] + p3[1]) * t3);
            ++nd;
        }
    }
    dense[nd][0] = pt[n - 1][0]; dense[nd][1] = pt[n - 1][1]; ++nd;
    /* Resample to a constant speed, then store integer per-frame deltas. */
    cx = out[0][0] = dense[0][0]; cy = out[0][1] = dense[0][1];
    for (j = 1; j < nd && no < PMAX; ++j) {
        for (;;) {
            float dx = dense[j][0] - cx, dy = dense[j][1] - cy, d = sqrtf(dx * dx + dy * dy);
            if (d < PATH_SPEED || no >= PMAX) break;
            cx += dx / d * PATH_SPEED; cy += dy / d * PATH_SPEED;
            out[no][0] = cx; out[no][1] = cy; ++no;
        }
    }
    p->sx = (int)lroundf(out[0][0]); p->sy = (int)lroundf(out[0][1]); p->n = no - 1;
    for (k = 0; k < p->n; ++k) {
        p->dx[k] = (signed char)(lroundf(out[k + 1][0]) - lroundf(out[k][0]));
        p->dy[k] = (signed char)(lroundf(out[k + 1][1]) - lroundf(out[k][1]));
    }
}
static void paths_init(void) {
    if (paths_ready) return;
    build_path(&paths[P_A], ptA, sizeof ptA / sizeof *ptA);
    build_path(&paths[P_B], ptB, sizeof ptB / sizeof *ptB);
    build_path(&paths[P_C], ptC, sizeof ptC / sizeof *ptC);
    build_path(&paths[P_D], ptD, sizeof ptD / sizeof *ptD);
    paths_ready = 1;
}
#endif

static const int bossX[4] = {145, 171, 197, 223};
#ifdef RULES_ARCADE
int slot_x(int i) { return arc_slot[i][0]; }
int slot_y(int i) { return arc_slot[i][1]; }
#elif defined(GAME_PATHS_TABLE)   /* a 68000 divides slowly, and every alien asks for its slot in every tick: a table (made by amiga/tools/gen_paths.py) */
int slot_x(int i) { return slot_xy[i][0]; }
int slot_y(int i) { return slot_xy[i][1]; }
#else
int slot_x(int i) { return i < 4 ? bossX[i] : 106 + 26 * ((i - 4) % 7); }
int slot_y(int i) { return i < 4 ? 72 : 100 + 28 * ((i - 4) / 7); }
#endif

#ifdef RULES_ARCADE   /* where a slot is now: the swing of the whole formation and the breathing of its columns and rows */
static int slot_px(const Game *g, int i) {
    int x = slot_x(i) + g->formDx, c = arc_slot_col[i];
    if (g->breathe) x += c < 5 ? arc_breath[g->bstep][c] : -arc_breath[g->bstep][9 - c];
    return x;
}
static int slot_py(const Game *g, int i) { return slot_y(i) + (g->breathe ? arc_breath[g->bstep][5 + arc_slot_row[i]] : 0); }
#else
#define slot_px(g, i) (slot_x(i) + (g)->formDx)
#define slot_py(g, i) slot_y(i)
#endif

#ifndef RULES_ARCADE
/* Fly-in: launch delay (frames) and path per slot. Bit 4 of the path code = mirrored. */
static const unsigned char entryDelay[NAL] = {
    40,44,48,52, 0,4,8,12, 56,60,64,68, 80,84,88,92,
    96,100, 16,20,24,28, 104,108, 120,124,128,132,136,140,144,148
};
static void entry_path(int i, int *path, int *mir) {
    int w = i < 4 || (i >= 8 && i < 12) ? 2 : i >= 12 && i < 18 ? 3 : i == 22 || i == 23 ? 3 : i >= 24 ? 4 : 1;
    if (w == 1) { *path = P_C; *mir = (i == 5 || i == 7 || i == 19 || i == 21); }
    else if (w == 2) { *path = P_D; *mir = 0; }
    else if (w == 3) { *path = P_D; *mir = 1; }
    else { *path = P_C; *mir = !((i - 24) & 1); }
}
#endif

/* Difficulty tables, index diff-1. */
static const int diveInterval[8] = {130, 115, 100, 85, 70, 58, 48, 34};
static const int diveMax[8] = {1, 1, 2, 2, 3, 3, 4, 5};
static const int diveShots[8] = {1, 1, 1, 2, 2, 2, 2, 2};

#ifdef RULES_ARCADE   /* the arcade repeats stages 23..26 (its tables stop there) */
static int arc_stage_no(int stage) { if (stage > ARC_NSTAGE) stage = ARC_NSTAGE - 3 + ((stage - (ARC_NSTAGE - 3)) & 3); return stage - 1; }
#endif
static int prand(void) { return rand() >> 4; }

static void add_score(Game *g, int n) {
    g->score += n;
    if (g->score > 999999) g->score = 999999;
    if (g->score > g->hi) g->hi = g->score;
    while (g->score >= g->nextBonus) {
        if (g->lives < 9) ++g->lives;
        g->nextBonus += g->nextBonus == 20000 ? 50000 : 70000;
        g->snd |= JG_BONUS;
    }
}

static void setup_stage(Game *g) {
    int i;
    paths_init();
#ifdef RULES_ARCADE
    int row = arc_stage[arc_stage_no(g->stage)][0];
    g->challenge = arc_row[row].challenge;
#else
    g->challenge = (g->stage & 3) == 3;
#endif
#ifdef RULES_ARCADE   /* 100 for each enemy, 10,000 when all 40 are hit (public descriptions of the arcade; not checked in the model) */
    g->chalVal = 100;
#else
    g->chalVal = 100 * ((g->stage + 1) / 4); if (g->chalVal > 900) g->chalVal = 900;
#endif
    g->chalHits = g->chalTimer = g->shots = g->hits = 0;
#ifdef RULES_ARCADE
    g->fclk = g->ff = g->swayPos = g->breathe = g->bstep = 0; g->swayDir = 1;
#endif
    g->formDx = 0; g->formDir = 3; g->formTimer = 0; g->diveTimer = diveInterval[g->diff - 1];
#ifdef RULES_ARCADE
    g->clk = g->af = g->wingm = g->bombFlags = g->hold = 0; g->tmr2 = 120; g->sortie[0] = 22; g->sortie[1] = g->sortie[2] = 2;
#endif
    g->cap = C_NONE; g->beamLen = 0;
    memset(g->ps, 0, sizeof g->ps); memset(g->eb, 0, sizeof g->eb);
    for (i = 0; i < NAL; ++i) {
        Alien *a = &g->al[i];
        memset(a, 0, sizeof *a);
#ifdef RULES_ARCADE
        a->type = i < 4 ? T_BOSS : i < 20 ? T_BUTTERFLY : T_BEE;
#else
        a->type = g->challenge ? (i >> 3 == 1 ? T_BUTTERFLY : i >> 3 == 3 ? T_BOSS : T_BEE)
                               : (i < 4 ? T_BOSS : i < 18 ? T_BUTTERFLY : T_BEE);
#endif
        a->hp = !g->challenge && a->type == T_BOSS ? 2 : 1;
        a->st = A_ENTER; a->y = 255;
#ifndef RULES_ARCADE
        if (g->challenge) { a->path = (i >> 3) & 1 ? P_B : P_A; a->mir = (i >> 3) >= 2; }
        else { entry_path(i, &a->path, &a->mir); a->dly = 2 * entryDelay[i]; }
#endif
    }
#ifdef RULES_ARCADE   /* the launch list of the stage's row: when each slot starts, and on which path (slot -1: an extra enemy, not used yet) */
    for (i = 0; i < arc_row[row].n; ++i) {
        const short *l = arc_row[row].l[i];
        if (l[1] >= 0) {
            Alien *a = &g->al[l[1]];
            a->dly = l[0]; a->path = l[2];
            a->bflags = arc_entry_bomb[l[1]] ? arc_row[row].hdr1 : 0; a->btmr = arc_path[l[2]].bt;   /* the bombs of an enemy that flies in */
        }
    }
#endif
}
static void start_stage(Game *g) {
    setup_stage(g);
    g->state = S_INTRO; g->stateTimer = 120; g->snd |= JG_STAGE;
}
static void start_game(Game *g) {
    srand((unsigned)g->frame * 2654435761u + 1);
    g->score = 0; g->lives = 3; g->stage = 1; g->diff = 1;
#ifdef START_STAGE
    g->stage = START_STAGE; g->diff = 1 + (g->stage - 1 - g->stage / 4); if (g->diff > 8) g->diff = 8;
#endif
    g->nextBonus = 20000;
    g->dual = 0; g->cap = C_NONE; g->px = 160; g->py = 230; g->invuln = 0; g->dyingQuiet = 0;
    start_stage(g);
}
static void game_over(Game *g) {
    g->state = S_GAMEOVER; g->stateTimer = 90; g->snd |= JG_OVER; g->saveReq = 1;
}

void game_init(Game *g, int hiScore) {
    memset(g, 0, sizeof *g);
    g->hi = hiScore; g->state = S_TITLE; g->py = 230; g->px = 160;
}

/* ---- player ---- */
static void player_hit(Game *g, int side) {
    if (g->dual) {
        g->dual = 0; if (side == 0) g->px += 16;
        g->invuln = 90; g->snd |= SND_HIT; return;
    }
    --g->lives;
    g->state = S_DYING; g->dyingQuiet = 0;
#ifdef RULES_ARCADE
    g->stateTimer = 107;   /* the arcade waits 4 x 32 frames before the ship comes back */
#else
    g->stateTimer = 63;
#endif
    memset(g->eb, 0, sizeof g->eb); memset(g->ps, 0, sizeof g->ps);
    g->snd |= SND_HIT | SND_DEATH;
}
static void update_player(Game *g, const Input *in, int firePress) {
    int maxx = g->dual ? 304 : 320, i, n;
    if (in->left) g->px -= 2;
    if (in->right) g->px += 2;
    if (g->px < 24) g->px = 24;
    if (g->px > maxx) g->px = maxx;
    if (!firePress) return;
    for (n = 0; n < (g->dual ? 2 : 1); ++n)
        for (i = n * 2; i < n * 2 + 2; ++i) if (!g->ps[i].act) {
            g->ps[i].act = 1; g->ps[i].x = g->px + 3 + 16 * n; g->ps[i].y = 214;
            if (g->state != S_RESULT) ++g->shots;   /* the result screen shows the stage's shots: later ones do not count */
            g->snd |= SND_SHOOT; break;
        }
}
static void update_pshots(Game *g) {
    int i;
    for (i = 0; i < 4; ++i) if (g->ps[i].act && (g->ps[i].y -= 4) < 20) g->ps[i].act = 0;
}

/* ---- aliens ---- */
static void release_capture(Game *g, int boss) {
    if (g->cap && g->cap != C_RESCUE && g->capBoss == boss) g->cap = C_NONE;
}
static void alien_hit(Game *g, int i) {
    Alien *a = &g->al[i];
    int pts, dive = a->st == A_DIVE || a->st == A_ENTER, k;
    ++g->hits;
    if (a->hp > 1) { --a->hp; g->snd |= SND_SHOOT; return; }
    if (g->challenge) { ++g->chalHits; pts = g->chalVal; }
    else if (a->type == T_BOSS) {
        int n = 0;
        if (dive) for (k = 0; k < NAL; ++k) n += g->al[k].esc == i + 1 && (g->al[k].st == A_DIVE || g->al[k].st == A_RETURN);
        pts = dive ? 400 << n : 150;
#ifdef RULES_ARCADE
        if (dive) g->hold = 6;
#endif
    } else pts = a->type == T_BUTTERFLY ? (dive ? 160 : 80) : (dive ? 100 : 50);
    if (a->type == T_BOSS && g->cap && g->capBoss == i) {
        if (g->cap == C_CARRY && (a->st == A_DIVE || a->st == A_RETURN)) {
            g->cap = C_RESCUE; g->rx = a->x; g->ry = a->y - 16;
            pts += 1000; g->snd |= JG_RESCUE;
        } else g->cap = C_NONE;   /* captive lost, or capture cancelled (beam vanishes) */
    }
    a->st = A_EXPLODE; a->timer = 11; g->snd |= SND_EXPLODE;
    add_score(g, pts);
}

#ifdef RULES_ARCADE   /* mirrored paths are separate paths: no mirror here */
static void path_step(Alien *a) {
    const signed char *d = arc_path[a->path].d + 2 * a->pstep;
    a->x += d[0]; a->y += d[1];
    ++a->pstep;
}
static void path_launch(Alien *a) {
    a->ent = 1; a->pstep = 0; a->x = arc_path[a->path].sx; a->y = arc_path[a->path].sy;
}
#else
static void path_step(Alien *a) {
    const Path *p = &paths[a->path];
    a->x += a->mir ? -p->dx[a->pstep] : p->dx[a->pstep];
    a->y += p->dy[a->pstep];
    ++a->pstep;
}
static void path_launch(Alien *a) {
    const Path *p = &paths[a->path];
    a->ent = 1; a->pstep = 0; a->x = a->mir ? MIRROR_X - p->sx : p->sx; a->y = p->sy;
}
#endif
#ifdef RULES_ARCADE
/* The formation swings left and right while the aliens fly in (one arcade pixel every 4 frames, +-32), and when they are all home and
 * the swing comes back to the middle it starts to breathe (arc_breath). */
static void arc_form_frame(Game *g) {
    ++g->ff;
    if (g->breathe) { if (!(g->ff & 3)) g->bstep = (g->bstep + 1) & 63; return; }
    if ((g->ff - 1) & 3) return;
    g->swayPos += g->swayDir;
    if (!g->entering && g->swayPos == 0) { g->breathe = 1; g->bstep = 0; }
    else if (g->swayPos >= 32) g->swayDir = -1;
    else if (g->swayPos <= -32) g->swayDir = 1;
    g->formDx = g->swayPos + g->swayPos * 3 / 7;   /* 320 / 224 */
}
static void update_formation(Game *g) {
    int i, n = 0;
    for (i = 0; i < NAL; ++i) n += g->al[i].st == A_ENTER;
    g->entering = n;
    if (g->challenge) return;
    for (g->fclk += 6; g->fclk >= 5; g->fclk -= 5) arc_form_frame(g);
}
#else
static void update_formation(Game *g) {
    int i, n = 0;
    for (i = 0; i < NAL; ++i) n += g->al[i].st == A_ENTER;
    g->entering = n;
    if (n || g->challenge) return;
    if (++g->formTimer >= 10 - g->diff) {
        g->formTimer = 0; g->formDx += g->formDir;
        if (g->formDx >= 42) g->formDir = -3;
        if (g->formDx <= -42) g->formDir = 3;
    }
}
#endif
static void update_entry(Game *g) {
    int i;
    for (i = 0; i < NAL; ++i) {
        Alien *a = &g->al[i];
        if (a->st != A_ENTER) continue;
        if (a->ent == 0) {
#ifdef RULES_ARCADE   /* the waves wait while the ship is dead or taken: the aliens in the air finish, the others do not start */
            if (g->state != S_PLAY) continue;
#endif
            if (--a->dly <= 0) path_launch(a);
        }
        else if (a->ent == 1) { if (a->pstep >= PATH_LEN(a->path)) a->ent = 2; else path_step(a); }
        else {
            int tx = slot_px(g, i), ty = slot_py(g, i);
            a->x += a->x < tx ? 2 : a->x > tx ? -2 : 0;
            a->y += a->y < ty ? 2 : a->y > ty ? -2 : 0;
            if (abs(a->x - tx) <= 3 && abs(a->y - ty) <= 3) { a->st = A_FORM; a->x = tx; a->y = ty; }
        }
    }
}
static void update_challenge(Game *g) {
    int i;
    ++g->chalTimer;
    for (i = 0; i < NAL; ++i) {
        Alien *a = &g->al[i];
        if (a->st != A_ENTER) continue;
#ifdef RULES_ARCADE
        if (a->ent == 0) { if (g->chalTimer >= a->dly) path_launch(a); }
#else
        if (a->ent == 0) { if (g->chalTimer >= (i >> 3) * 55 + (i & 7) * 6) path_launch(a); }
#endif
        else if (a->pstep >= PATH_LEN(a->path)) a->st = A_DEAD;
        else path_step(a);
    }
}

#ifdef RULES_ARCADE   /* the arcade limits the sideways speed of a bomb to 0.6 of its fall speed (2.5 px a tick): 0.6 x 2.5 x 16 */
#define BOMB_MAX_DX 24
/* A diver drops no bombs below this line. In the arcade it is 97 of the 288 screen lines above the ship (a third of the screen),
 * so a bomb always falls far: here 67 of 200 lines. */
#define BOMB_LOW_Y 163
#endif
static void spawn_ebullet(Game *g, const Alien *a) {
    int i, d = g->px - a->x;
    for (i = 0; i < EBN; ++i) if (!g->eb[i].act) {
        g->eb[i].act = 1; g->eb[i].x = a->x; g->eb[i].y = a->y + 8;
#ifdef RULES_ARCADE   /* aimed at the ship's place now: the bomb needs (py - y) / 2.5 ticks to fall, so it moves dx / ticks a tick, in 16ths */
        g->eb[i].ax = 0;
        g->eb[i].dx = 16 * d / ((g->py - g->eb[i].y) * 2 / 5 + 1);
        if (g->eb[i].dx > BOMB_MAX_DX) g->eb[i].dx = BOMB_MAX_DX;
        if (g->eb[i].dx < -BOMB_MAX_DX) g->eb[i].dx = -BOMB_MAX_DX;
        return;
#else
        g->eb[i].dx = abs(d) < 16 ? 0 : d > 0 ? 1 : -1; return;
#endif
    }
}
static void start_dive(Game *g, int i, int capture, int peel) {
    Alien *a = &g->al[i];
    a->st = A_DIVE; a->timer = peel; a->fired = 0; a->capdive = capture;
    a->dir = capture ? (a->x < g->px ? 1 : -1) : (a->x >= 184 ? 1 : -1);
    g->snd |= SND_SWOOP;
    if (capture) { g->cap = C_DIVING; g->capBoss = i; }
#ifdef RULES_ARCADE   /* a dive follows the arcade path of its kind from its slot: a boss and an escort label 2, a butterfly 1, a bee 0 */
    a->pstep = 0; a->bflags = g->bombFlags; a->btmr = 30;
    a->dpath = capture ? -1 : arc_dive[a->esc || a->type == T_BOSS ? 2 : a->type == T_BUTTERFLY ? 1 : 0][arc_slot_row[i]][arc_slot_side[i]];
#endif
}
#ifdef RULES_ARCADE
static void dive_step(Game *g, int i);
static void dive_step_old(Game *g, int i) {
#else
static void dive_step(Game *g, int i) {
#endif
    Alien *a = &g->al[i];
    int dy = g->diff >= 5 ? 3 : 2;
    if (a->timer > 0) { --a->timer; a->x += 2 * a->dir; a->y += 1; return; }
    a->y += dy;
    if (a->capdive || (g->frame & 1)) a->x += a->x < g->px ? 1 : a->x > g->px ? -1 : 0;
    if (!a->esc && !a->capdive) {
        int mask = g->diff <= 2;
        if ((a->fired == 0 && a->y >= 100) || (a->fired == 1 && diveShots[g->diff - 1] == 2 && a->y >= 150)) {
            ++a->fired;
            if ((prand() & mask) == 0) spawn_ebullet(g, a);
        }
    }
    if (a->capdive && a->y >= 196) {
        a->st = A_BEAM; g->cap = C_BEAM; g->beamLen = g->beamAcc = 0; g->beamTimer = 180;
#ifdef RULES_ARCADE   /* 10 x p6 arcade frames to grow (p6 = 12, 9 or 6 by stage), then 64 frames to take the ship, then the same to go */
        g->beamPh = 0; g->beamStep = arc_stage[arc_stage_no(g->stage)][1 + 6] * 10 * 5 / 6 / 4;
#endif
    } else if (a->y >= 244) { a->st = A_RETURN; a->y = 0; a->capdive = 0; }
}
#ifdef RULES_ARCADE
static void dive_step(Game *g, int i) {
    Alien *a = &g->al[i];
    if (a->capdive) { dive_step_old(g, i); return; }
    if (a->timer > 0) { --a->timer; a->x = slot_px(g, i); a->y = slot_py(g, i); return; }   /* an escort waits for its boss */
    if (a->dpath >= 0 && a->pstep < arc_dive_path[a->dpath].n) {
        const signed char *d = arc_dive_path[a->dpath].d + 2 * a->pstep;
        a->x += d[0]; a->y += d[1];
    } else {   /* the end of the arcade path of a butterfly (it aims at the ship) */
        a->y += 3;
        if (g->frame & 1) a->x += a->x < g->px ? 1 : a->x > g->px ? -1 : 0;
    }
    ++a->pstep;
    if (a->y >= 244) {   /* gone below the screen: back from the top when the arcade dive would end (the way back takes slot_y / 2 ticks) */
        int total = a->dpath >= 0 ? arc_dive_path[a->dpath].total : 220;
        a->st = A_RETURN; a->y = 0; a->timer = total - a->pstep - slot_py(g, i) / 2; if (a->timer < 0) a->timer = 0;
    }
}
#endif
static void update_aliens(Game *g) {
    int i;
    for (i = 0; i < NAL; ++i) {
        Alien *a = &g->al[i];
        switch (a->st) {
        case A_FORM:
            a->x = slot_px(g, i); a->y = slot_py(g, i);
#ifdef RULES_ARCADE
            if (a->timer > 0) --a->timer;   /* just home: it turns round before it can dive again */
#endif
            break;
        case A_EXPLODE: if (--a->timer < 0) a->st = A_DEAD; break;
        case A_DIVE: dive_step(g, i); break;
        case A_RETURN:
            a->x = slot_px(g, i);
#ifdef RULES_ARCADE
            if (a->timer > 0) { --a->timer; break; }
#endif
            if ((a->y += 2) >= slot_py(g, i)) {
                a->y = slot_py(g, i); a->st = A_FORM; a->esc = 0;
#ifdef RULES_ARCADE   /* the arcade takes 54 frames (bee: 3) to settle a boss or a butterfly: 45 ticks */
                a->timer = a->type == T_BEE ? 3 : 45;
#endif
            }
            break;
        }
    }
}
#ifdef RULES_ARCADE
/* The arcade's dive scheduler (f_0857, f_1B65 of the model, see ARCADE.md). One call is one arcade frame. */
static int arc_standby(Game *g, int from, int to) {
    int i;
    for (i = from; i < to; ++i) if (g->al[i].st == A_FORM && !g->al[i].timer) return i;
    return -1;
}
static void arc_sortie_boss(Game *g) {   /* case_bmbr_boss, j_1CAE: who dives with whom (see ARCADE.md) */
    static const unsigned char boss_for_b[5] = {0, 1, 3, 2, 0};
    int c = 0, k, ixl, B, cc, b, slot = -1, n = 1, esc[2], ne = 0;
    if (!g->cap && !(++g->wingm & 1) && !g->dual) {   /* every second sortie tries to capture */
        if ((slot = arc_standby(g, 0, 4)) >= 0) start_dive(g, slot, 1, 20);
        return;
    }
    for (k = 0; k < 6; ++k) c = (c << 1) | (g->al[arc_wingmen[k]].st == A_FORM && !g->al[arc_wingmen[k]].timer);   /* which of the six wingmen are at home */
    for (ixl = 0; ixl < 2 && slot < 0; ++ixl)   /* ixl 0: a boss with two wingmen (the pattern 011, 111, 110), ixl 1: with one */
        for (cc = c, B = 4; B >= 1; --B, cc >>= 1) {
            int a = cc & 7;
            if ((ixl == 0 ? a != 4 && a >= 3 : a != 0) && g->al[boss_for_b[B]].st == A_FORM && !g->al[boss_for_b[B]].timer) { slot = boss_for_b[B]; n = 2 - ixl; break; }
        }
    if (slot < 0) {   /* a boss alone */
        if ((slot = arc_standby(g, 0, 4)) >= 0) start_dive(g, slot, 0, 0);
        return;
    }
    b = B + 1;   /* B and cc are the ones of the match */
    for (k = 0; k < n; ++k) {
        int cy = cc & 1;
        cc = (cc >> 1) | (cy << 7);
        if (!cy) { --b; cy = cc & 1; cc = (cc >> 1) | (cy << 7); if (!cy) --b; }
        if (b >= 0 && b < 6) esc[ne++] = arc_wingmen[b];
        --b;
    }
    for (k = 0; k < ne; ++k) g->al[esc[k]].esc = slot + 1;
    start_dive(g, slot, 0, 0);
    for (k = 0; k < ne; ++k) start_dive(g, esc[k], 0, k + 1);
}
static void arc_frame(Game *g) {
    const unsigned char *p = arc_stage[arc_stage_no(g->stage)] + 1;
    int i, n = 0, flying = 0, tens, idx, reload[3], maxb = p[4], cont, hdr0;
    ++g->af;
    if (!(g->af & 31)) { if (g->tmr2 > 0) --g->tmr2; if (g->hold > 0) --g->hold; }
    hdr0 = arc_row[p[-1]].hdr0;
    for (i = 0; i < NAL; ++i) {
        int st = g->al[i].st;
        n += st != A_DEAD && st != A_EXPLODE;
        flying += st == A_DIVE || st == A_RETURN || st == A_BEAM;
    }
    tens = n / 10;
    if (g->tmr2 < 60) maxb = p[5];
    g->bombFlags = arc_bomb_tab[4 * p[0] + tens];
    cont = n < p[7];
    idx = (g->tmr2 < 40) + (g->tmr2 == 0);
    reload[0] = cont ? 2 : arc_bomb_tab[32 + 4 * p[1] + tens];
    reload[1] = cont ? 2 : arc_red_reload[3 * p[2] + idx];
    reload[2] = cont ? 2 : arc_bee_reload[3 * p[3] + idx];
    for (i = 0; i < NAL; ++i) {   /* bombs: a diver drops one at every set bit of its flags, every 20 frames, high on the screen */
        Alien *a = &g->al[i];
        if (!((a->st == A_DIVE && !a->capdive) || (a->st == A_ENTER && a->ent == 1))) continue;
        if (--a->btmr > 0) continue;
        a->btmr = hdr0;
        if ((a->bflags & 1) && a->y <= BOMB_LOW_Y && !g->hold) spawn_ebullet(g, a);
        a->bflags >>= 1;
    }
    if (g->entering || (g->af & 15)) return;
    for (i = 0; i < 3; ++i) if (--g->sortie[i] == 0) break;
    if (i == 3) return;
    if (flying >= maxb) { ++g->sortie[i]; return; }
    g->sortie[i] = reload[i];
    if (i == 2) { if ((n = arc_standby(g, 20, 40)) >= 0) start_dive(g, n, 0, 0); }
    else if (i == 1) { if ((n = arc_standby(g, 4, 20)) >= 0) start_dive(g, n, 0, 0); }
    else arc_sortie_boss(g);
}
static void select_dive(Game *g) {
    if (g->challenge) return;
    for (g->clk += 6; g->clk >= 5; g->clk -= 5) arc_frame(g);
}
#else
static void select_dive(Game *g) {
    int i, tries, away = 0, pick = -1;
    if (g->entering || g->challenge) return;
    if (--g->diveTimer > 0) return;
    g->diveTimer = diveInterval[g->diff - 1];
    for (i = 0; i < NAL; ++i) away += !g->al[i].esc && (g->al[i].st == A_DIVE || g->al[i].st == A_RETURN || g->al[i].st == A_BEAM);
    if (away >= diveMax[g->diff - 1]) return;
#ifdef FORCECAPTURE
    if (!g->cap && !g->dual && g->al[1].st == A_FORM) { start_dive(g, 1, 1, 20); return; }
#endif
    if (!g->cap && !g->dual && (prand() & 1)) { i = prand() & 3; if (g->al[i].st == A_FORM) pick = i; }
    for (tries = 0; pick < 0 && tries < 8; ++tries) {
#ifdef RULES_ARCADE
        i = prand() % NAL;
#else
        i = prand() & 31;
#endif
        if (g->al[i].st == A_FORM) pick = i;
    }
    if (pick < 0) return;
    if (g->al[pick].type == T_BOSS && !g->cap && !g->dual) { start_dive(g, pick, 1, 20); return; }
    start_dive(g, pick, 0, 20);
    if (g->al[pick].type == T_BOSS && (g->cap || g->dual)) {
        int k;
        for (k = 0; k < 2; ++k) {
#ifdef RULES_ARCADE
            int ei = 4 + 2 * pick + k;
#else
            int ei = 5 + pick + k;
#endif
            Alien *e = &g->al[ei];
            if (e->st == A_FORM) { start_dive(g, ei, 0, k ? 32 : 26); e->esc = pick + 1; }
        }
    }
}
#endif
static void update_ebullets(Game *g) {
    int i;
    for (i = 0; i < EBN; ++i) if (g->eb[i].act) {
#ifdef RULES_ARCADE
        g->eb[i].y += 2 + (g->frame & 1);
        g->eb[i].ax += g->eb[i].dx; g->eb[i].x += g->eb[i].ax >> 4; g->eb[i].ax &= 15;
#else
        g->eb[i].y += 3;
        if (g->frame & 1) g->eb[i].x += g->eb[i].dx;
#endif
        if (g->eb[i].y >= 250) g->eb[i].act = 0;
    }
}

static void update_collisions(Game *g) {
    int i, j;
    for (i = 0; i < 4; ++i) if (g->ps[i].act) for (j = 0; j < NAL; ++j) {
        Alien *a = &g->al[j];
        if (a->st == A_DEAD || a->st == A_EXPLODE || (a->st == A_ENTER && a->ent == 0)) continue;
        if (g->ps[i].y - 8 <= a->y && a->y < g->ps[i].y + 8 && a->x - 6 <= g->ps[i].x && g->ps[i].x < a->x + 12) {
            g->ps[i].act = 0; alien_hit(g, j); break;
        }
    }
    if (g->state != S_PLAY || g->invuln) return;
    for (i = 0; i < EBN && g->state == S_PLAY; ++i) if (g->eb[i].act && g->eb[i].y >= 227 && g->eb[i].y <= 240) {
        for (j = 0; j < 1 + g->dual; ++j) {
            int sx = g->px + 16 * j;
            if (g->eb[i].x >= sx - 6 && g->eb[i].x <= sx + 7) { g->eb[i].act = 0; player_hit(g, j); break; }
        }
    }
    for (j = 0; j < NAL && g->state == S_PLAY && !g->invuln && !g->challenge; ++j) {   /* challenge aliens never ram */
        Alien *a = &g->al[j];
        int s;
        if (!((a->st == A_DIVE) || (a->st == A_ENTER && a->ent))) continue;
        for (s = 0; s < 1 + g->dual; ++s) {
            int sx = g->px + 16 * s;
            if (a->y >= g->py - 7 && a->y <= g->py + 8 && a->x > sx - 8 && a->x <= sx + 8) {
                if (a->capdive) release_capture(g, j);   /* ramming boss drops its captive */
                if (a->type == T_BOSS && g->cap == C_CARRY && g->capBoss == j) g->cap = C_NONE;
                a->st = A_EXPLODE; a->timer = 11; g->snd |= SND_EXPLODE;
                player_hit(g, s); break;
            }
        }
    }
}

/* ---- tractor beam, capture, rescue ---- */
static void update_capture(Game *g) {
    if (g->cap == C_BEAM) {
        Alien *b = &g->al[g->capBoss];
        if (!(g->frame & 31)) g->snd |= SND_SWOOP;
#ifdef RULES_ARCADE
        if (g->beamPh == 0) { if (++g->beamAcc >= g->beamStep) { g->beamAcc = 0; if (++g->beamLen >= 4) { g->beamPh = 1; g->beamTimer = 53; } } }
        else if (g->beamPh == 2) {
            if (++g->beamAcc >= g->beamStep) { g->beamAcc = 0; if (--g->beamLen <= 0) { g->cap = C_NONE; b->st = A_RETURN; b->y = 0; } }
        } else
#else
        if (g->beamLen < 4) { if (++g->beamAcc >= 8) { g->beamAcc = 0; ++g->beamLen; } }
        else
#endif
        if (g->state == S_PLAY && !g->invuln && g->px >= b->x - 20 && g->px <= b->x + 19) {
            g->cap = C_PULL; g->state = S_CAPTURED; g->dual = 0;
            memset(g->ps, 0, sizeof g->ps); g->snd |= JG_CAPTURE;
        } else if (--g->beamTimer <= 0) {
#ifdef RULES_ARCADE
            g->beamPh = 2; g->beamAcc = 0;
#else
            g->cap = C_NONE; b->st = A_RETURN; b->y = 0;
#endif
        }
    } else if (g->cap == C_RESCUE) {
        int tx = g->px + 16;
        if ((g->ry += 3) > 230) g->ry = 230;
        g->rx += g->rx < tx ? 2 : g->rx > tx ? -2 : 0;
        if (g->ry == 230 && g->state == S_PLAY && g->rx - tx >= -4 && g->rx - tx <= 3) {
            g->cap = C_NONE; g->dual = 1; if (g->px > 304) g->px = 304; g->snd |= JG_RESCUE;
        }
    }
}
static void update_captured(Game *g) {
    Alien *b = &g->al[g->capBoss];
    update_ebullets(g);
    g->py -= 2;
    if (g->py - b->y >= 22) return;
    g->py = 230; g->cap = C_CARRY; b->st = A_RETURN; b->y = 0; b->capdive = 0;
    if (--g->lives <= 0) { game_over(g); return; }
    g->state = S_DYING; g->stateTimer = 100; g->dyingQuiet = 1;
}

static void next_stage(Game *g) {
    if (!g->challenge && g->diff < 8) ++g->diff;
    ++g->stage;
    start_stage(g);
}
static void enter_result(Game *g) {
    g->state = S_RESULT; g->stateTimer = 150;
    if (g->challenge && g->chalHits == NAL) add_score(g, 10000);
}
static void move_world(Game *g) {
    update_formation(g); update_entry(g); update_aliens(g);
}

void game_tick(Game *g, const Input *in) {
    int firePress = in->fire && !g->prevFire, i, alive;
    g->prevFire = in->fire;
    if (g->state == S_TITLE) { if (firePress) start_game(g); ++g->frame; return; }
    if (in->pause && g->state == S_PLAY) g->paused = !g->paused;
    if (g->paused) return;
    if (in->quit && g->state != S_GAMEOVER) { g->state = S_TITLE; g->saveReq = 1; g->snd = 0; return; }
    ++g->frame;
    switch (g->state) {
    case S_INTRO:
        if (--g->stateTimer <= 0) g->state = S_PLAY;
        break;
    case S_PLAY:
        if (g->invuln) --g->invuln;
        update_player(g, in, firePress); update_pshots(g);
        if (g->challenge) { update_challenge(g); update_aliens(g); }
        else { move_world(g); select_dive(g); update_ebullets(g); }
        update_collisions(g); update_capture(g);
        if (g->state != S_PLAY) break;
        for (alive = 0, i = 0; i < NAL; ++i) alive += g->al[i].st != A_DEAD;
        if (!alive && g->cap != C_RESCUE) enter_result(g);
        break;
    case S_DYING:
        if (g->challenge) update_aliens(g);
        else { move_world(g); update_ebullets(g); update_capture(g); }
        if (--g->stateTimer <= 0) {
            if (g->lives <= 0) game_over(g);
            else {
                g->state = S_READY;
#ifdef RULES_ARCADE
                g->stateTimer = 80;   /* 3 x 32 frames after the last flyer is home */
#else
                g->stateTimer = 90;
#endif
            }
        }
        break;
    case S_READY:
        if (g->challenge) update_aliens(g);
        else move_world(g);
#ifdef RULES_ARCADE   /* the ship comes back when nothing flies any more: the divers finish first, the beam too */
        if (!g->challenge) {
            int k, flying = 0;
            update_capture(g);
            for (k = 0; k < NAL; ++k) flying += g->al[k].st == A_DIVE || g->al[k].st == A_RETURN || g->al[k].st == A_BEAM || (g->al[k].st == A_ENTER && g->al[k].ent);
            if (flying) break;
        }
#endif
        if (--g->stateTimer <= 0) {
            g->state = S_PLAY; g->px = 160; g->invuln = 120;
#ifdef RULES_ARCADE   /* after a death the sorties start slowly again */
            g->tmr2 += 30; if (g->tmr2 > 120) g->tmr2 = 120;
#endif
        }
        break;
    case S_CAPTURED:
        move_world(g); update_capture(g); update_captured(g);
        break;
    case S_RESULT:
        update_player(g, in, firePress); update_pshots(g);
        if (--g->stateTimer <= 0) next_stage(g);
        break;
    case S_GAMEOVER:
        if (g->stateTimer > 0) --g->stateTimer;
        else if (firePress) g->state = S_TITLE;
        break;
    }
}

/* Synthetic input for unattended runs: sweep, fire, press fire on menus. */
void game_autoplay(const Game *g, Input *in) {
    memset(in, 0, sizeof *in);
    in->fire = (g->frame & 15) < 2;
    in->left = ((g->frame >> 7) & 1) == 0 ? 0 : 1;
    in->right = !in->left;
#ifdef FORCECAPTURE   /* walk under the capture boss so the beam catches, then shoot the carrier */
    if (g->state == S_PLAY || g->state == S_RESULT) in->fire = 0;
    if (g->cap == C_BEAM || g->cap == C_CARRY || g->cap == C_DIVING) {
        int bx = g->al[g->capBoss].x;
        in->left = g->px > bx + 2; in->right = g->px < bx - 2;
        if (g->cap == C_CARRY) in->fire = (g->frame & 3) < 2;
    }
#endif
}
