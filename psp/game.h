/* Galaga game rules, ported from 64galaga. No platform headers: host-testable.
 * Logic runs at the C64 PAL rate (50 ticks/s) in C64 sprite coordinates:
 * play area x 24..343, y 50..249. x/y are the top-left of a 24x21 sprite box. */
#ifndef GAME_H
#define GAME_H

/* Two layouts, both with the arcade's rules (see ../ARCADE.md): the default has 40 enemies like the arcade (RULES_ARCADE).
 * -DRULES_ARCADE32 puts the arcade's scheduler, bombs, beam, respawn and challenge scoring on the C64 game's layout (32 enemies),
 * fly-in and dives. That is what the 6502 C64 game plays (it cannot show the arcade's rows of 10). */
#ifndef RULES_ARCADE32
#define RULES_ARCADE
#define NAL 40
#define EBN 8   /* enemy bombs on the screen */
#else
#define NAL 32
#define EBN 4
#endif
#define TICK_HZ 50

/* The geometry of the field, in game units (2 units are one Lynx pixel; x / y are the top left of a sprite box). The default is the C64 field: x 24..343, y 50..249,
 * 24 x 21 sprites. -DRULES_PORTRAIT is the arcade's own portrait field at 0.88 units per arcade pixel (see tools/gen_arcade.py portrait): 16 x 16 sprites. */
#ifdef RULES_PORTRAIT
#define G_LEFT 4            /* the ship's smallest x */
#define G_SHIP_XMAX 186     /* its biggest x (a dual fighter: less one ship) */
#define G_SHIP_X0 95        /* where it starts and comes back */
#define G_SHIP_Y 242        /* its y (the arcade's fighter, y 297, in the bent field of tools/gen_arcade.py) */
#define G_DUAL_DX 16        /* the second ship of a dual fighter, and a captive docked beside it */
#define G_SHIP_V 1
#define G_SHOT_DX 7         /* a shot leaves the ship this far from its x ... */
#define G_SHOT_DY 12        /* ... and this far above its y */
#define G_SHOT_V 4
#define G_SHOT_TOP 4        /* a shot is gone above this y */
#define G_HIDE_Y 255        /* an enemy that waits to fly in */
#define G_RET_Y0 (-16)      /* a diver that comes back from the top starts here */
#define G_OFF_Y 250         /* a diver has left the bottom */
#define G_BEAM_Y 208        /* the capture boss starts the beam (34 units above the ship, as in the C64 field) */
#define G_BOMB_OFF_Y 250    /* a bomb has left the bottom */
#define G_BOMB_LOW_Y 149    /* no bombs from a diver below this y (97 of the arcade's 288 lines above the ship, 0.96 units a line) */
#define G_BOMB_TOP_Y 0      /* no bombs from an alien above the screen (a bomb keeps y in one byte on the Lynx) */
#define G_BOMB_DY 6         /* a bomb starts this far below the alien's y */
#define G_MID_X 95          /* the middle of the field (the side a diver peels off to) */
#define G_CAPT_DY 12        /* a captive rides this far above its boss */
#define G_HOME_V 2          /* speeds in units a tick: flying home ... */
#define G_HOME_NEAR 2       /* ... it is home within this distance */
#define G_RET_V 2           /* a diver returning from the top */
#define G_PEEL_VX 1         /* a capture dive peels off sideways ... */
#define G_PEEL_VY 1
#define G_CDIVE_V0 2        /* ... and dives (stage 1-4, later) */
#define G_CDIVE_V1 3
#define G_TAIL_VY 2         /* the end of a butterfly's dive path */
#define G_RESC_VY 3         /* a rescued ship flies down ... */
#define G_RESC_VX 2         /* ... and sideways */
#define G_PULL_V 2          /* the captured ship is pulled up */
#define G_PULL_DONE 14      /* ... until it is this close to the boss */
#define G_HB_SHOT_Y 5       /* hit boxes: a shot hits an alien when ... */
#define G_HB_SHOT_XL 4
#define G_HB_SHOT_XR 8
#define G_HB_BOMB_Y0 (-2)   /* a bomb hits the ship from y - 2 to y + 7 ... */
#define G_HB_BOMB_Y1 7
#define G_HB_BOMB_XL 4
#define G_HB_BOMB_XR 5
#define G_HB_RAM_Y0 5       /* an alien rams the ship */
#define G_HB_RAM_Y1 5
#define G_HB_RAM_X 5
#define G_HB_BEAM_XL 13     /* the beam takes the ship */
#define G_HB_BEAM_XR 12
#define G_HB_DOCK_L 3       /* a rescued ship docks */
#define G_HB_DOCK_R 2
#define G_FORM_DX(p) ((p) * 88 / 100)   /* the swing of the formation: arcade pixels to units */
#else
#define G_LEFT 24
#define G_SHIP_XMAX 320
#define G_SHIP_X0 160
#define G_SHIP_Y 230
#define G_DUAL_DX 16
#define G_SHIP_V 2
#define G_SHOT_DX 3
#define G_SHOT_DY 16
#define G_SHOT_V 4
#define G_SHOT_TOP 20
#define G_HIDE_Y 255
#define G_RET_Y0 0
#define G_OFF_Y 244
#define G_BEAM_Y 196
#define G_BOMB_OFF_Y 250
#define G_BOMB_LOW_Y 163
#define G_BOMB_TOP_Y (-32000)
#define G_BOMB_DY 8
#define G_MID_X 184
#define G_CAPT_DY 16
#define G_HOME_V 2
#define G_HOME_NEAR 3
#define G_RET_V 2
#define G_PEEL_VX 2
#define G_PEEL_VY 1
#define G_CDIVE_V0 2
#define G_CDIVE_V1 3
#define G_TAIL_VY 3
#define G_RESC_VY 3
#define G_RESC_VX 2
#define G_PULL_V 2
#define G_PULL_DONE 22
#define G_HB_SHOT_Y 8
#define G_HB_SHOT_XL 6
#define G_HB_SHOT_XR 12
#define G_HB_BOMB_Y0 (-3)
#define G_HB_BOMB_Y1 10
#define G_HB_BOMB_XL 6
#define G_HB_BOMB_XR 7
#define G_HB_RAM_Y0 7
#define G_HB_RAM_Y1 8
#define G_HB_RAM_X 8
#define G_HB_BEAM_XL 20
#define G_HB_BEAM_XR 19
#define G_HB_DOCK_L 4
#define G_HB_DOCK_R 3
#define G_FORM_DX(p) ((p) + (p) * 3 / 7)   /* 320 / 224 */
#endif

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
    int x, y, st, type, hp, timer, dir, esc, capdive;
    int path, pstep, mir, ent, dly;   /* ent: 0 waiting, 1 on path, 2 homing */
    int bflags, btmr;   /* bomb flags and the time to the next bomb (arcade frames) */
