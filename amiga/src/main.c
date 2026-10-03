/* Galaga for the Amiga: the main loop, input, and what the game state looks like on the screen.
 * The rules are psp/game.c (src/game.c). One tick of the game for each vertical blank: 50 a second, as on the C64. */
#include "game.h"
#include "video.h"
#include "audio.h"
#include "assets.h"

extern volatile u32 vbl_count;
extern volatile u8 keys[128];

#define REG(r) (*(volatile u16 *)(0xdff000 + (r)))


#ifdef SELFTEST
/* -DSELFTEST=n: instead of the game, run n ticks of the scripted game (src/selftest.h): a green screen if the hash is
 * SELFTEST_EXPECT (made by tests/selftest_native.c), a red one if not. */
#include "selftest.h"
static void run_selftest(void) {
    REG(0x180) = 0x0ff0;                              /* yellow: running */
    REG(0x096) = 0x8100;                              /* bitplane DMA on, no plane: the colour fills the screen */
    REG(0x100) = 0x0200;
    REG(0x180) = selftest_hash(SELFTEST) == SELFTEST_EXPECT ? 0x00f0 : 0x0f00;
    for (;;) ;
}
#endif

#ifndef TITLE_HOLD
#define TITLE_HOLD 150          /* AUTOPLAY: ticks until it presses fire on the title screen */
#endif

/* ---- input: the cursor keys or A / D, space / Z / X / Return or the fire button of a joystick in port 2; P pauses, Esc quits ---- */
enum { K_P = 0x19, K_A = 0x20, K_D = 0x22, K_Z = 0x31, K_X = 0x32, K_SPACE = 0x40, K_RETURN = 0x44, K_ESC = 0x45,
       K_RIGHT = 0x4e, K_LEFT = 0x4f, K_CTRL = 0x63 };

static void read_input(Input *in) {
    static int old_pause, old_quit;
    u16 j = REG(0x00c);                               /* JOY1DAT: port 2 */
    int pause = keys[K_P], quit = keys[K_ESC];
    in->left = keys[K_LEFT] || keys[K_A] || (j & 0x0200);
    in->right = keys[K_RIGHT] || keys[K_D] || (j & 0x0002);
    in->fire = keys[K_SPACE] || keys[K_Z] || keys[K_X] || keys[K_RETURN] || keys[K_CTRL] || !(*(volatile u8 *)0xbfe001 & 0x80);
    in->pause = pause && !old_pause;
    in->quit = quit && !old_quit;
    old_pause = pause; old_quit = quit;
}

/* ---- the screen ---- */
static int star_slow, star_fast;                  /* the starfield (hardware sprites, video.c): the offsets of its two layers */

enum { WHITE = 1, RED = 2, CYAN = 20 };          /* palette entries (tools/art.py) */

static char *put_num(char *p, int n, int digits) {
    int i;
    for (i = digits - 1; i >= 0; --i) { p[i] = '0' + n % 10; n /= 10; }
    return p + digits;
}
static int str_len(const char *s) { int n = 0; while (s[n]) ++n; return n; }
static void centre(const char *s, int y, int colour) { video_text(s, (SCREEN_W - 8 * str_len(s)) / 2, y, colour); }

/* sprite slots (video.c): the aliens are 0..NAL-1 */
enum { SLOT_SHIP = NAL, SLOT_DUAL, SLOT_CAPTIVE, SLOT_PBUL, SLOT_EBUL = SLOT_PBUL + 4 };

/* C64 position of a sprite box -> screen */
static int scroll;                                /* the formation's sway (formDx): the playfield is shown shifted by it (copper), so everything is drawn at x - scroll */
#define SX(x) ((x) - 24 - scroll)
#define SY(y) ((y) - 50 + TOP)

static void draw_hud(const Game *g) {
    char b[16];
    int i;
    if (!video_static_begin(g->score, g->hi, g->stage, g->lives)) return;      /* the hud stays in the bitmap until a number changes */
    video_text("SCORE", 8, 2, RED);
    video_text("HI-SCORE", 128, 2, RED);
    video_text("STAGE", 256, 2, RED);
    put_num(b, g->score, 6); b[6] = 0; video_text(b, 8, 12, WHITE);
    put_num(b, g->hi, 6); b[6] = 0; video_text(b, 136, 12, WHITE);
    put_num(b, g->stage, 2); b[2] = 0; video_text(b, 264, 12, WHITE);
    for (i = 0; i < g->lives && i < 8; ++i) video_static_bob(SPR_LIFE, 64 + (i & 3) * 14, 2 + (i >> 2) * 13);   /* the lives: two rows of four, in the hud */
    video_static_end();
}

