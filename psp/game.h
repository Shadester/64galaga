/* Galaga game rules, ported from 64galaga. No platform headers: host-testable.
 * Logic runs at the C64 PAL rate (50 ticks/s) in C64 sprite coordinates:
 * play area x 24..343, y 50..249. x/y are the top-left of a 24x21 sprite box. */
#ifndef GAME_H
#define GAME_H

#ifdef RULES_ARCADE   /* the arcade rules: 40 enemies, see ../ARCADE.md */
#define NAL 40
#else
#define NAL 32
#endif
#define TICK_HZ 50

enum { S_TITLE, S_INTRO, S_PLAY, S_DYING, S_GAMEOVER, S_CAPTURED, S_RESULT, S_READY };
enum { T_BOSS, T_BUTTERFLY, T_BEE };
enum { A_DEAD, A_FORM, A_DIVE, A_RETURN, A_EXPLODE, A_BEAM, A_ENTER };
/* cap: tractor beam / captive state */
enum { C_NONE, C_DIVING, C_BEAM, C_PULL, C_CARRY, C_RESCUE };
/* Sound events, one bit each; the platform clears Game.snd after reading. */
enum {
    SND_SHOOT = 1, SND_EXPLODE = 2, SND_HIT = 4, SND_DEATH = 8, SND_SWOOP = 16,
    JG_STAGE = 32, JG_OVER = 64, JG_CAPTURE = 128, JG_RESCUE = 256, JG_BONUS = 512
};

typedef struct {
    int x, y, st, type, hp, timer, dir, esc, capdive, fired;
    int path, pstep, mir, ent, dly;   /* ent: 0 waiting, 1 on path, 2 homing */
} Alien;
typedef struct { int x, y, act, dx; } Bullet;
typedef struct { int left, right, fire, pause, quit; } Input;  /* pause/quit are edge pulses */

typedef struct {
    int state, paused, stateTimer, frame, prevFire;
    int score, hi, lives, stage, diff, nextBonus, challenge, chalVal, chalHits, chalTimer;
    int shots, hits;
    int px, py, invuln, dual, dyingQuiet;
    int formDx, formDir, formTimer, entering, diveTimer;
    int cap, capBoss, beamLen, beamAcc, beamTimer, rx, ry;
    int snd, saveReq;
    Alien al[NAL];
    Bullet ps[4], eb[3];
} Game;

void game_init(Game *g, int hiScore);
void game_tick(Game *g, const Input *in);
void game_autoplay(const Game *g, Input *in);
int slot_x(int i);
int slot_y(int i);

#endif
