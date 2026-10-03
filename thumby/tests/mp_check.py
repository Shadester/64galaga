# Runs the rules for a scripted game and prints a checksum of the state: CPython and MicroPython (the engine's)
# must print the same number. Usage: python3 tests/mp_check.py [c64]   |   tools/run_mp.sh tests/mp_check.py [c64]  (c64: the C64 rules, else the arcade rules)
import sys
sys.path.append('../Galaga')
sys.path.append('Galaga')
import game as G

if 'c64' in sys.argv:
    G.set_arcade(False)

g = G.Game(0)
inp = G.Input()
c = 0
for t in range(20000):
    G.autoplay(g, inp)
    g.tick(inp)
    v = [g.state, g.score, g.lives, g.px, g.stage, g.formDx, g.cap, g.dual, g.shots, g.hits, g.snd]
    for a in g.al:
        v += [a.st, a.x, a.y]
    for b in g.eb:
        v += [b.x, b.y, b.act]
    for x in v:
        c = (c * 31 + x) & 0xffffffff
    g.snd = 0
print('checksum', c, 'stage', g.stage, 'score', g.score)