static void draw_messages(const Game *g) {
    char *p;
    if (g->paused) { centre("PAUSED", 120, WHITE); return; }
    switch (g->state) {
    case S_INTRO:
        if (g->challenge) centre("CHALLENGING STAGE", 150, CYAN);
        else { char t[10] = "STAGE "; put_num(t + 6, g->stage, 2); t[8] = 0; centre(t, 150, WHITE); }
        break;
    case S_READY: centre("READY", 192, WHITE); break;
    case S_DYING: if (g->dyingQuiet) centre("FIGHTER CAPTURED", 192, RED); break;
    case S_RESULT:
        if (g->challenge) {
            char t[24] = "NUMBER OF HITS ";
            p = put_num(t + 15, g->chalHits, 2); *p = 0;
            centre(t, 96, WHITE);
            if (g->chalHits == NAL) { centre("PERFECT!", 120, CYAN); centre("BONUS 10000", 136, WHITE); }
        } else {
            char t[16];
            int sh = g->shots > 999 ? 999 : g->shots, hi = g->hits > 999 ? 999 : g->hits;
            int ratio = g->shots ? g->hits * 100 / g->shots : 0;
            if (ratio > 100) ratio = 100;
            p = t; *p++ = 'S'; *p++ = 'H'; *p++ = 'O'; *p++ = 'T'; *p++ = 'S'; *p++ = ' '; p = put_num(p, sh, 3); *p = 0;
            centre(t, 96, WHITE);
            p = t; *p++ = 'H'; *p++ = 'I'; *p++ = 'T'; *p++ = 'S'; *p++ = ' '; *p++ = ' '; p = put_num(p, hi, 3); *p = 0;
            centre(t, 112, WHITE);
            p = t; *p++ = 'R'; *p++ = 'A'; *p++ = 'T'; *p++ = 'I'; *p++ = 'O'; *p++ = ' '; p = put_num(p, ratio, 3); *p++ = '%'; *p = 0;
            centre(t, 128, CYAN);
        }
        break;
    case S_GAMEOVER:
        centre("GAME OVER", 102, WHITE);
        if (g->stateTimer == 0) centre("PRESS FIRE", 130, WHITE);
        break;
    }
}

#ifdef PROFILE
static int loops;                                 /* PROFILE (+ HALT): loops of the main loop; fewer loops for the same ticks = a slower picture */
static u32 vbl_start, vbl_halt;
static u32 lines_tick, lines_draw;                /* PROFILE: the beam lines (64 us) that the ticks and the picture needed in total */
extern volatile u32 vbl_count;
static u32 now_lines(void) { u32 v; do { v = vbl_count; } while (v != vbl_count); return v * 313 + ((REG(0x004) & 1) << 8 | REG(0x006) >> 8); }                   /* the VBLs the game needed for HALT ticks: HALT = 50 a second */
#endif

