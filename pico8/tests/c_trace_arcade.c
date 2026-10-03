/* Runs psp/game.c and the scripted input of tests/test_lockstep.py, and prints the whole game state after every
 * tick (the fields of thumby/tests/c_trace.c, then the fields of the arcade rules). Flags: -DTICKS=n -DSTART_STAGE=n -DFORCECAPTURE -DBEAMTEST */
#include <stdio.h>

static unsigned lcg = 1;
static int lcg_rand(void) { lcg = (lcg * 1103515245u + 12345u) & 0x7fffffffu; return (int)lcg; }
static void lcg_srand(unsigned s) { lcg = s; }
#define rand lcg_rand
#define srand lcg_srand
#include "../../psp/game.c"

#ifndef TICKS
#define TICKS 3000
#endif

static void script(const Game *g, int t, Input *in) {
    memset(in, 0, sizeof *in);
    in->fire = (t % 7) < 2;
    in->left = (t / 90) % 2;
    in->right = !in->left;
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

int main(void) {
    Game g;
    Input in;
    int t, i;
    paths_init();
    game_init(&g, 0);
    for (t = 0; t < TICKS; ++t) {
        script(&g, t, &in);
#ifdef BEAMTEST   /* the ship cannot be hit, except under the beam: to see the capture, the carrying and the rescue */
        g.invuln = (g.cap == C_BEAM || g.cap == C_PULL) ? 0 : 100;
        if (g.cap == C_BEAM) memset(g.eb, 0, sizeof g.eb);
#endif
        game_tick(&g, &in);
        printf("%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d",
               g.state, g.paused, g.stateTimer, g.frame, g.score, g.hi, g.lives, g.stage, g.diff, g.nextBonus,
               g.challenge, g.chalVal, g.chalHits, g.chalTimer, g.shots, g.hits, g.px, g.py, g.invuln, g.dual,
               g.dyingQuiet, g.formDx, g.formDir, g.formTimer, g.entering, g.cap, g.capBoss, g.beamLen,
               g.beamAcc, g.beamTimer, g.rx, g.ry, g.snd);
        printf(" %d %d %d %d %d %d %d %d %d %d %d %d %d %d", g.fclk, g.ff, g.swayPos, g.swayDir, g.breathe, g.bstep, g.clk,
               g.af, g.tmr2, g.hold, g.wingm, g.bombFlags, g.beamPh, g.beamStep);
        printf(" %d %d %d", g.sortie[0], g.sortie[1], g.sortie[2]);
        for (i = 0; i < NAL; ++i) {
            const Alien *a = &g.al[i];
            printf(" %d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d", a->st, a->x, a->y, a->hp, a->timer, a->dir, a->esc, a->capdive,
                   a->pstep, a->ent, a->dly, a->dpath, a->bflags, a->btmr);
        }
        for (i = 0; i < 4; ++i) printf(" %d,%d,%d", g.ps[i].x, g.ps[i].y, g.ps[i].act);
        for (i = 0; i < EBN; ++i) printf(" %d,%d,%d,%d,%d", g.eb[i].x, g.eb[i].y, g.eb[i].act, g.eb[i].dx, g.eb[i].ax);
        printf("\n");
        g.snd = 0; g.saveReq = 0;
    }
    return 0;
}
