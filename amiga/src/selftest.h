/* Runs the scripted game of thumby/tests/c_trace.c (psp/game.c with scripted input) and returns a hash of the whole game
 * state after every tick. tests/selftest_native.c computes it on this Mac, the Amiga build computes it on the 68000:
 * the numbers must be the same. Flags (the same as for c_trace.c): START_STAGE=n, FORCECAPTURE. */
#ifndef SELFTEST_H
#define SELFTEST_H
#include "game.h"

static unsigned st_hash;
/* rotate, xor, add: no multiplication, because a 68000 multiplies 32 bits slowly */
static void st_add(int v) {
    st_hash = ((st_hash << 5) | (st_hash >> 27)) ^ (unsigned)v;
    st_hash += 0x9e3779b9u;
}

static void st_script(const Game *g, int t, Input *in) {
    in->fire = (t % 7) < 2;
    in->left = (t / 90) % 2;
    in->right = !in->left;
    in->pause = in->quit = 0;
#ifdef FORCECAPTURE
    if (g->state == S_PLAY || g->state == S_RESULT) in->fire = 0;
    if (g->cap == C_BEAM || g->cap == C_CARRY || g->cap == C_DIVING) {
        int bx = g->al[g->capBoss].x;
        in->left = g->px > bx + 2; in->right = g->px < bx - 2;
        if (g->cap == C_CARRY) in->fire = (t & 3) < 2;
    }
#endif
    if (t % 1500 == 1499) in->pause = 1;
    if (t % 1500 == 1503) in->pause = 1;
}

static unsigned selftest_hash(int ticks) {
    static Game g;
    Input in;
    int t, i;
    game_init(&g, 0);
    st_hash = 0x811c9dc5u;
    for (t = 0; t < ticks; ++t) {
        st_script(&g, t, &in);
        game_tick(&g, &in);
        st_add(g.state); st_add(g.paused); st_add(g.stateTimer); st_add(g.frame); st_add(g.score); st_add(g.hi);
        st_add(g.lives); st_add(g.stage); st_add(g.diff); st_add(g.nextBonus); st_add(g.challenge); st_add(g.chalVal);
        st_add(g.chalHits); st_add(g.chalTimer); st_add(g.shots); st_add(g.hits); st_add(g.px); st_add(g.py);
        st_add(g.invuln); st_add(g.dual); st_add(g.dyingQuiet); st_add(g.formDx); st_add(g.formDir); st_add(g.formTimer);
        st_add(g.entering); st_add(g.cap); st_add(g.capBoss); st_add(g.beamLen); st_add(g.beamAcc);
        st_add(g.beamTimer); st_add(g.rx); st_add(g.ry); st_add(g.snd);
        st_add(g.beamPh); st_add(g.beamStep); st_add(g.clk); st_add(g.af); st_add(g.tmr2); st_add(g.hold); st_add(g.wingm);
        st_add(g.bombFlags); st_add(g.sortie[0]); st_add(g.sortie[1]); st_add(g.sortie[2]);
        st_add(g.fclk); st_add(g.ff); st_add(g.swayPos); st_add(g.swayDir); st_add(g.breathe); st_add(g.bstep);
        for (i = 0; i < NAL; ++i) {
            const Alien *a = &g.al[i];
            st_add(a->st); st_add(a->x); st_add(a->y); st_add(a->hp); st_add(a->timer); st_add(a->dir); st_add(a->esc);
            st_add(a->capdive); st_add(a->pstep); st_add(a->ent); st_add(a->dly);
            st_add(a->type); st_add(a->path); st_add(a->mir); st_add(a->bflags); st_add(a->btmr); st_add(a->dpath);
        }
        for (i = 0; i < 4; ++i) { st_add(g.ps[i].x); st_add(g.ps[i].y); st_add(g.ps[i].act); }
        for (i = 0; i < EBN; ++i) { st_add(g.eb[i].x); st_add(g.eb[i].y); st_add(g.eb[i].act); st_add(g.eb[i].dx); st_add(g.eb[i].ax); }
        g.snd = g.saveReq = 0;
    }
    return st_hash;
}
#endif