static void draw(const Game *g) {
    int i, anim = (g->frame >> 4) & 1;
    video_begin();
    scroll = g->state == S_TITLE ? 0 : g->formDx;
    video_scroll(scroll);
    video_title(g->state == S_TITLE);
    if (g->state == S_TITLE) {
        char b[20] = "HI-SCORE ";
        put_num(b + 9, g->hi, 6); b[15] = 0;
        centre(b, 190, RED);
        centre("PRESS FIRE", 206, WHITE);
        centre("ARROWS AND SPACE", 232, WHITE);
        video_stars(-1, -1);
        video_end(1);
        return;
    }
    video_stars(star_slow, star_fast);
    draw_hud(g);
    if (g->state != S_GAMEOVER) {
        if ((g->cap == C_BEAM || g->cap == C_PULL) && g->beamLen) {      /* behind the boss, as the text characters are on the C64 */
            const Alien *b = &g->al[g->capBoss];
            video_beam(SX(b->x + 12), TOP + 1 + ((b->y - 36) >> 3) * 8, g->beamLen, (g->frame >> 2) & 3);
        }
        for (i = 0; i < NAL; ++i) {
            const Alien *a = &g->al[i];
            int id;
            if (a->st == A_DEAD || (a->st == A_ENTER && a->ent == 0)) continue;
            if (a->st == A_EXPLODE) { int f = 2 - (a->timer >> 2); id = SPR_EXPL1 + (f < 0 ? 0 : f > 2 ? 2 : f); }
            else if (a->type == T_BOSS && a->hp == 1 && !g->challenge) id = SPR_BOSSP_A + anim;
            else id = (a->type == T_BOSS ? SPR_BOSS_A : a->type == T_BUTTERFLY ? SPR_BFLY_A : SPR_BEE_A) + anim;
            video_bob(i, id, SX(a->x), SY(a->y));
        }
        if (g->state == S_DYING) {
            if (!g->dyingQuiet) { int f = 3 - (g->stateTimer >> 4); video_bob(SLOT_SHIP, SPR_PEXP1 + (f < 0 ? 0 : f > 3 ? 3 : f), SX(g->px), SY(g->py)); }
        } else if (g->state != S_READY && !(g->invuln & 4)) {
            video_bob(SLOT_SHIP, SPR_SHIP, SX(g->px + 3), SY(g->py - 2));
            if (g->dual) video_bob(SLOT_DUAL, SPR_SHIP, SX(g->px + 19), SY(g->py - 2));
        }
        if (g->cap == C_CARRY) {
            const Alien *b = &g->al[g->capBoss];
            if (b->st != A_DEAD && b->y >= 32) video_bob(SLOT_CAPTIVE, SPR_CAPTIVE, SX(b->x + 3), SY(b->y - 18));
        } else if (g->cap == C_RESCUE) {
            video_bob(SLOT_CAPTIVE, SPR_CAPTIVE, SX(g->rx + 3), SY(g->ry - 2));
        }
        for (i = 0; i < 4; ++i) if (g->ps[i].act) video_bob(SLOT_PBUL + i, SPR_PBUL, SX(g->ps[i].x + 8), SY(g->ps[i].y + 1));
        for (i = 0; i < EBN; ++i) if (g->eb[i].act) video_bob(SLOT_EBUL + i, SPR_EBUL, SX(g->eb[i].x + 10), SY(g->eb[i].y - 2));
    }
    draw_messages(g);
#if defined(PROFILE) && defined(HALT)
    if (g->frame + 3 >= HALT) { char b[40] = "LOOPS "; char *p = put_num(b + 6, loops, 4); *p++ = ' '; *p++ = 'T'; p = put_num(p, (lines_tick >> 4) % 10000, 4); *p++ = ' '; *p++ = 'D'; p = put_num(p, (lines_draw >> 4) % 10000, 4); *p = 0; video_text(b, 60, 244, WHITE); }
#endif
    video_end(0);
}

int main(void) {
    static Game g;
    Input in;
    u32 last;
    int t = 0;
    (void)t;
#ifdef SELFTEST
    run_selftest();
#endif
    video_init();
    audio_init();
    game_init(&g, 0);
    last = vbl_count;
#ifdef PROFILE
    vbl_start = last;
#endif
    for (;;) {
        u32 now;
        int n;
        while ((now = vbl_count) == last) ;
        n = now - last > 6 ? 6 : now - last;              /* a slow frame: the game catches up, 6 ticks at most */
#ifdef PROFILE
#ifdef HALT
        if (t < HALT) ++loops;                       /* only until the game stops */
#else
        ++loops;
#endif
#endif
        last = now;
#ifdef PROFILE
        u32 t0 = now_lines(), t1, t2;
#endif
        read_input(&in);
        while (n--) {
#ifdef HALT
            if (t >= HALT) break;
#endif
#ifdef AUTOPLAY
            if (g.state != S_TITLE || t >= TITLE_HOLD) game_autoplay(&g, &in);    /* for every tick, so the game is the same at any frame rate */
#endif
            game_tick(&g, &in);
            ++t;
            if (g.paused || g.state == S_TITLE) audio_mute();
            else { audio_play(g.snd); audio_tick(); }
            g.snd = 0;
            if (g.state != S_TITLE && !g.paused) {
                if (++star_slow >= STAR_ROWS) star_slow = 0;
                if ((star_fast += 2) >= STAR_ROWS) star_fast -= STAR_ROWS;
            }
        }
#if defined(PROFILE) && defined(HALT)
        if (t >= HALT && !vbl_halt) vbl_halt = vbl_count - vbl_start;
#endif
#ifdef PROFILE
        t1 = now_lines();
#endif
        draw(&g);
#ifdef PROFILE
        t2 = now_lines();
#ifdef HALT
        if (t < HALT)
#endif
        { lines_tick += t1 - t0; lines_draw += t2 - t1; }
#endif
    }
}
