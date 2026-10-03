/* Host-side rule checks of the arcade rules (the default). Build: make test */
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
static void formation(void) {   /* everybody in slot */
    int i;
    for (i = 0; i < NAL; ++i) { g.al[i].st = A_FORM; g.al[i].x = slot_x(i); g.al[i].y = slot_y(i); }
    g.entering = 0;
}
static void shoot(int i) {   /* bullet that hits alien i next collision pass */
    g.ps[0].act = 1; g.ps[0].x = g.al[i].x + 6; g.ps[0].y = g.al[i].y;
    update_collisions(&g);
}
static void expect_score(int s) { if (g.score != s) { printf("score %d, want %d\n", g.score, s); assert(0); } }

int main(void) {
    int i, steps;
    paths_init();
    assert(NAL == 40 && EBN == 8);
    for (i = 0; i < ARC_NPATH; ++i) {   /* every path is long enough and starts at the edge of the 24..343 x 50..249 play area */
        int x = arc_path[i].sx, y = arc_path[i].sy;
        assert(arc_path[i].n > 50 && (x < 32 || x > 335 || y < 50));
    }

    /* scoring table */
    begin(1); formation();
    shoot(20); expect_score(50);      /* bee, formation */
    shoot(5); expect_score(130);      /* butterfly, formation */
    g.al[6].st = A_DIVE; shoot(6); expect_score(290);
    g.al[21].st = A_DIVE; shoot(21); expect_score(390);
    shoot(0); expect_score(390); assert(g.al[0].hp == 1);   /* boss: first hit, no points */
    shoot(0); expect_score(540);      /* boss in formation */

    /* boss escorts 400 / 800 / 1600 */
    begin(1); formation(); g.al[1].st = A_DIVE; shoot(1); shoot(1); expect_score(400);
    begin(1); formation(); g.al[1].st = A_DIVE; g.al[6].st = A_DIVE; g.al[6].esc = 2; shoot(1); shoot(1); expect_score(800);
    begin(1); formation(); g.al[1].st = A_DIVE; g.al[6].st = A_DIVE; g.al[6].esc = 2; g.al[7].st = A_DIVE; g.al[7].esc = 2; shoot(1); shoot(1); expect_score(1600);

    /* a bomb is aimed at the ship, but moves sideways at most 0.6 of its fall speed (the arcade's limit) */
    begin(1); formation(); g.px = 300; g.py = 230;
    g.al[0].x = 40; g.al[0].y = 200; spawn_ebullet(&g, &g.al[0]); assert(g.eb[0].dx == BOMB_MAX_DX);
    g.al[0].x = 300; g.al[0].y = 200; spawn_ebullet(&g, &g.al[0]); assert(g.eb[1].dx == 0);
    g.al[0].x = 100; g.al[0].y = 120; g.px = 60; spawn_ebullet(&g, &g.al[0]); assert(g.eb[2].dx == -BOMB_MAX_DX + 0 || (g.eb[2].dx < 0 && g.eb[2].dx >= -BOMB_MAX_DX));

    /* the fly-in waits while the ship is dead: aliens that have not started do not start */
    begin(1); g.lives = 3;
    for (i = 0; i < 5; ++i) game_tick(&g, &none);
    assert(g.al[8].st == A_ENTER && g.al[8].ent == 0);
    {
        int dly = g.al[8].dly;
        player_hit(&g, 0);
        for (i = 0; i < 40; ++i) game_tick(&g, &none);
        assert(g.state == S_DYING && g.al[8].ent == 0 && g.al[8].dly == dly);
    }

    /* bonus lives: 20k, 70k, 140k */
    begin(1); g.lives = 3;
    add_score(&g, 20000); assert(g.lives == 4);
    add_score(&g, 49999); assert(g.lives == 4);
    add_score(&g, 1); assert(g.lives == 5);
    add_score(&g, 70000); assert(g.lives == 6);

    /* challenge stages 3, 7, 11; per-hit value, perfect bonus */
    begin(3); assert(g.challenge && g.chalVal == 100);
    begin(7); assert(g.challenge && g.chalVal == 100);
    begin(11); assert(g.challenge && g.chalVal == 100);
    begin(4); assert(!g.challenge);
    begin(3);
    for (i = 0; i < NAL; ++i) { g.al[i].st = A_ENTER; g.al[i].ent = 1; g.al[i].x = 100; g.al[i].y = 100 + i; }
    for (i = 0; i < NAL; ++i) shoot(i);
    expect_score(100 * NAL); assert(g.chalHits == NAL);
    enter_result(&g); expect_score(100 * NAL + 10000);

    /* difficulty skips challenge stages */
    begin(1); g.diff = 1;
    g.stage = 1; next_stage(&g); assert(g.diff == 2 && g.stage == 2);
    next_stage(&g); assert(g.diff == 3 && g.stage == 3 && g.challenge);
    next_stage(&g); assert(g.diff == 3 && g.stage == 4);

    /* capture -> carry -> rescue -> dual */
    begin(1); formation(); g.px = g.al[2].x;
    g.sortie[0] = g.sortie[1] = g.sortie[2] = 1 << 30;   /* only the capture boss dives */
    start_dive(&g, 2, 1, 20); assert(g.cap == C_DIVING);
    for (steps = 0; steps < 600 && g.cap != C_BEAM; ++steps) game_tick(&g, &none);
    assert(g.cap == C_BEAM);
    g.px = g.al[2].x;
    for (steps = 0; steps < 300 && g.state == S_PLAY; ++steps) game_tick(&g, &none);
    assert(g.state == S_CAPTURED && g.cap == C_PULL);
    for (steps = 0; steps < 100 && g.state == S_CAPTURED; ++steps) game_tick(&g, &none);
    assert(g.state == S_DYING && g.dyingQuiet && g.cap == C_CARRY && g.lives == 2);
    for (steps = 0; steps < 400 && g.state != S_PLAY; ++steps) game_tick(&g, &none);
    assert(g.state == S_PLAY && g.invuln > 0);
    g.al[2].st = A_DIVE; g.al[2].x = 150; g.al[2].y = 60; g.al[2].hp = 1; shoot(2);
    assert(g.cap == C_RESCUE);
    for (steps = 0; steps < 300 && g.cap == C_RESCUE; ++steps) game_tick(&g, &none);
    assert(g.dual == 1 && g.cap == C_NONE);
    /* dual hit: lose a half, keep the life */
    g.invuln = 0; i = g.lives; g.eb[0] = (Bullet){g.px + 16, 230, 1, 0, 0}; update_collisions(&g);
    assert(g.dual == 0 && g.lives == i && g.state == S_PLAY);

    /* shooting a carrier in formation loses the captive */
    begin(1); formation(); g.cap = C_CARRY; g.capBoss = 1; shoot(1); shoot(1); assert(g.cap == C_NONE);

    /* a challenge stage plays out to its result screen, and its aliens never hurt the ship */
    begin(3); g.lives = 3; g.px = 160;
    for (steps = 0; steps < 3000 && g.state == S_PLAY; ++steps) {
        Input in = {0, 0, (steps & 15) < 2, 0, 0};
        in.left = g.px > 60 && (steps / 100) & 1; in.right = !in.left;
        game_tick(&g, &in);
    }
    assert(g.state == S_RESULT && g.lives == 3);
    {   /* shots fired on the result screen do not change its ratio */
        int shots = g.shots, hits = g.hits;
        for (steps = 0; steps < 60 && g.state == S_RESULT; ++steps) {
            Input in = {0, 0, (steps & 3) < 2, 0, 0};
            game_tick(&g, &in);
        }
        assert(g.shots == shots && g.hits == hits);
    }

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