#ifdef RULES_ARCADE
    int dpath;   /* dive path (-1: free) */
#endif
} Alien;
typedef struct { int x, y, act, dx; int ax; } Bullet;   /* ax: the sideways speed of a bomb is dx / 16 pixel a tick, ax the rest */
typedef struct { int left, right, fire, pause, quit; } Input;  /* pause/quit are edge pulses */

typedef struct {
    int state, paused, stateTimer, frame, prevFire;
    int score, hi, lives, stage, diff, nextBonus, challenge, chalVal, chalHits, chalTimer;
    int shots, hits;
    int px, py, invuln, dual, dyingQuiet;
    int formDx, formDir, formTimer, entering;
    int cap, capBoss, beamLen, beamAcc, beamTimer, rx, ry;
    int snd, saveReq;
    Alien al[NAL];
    /* the dive scheduler runs on the arcade's 60 Hz clock: 6 arcade frames for every 5 ticks */
    int beamPh, beamStep;   /* the beam: 0 grows, 1 holds (the ship is taken), 2 shrinks; ticks for one of its 4 steps */
    int clk, af, tmr2, hold, sortie[3], wingm, bombFlags;   /* tmr2: counts down from 120 once in 32 frames (time since the stage began); hold: no bombs after a boss was shot while it dived */
#ifdef RULES_ARCADE
    int fclk, ff, swayPos, swayDir, breathe, bstep;   /* the formation: swing while the aliens fly in, then breathe (also on the arcade clock) */
#endif
    Bullet ps[4], eb[EBN];
} Game;

void game_init(Game *g, int hiScore);
void game_tick(Game *g, const Input *in);
void game_autoplay(const Game *g, Input *in);
int slot_x(int i);
int slot_y(int i);

#endif
