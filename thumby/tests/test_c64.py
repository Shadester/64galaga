#!/usr/bin/env python3
"""Rule checks of Galaga/game.py (a translation of psp/tests/test_game.c). Usage: python3 tests/test_game.py"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Galaga'))
import game as G  # noqa: E402
from game import *  # noqa: E402,F403

none = Input()
press = Input()
press.fire = 1
g = None


def begin(stage):
    global g
    g = Game(0)
    g.tick(press)
    g.tick(none)
    assert g.state == S_INTRO
    g.stage = stage
    if stage > 1:
        g.diff = min(8, 1 + (stage - 1 - stage // 4))
    g.setup_stage()
    g.state = S_PLAY
    g.invuln = 0


def formation():
    for i, a in enumerate(g.al):
        a.st = A_FORM
        a.x = slot_x(i)
        a.y = slot_y(i)
    g.entering = 0


def shoot(i):   # a bullet that hits alien i in the next collision pass
    g.ps[0].act = 1
    g.ps[0].x = g.al[i].x + 6
    g.ps[0].y = g.al[i].y
    g.update_collisions()


def expect_score(s):
    assert g.score == s, (g.score, s)


# every path starts outside the 24..343 x 50..249 play area
for p in G.PATHS:
    assert p[0] < 0 or p[0] > 344 or p[1] < 30
assert 140 < G.PATHS[P_C][2] < 185 and 155 < G.PATHS[P_D][2] < 195

# scoring table
begin(1); formation()
shoot(20); expect_score(50)           # bee, formation
shoot(5); expect_score(130)           # butterfly, formation
g.al[6].st = A_DIVE; shoot(6); expect_score(290)
g.al[19].st = A_DIVE; shoot(19); expect_score(390)
shoot(0); expect_score(390); assert g.al[0].hp == 1     # boss: first hit, no points
shoot(0); expect_score(540)           # boss in formation

# boss escorts 400 / 800 / 1600
begin(1); formation(); g.al[1].st = A_DIVE; shoot(1); shoot(1); expect_score(400)
begin(1); formation(); g.al[1].st = A_DIVE; g.al[6].st = A_DIVE; g.al[6].esc = 2; shoot(1); shoot(1); expect_score(800)
begin(1); formation(); g.al[1].st = A_DIVE
g.al[6].st = A_DIVE; g.al[6].esc = 2; g.al[7].st = A_DIVE; g.al[7].esc = 2; shoot(1); shoot(1); expect_score(1600)

# bonus lives: 20k, 70k, 140k
begin(1); g.lives = 3
g.add_score(20000); assert g.lives == 4
g.add_score(49999); assert g.lives == 4
g.add_score(1); assert g.lives == 5
g.add_score(70000); assert g.lives == 6

# challenge stages 3, 7, 11; per-hit value, perfect bonus
begin(3); assert g.challenge and g.chalVal == 100
begin(7); assert g.challenge and g.chalVal == 200
begin(11); assert g.challenge and g.chalVal == 300
begin(4); assert not g.challenge
begin(3)
for i, a in enumerate(g.al):
    a.st = A_ENTER; a.ent = 1; a.x = 100; a.y = 100 + i
for i in range(NAL):
    shoot(i)
expect_score(3200); assert g.chalHits == NAL
g.enter_result(); expect_score(13200)

# difficulty skips challenge stages
begin(1); g.diff = 1
g.stage = 1; g.next_stage(); assert g.diff == 2 and g.stage == 2
g.next_stage(); assert g.diff == 3 and g.stage == 3 and g.challenge
g.next_stage(); assert g.diff == 3 and g.stage == 4

# capture -> carry -> rescue -> dual
begin(1); formation(); g.px = g.al[2].x
g.start_dive(2, 1, 20); assert g.cap == C_DIVING
steps = 0
while steps < 600 and g.cap != C_BEAM:
    g.tick(none); steps += 1
assert g.cap == C_BEAM
g.px = g.al[2].x
steps = 0
while steps < 100 and g.state == S_PLAY:
    g.tick(none); steps += 1
assert g.state == S_CAPTURED and g.cap == C_PULL
steps = 0
while steps < 100 and g.state == S_CAPTURED:
    g.tick(none); steps += 1
assert g.state == S_DYING and g.dyingQuiet and g.cap == C_CARRY and g.lives == 2
steps = 0
while steps < 400 and g.state != S_PLAY:
    g.tick(none); steps += 1
assert g.state == S_PLAY and g.invuln > 0
a = g.al[2]; a.st = A_DIVE; a.x = 150; a.y = 60; a.hp = 1; shoot(2)
assert g.cap == C_RESCUE
steps = 0
while steps < 300 and g.cap == C_RESCUE:
    g.tick(none); steps += 1
assert g.dual == 1 and g.cap == C_NONE
# dual hit: lose a half, keep the life
g.invuln = 0; lives = g.lives
b = g.eb[0]; b.x = g.px + 16; b.y = 230; b.act = 1; b.dx = 0
g.update_collisions()
assert g.dual == 0 and g.lives == lives and g.state == S_PLAY

# shooting a carrier in formation loses the captive
begin(1); formation(); g.cap = C_CARRY; g.capBoss = 1; shoot(1); shoot(1); assert g.cap == C_NONE

# a challenge stage plays out to its result screen, and its aliens never hurt the ship
begin(3); g.lives = 3; g.px = 160
steps = 0
inp = Input()
while steps < 3000 and g.state == S_PLAY:
    inp.fire = 1 if (steps & 15) < 2 else 0
    inp.left = 1 if g.px > 60 and (steps // 100) & 1 else 0
    inp.right = 0 if inp.left else 1
    g.tick(inp); steps += 1
assert g.state == S_RESULT and g.lives == 3
# shots fired on the result screen do not change its ratio
shots, hits = g.shots, g.hits
steps = 0
while steps < 60 and g.state == S_RESULT:
    inp.fire = 1 if (steps & 3) < 2 else 0
    g.tick(inp); steps += 1
assert g.shots == shots and g.hits == hits

# full unattended run: no exception, invariants hold
g = Game(0)
inp = Input()
for steps in range(100000):
    G.autoplay(g, inp)
    g.tick(inp)
    assert 24 <= g.px <= 320 and 0 <= g.lives <= 9
    for a in g.al:
        assert -400 < a.x < 800 and -100 < a.y < 400
print('ok (final stage %d, hi %d)' % (g.stage, g.hi))
