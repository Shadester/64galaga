/* Host-side checks of the arcade scheduler on the C64's layout (-DRULES_ARCADE32): 32 aliens, our own fly-in and dives. Build: make test */
#include <stdio.h>
#include <assert.h>
#include "../game.c"

static Game g;
static Input none, press = {0, 0, 1, 0, 0};

static void begin(int stage) {
    game_init(&g, 0);
    game_tick(&g, &press); game_tick(&g, &none);
    assert(g.state == S_INTRO);
    g.stage = stage; if (stage > 1) { g.diff = 1 + (stage - 1 - stage / 4); if (g.diff > 8) g.diff = 8; }
    setup_stage(&g); g.state = S_PLAY;
    g.invuln = 0;
}
static void formation(void) {
    int i;
    for (i = 0; i < NAL; ++i) { g.al[i].st = A_FORM; g.al[i].x = slot_x(i); g.al[i].y = slot_y(i); }
    g.entering = 0;
}
static void shoot(int i) {
    g.ps[0].act = 1; g.ps[0].x = g.al[i].x + 6; g.ps[0].y = g.al[i].y;
    update_collisions(&g);
}

int main(void) {
    int i, steps, dives = 0, escorts = 0, bombs = 0, prev[NAL] = {0};
    paths_init();
    assert(NAL == 32 && EBN == 4);

    /* a challenge stage: 100 for each alien, 10,000 when all 32 are hit */
    begin(3); assert(g.challenge && g.chalVal == 100);
    for (i = 0; i < NAL; ++i) { g.al[i].st = A_ENTER; g.al[i].ent = 1; g.al[i].x = 100; g.al[i].y = 100 + i; }
    for (i = 0; i < NAL; ++i) shoot(i);
    assert(g.score == 100 * NAL && g.chalHits == NAL);
    enter_result(&g); assert(g.score == 100 * NAL + 10000);

    /* the scheduler: a stage in formation, nothing shoots the aliens: bees, butterflies and a boss with escorts dive, bombs fall */
    begin(1); formation(); g.px = 100;
    for (steps = 0; steps < 3000; ++steps) {
        game_tick(&g, &none);
        g.invuln = 100;
        for (i = 0; i < NAL; ++i) {
            if (g.al[i].st == A_DIVE && prev[i] != A_DIVE) { ++dives; escorts += g.al[i].esc != 0; }
            prev[i] = g.al[i].st;
        }
        for (i = 0; i < EBN; ++i) bombs += g.eb[i].act;
    }
    assert(dives >= 8 && escorts >= 2 && bombs > 0);

    /* a bomb is aimed at the ship, at most 0.6 sideways for each pixel it falls */
    begin(1); formation(); g.px = 300; g.py = 230;
    g.al[18].x = 40; g.al[18].y = 120; spawn_ebullet(&g, &g.al[18]); assert(g.eb[0].dx == BOMB_MAX_DX);

    /* a ship that is taken: the beam grows, holds, and the boss carries the ship away */
    begin(1); formation(); g.px = g.al[2].x;
    g.sortie[0] = g.sortie[1] = g.sortie[2] = 1 << 30;
    start_dive(&g, 2, 1, 20); assert(g.cap == C_DIVING);
    for (steps = 0; steps < 600 && g.cap != C_BEAM; ++steps) game_tick(&g, &none);
    assert(g.cap == C_BEAM);
    g.px = g.al[2].x;
    for (steps = 0; steps < 300 && g.state == S_PLAY; ++steps) game_tick(&g, &none);
    assert(g.state == S_CAPTURED && g.cap == C_PULL);

    /* full unattended run: no crash, invariants hold */
    game_init(&g, 0);
    for (steps = 0; steps < 500000; ++steps) {
        Input in; game_autoplay(&g, &in); in.pause = in.quit = 0;
        game_tick(&g, &in);
        assert(g.px >= 24 && g.px <= 320 && g.lives >= 0 && g.lives <= 9);
        for (i = 0; i < NAL; ++i) assert(g.al[i].x > -400 && g.al[i].x < 800 && g.al[i].y > -100 && g.al[i].y < 400);
    }
    printf("ok (final stage %d, hi %d)\n", g.stage, g.hi);
    return 0;
}
