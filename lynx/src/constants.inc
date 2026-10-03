; Memory map, screen geometry and shared limits

SCR_W       = 160
SCR_H       = 102
BUF0        = $a000             ; two 8160-byte frame buffers (code and data end below $a000)
BUF1        = $c000
BUF_FLIP    = (BUF0 ^ BUF1) >> 8
SCB_SIZE    = 15                ; control, flags, collision, next, data, x, y, hsize, vsize
BG_SIZE     = 23                ; background SCB: the same plus the 8-byte pen map
MAX_SCB     = 140               ; 40 aliens (the arcade formation) need 8 more
NUM_STARS   = 12

        .include "art.inc"

; ---- Game constants (C64 values: the rules run in C64 sprite coordinates, x 24..343, y 50..249) ----
MAX_ENEMIES     = 40            ; the arcade formation: 4 bosses, 16 butterflies, 20 bees (tools/gen_arcade.py)
EBN             = 8             ; enemy bombs on the screen
VS_PLAYER       = MAX_ENEMIES
VS_PBUL         = VS_PLAYER+1   ; 4 slots
VS_EBUL         = VS_PBUL+4     ; EBN slots
VS_DUAL         = VS_EBUL+EBN   ; second ship of the dual fighter
VS_CAPT         = VS_DUAL+1     ; captured ship carried by a boss
MAX_SPRITES     = VS_CAPT+3     ; ship + enemies + 4 player bullets + enemy bullets + extras
VS_NONE         = MAX_SPRITES

; The geometry of the field: the same names as the G_* macros of psp/game.h (the C reference). The portrait ROM (-D PORTRAIT=1) has the portrait field.
.ifdef PORTRAIT
PLAYER_Y        = 242
SCREEN_LEFT     = 4
SCREEN_RIGHT    = 186           ; the ship's biggest x (a dual fighter: less DUAL_DX)
SHIP_X0         = 95
SHIP_V          = 1
SHOT_DX         = 7
SHOT_DY         = 12
SHOT_TOP        = 4
OFF_Y           = 250
RET_Y0          = -16           ; a diver returns from above the screen
BEAM_Y          = 208
BOMB_LOW_Y      = 149
BOMB_DY         = 6
MID_X           = 95
CAPT_DY         = 12
HOME_V          = 2
HOME_NEAR       = 2
PEEL_VX         = 1
PEEL_VY         = 1
TAIL_VY         = 2
PULL_DONE       = 14
HB_SHOT_Y       = 5
HB_SHOT_XL      = 4
HB_SHOT_XR      = 8
HB_BOMB_Y0      = -2
HB_BOMB_Y1      = 7
HB_BOMB_XL      = 4
HB_BOMB_XR      = 5
HB_RAM_Y0       = 5
HB_RAM_Y1       = 5
HB_RAM_X        = 5
HB_BEAM_XL      = 13
HB_BEAM_XR      = 12
HB_DOCK_L       = 3
HB_DOCK_R       = 2
.else
PLAYER_Y        = 230
SCREEN_LEFT     = 24
SCREEN_RIGHT    = 320           ; Max player X (9-bit), sprite right edge at 344
SHIP_X0         = 160
SHIP_V          = 2
SHOT_DX         = 3
SHOT_DY         = 16
SHOT_TOP        = 20
OFF_Y           = 244
RET_Y0          = 0
BEAM_Y          = 196
BOMB_LOW_Y      = 163
BOMB_DY         = 8
MID_X           = 184
CAPT_DY         = 16
HOME_V          = 2
HOME_NEAR       = 3
PEEL_VX         = 2
PEEL_VY         = 1
TAIL_VY         = 3
PULL_DONE       = 22
HB_SHOT_Y       = 8
HB_SHOT_XL      = 6
HB_SHOT_XR      = 12
HB_BOMB_Y0      = -3
HB_BOMB_Y1      = 10
HB_BOMB_XL      = 6
HB_BOMB_XR      = 7
HB_RAM_Y0       = 7
HB_RAM_Y1       = 8
HB_RAM_X        = 8
HB_BEAM_XL      = 20
HB_BEAM_XR      = 19
HB_DOCK_L       = 4
HB_DOCK_R       = 3
.endif
RET_V           = 2             ; a diver returning from the top
CDIVE_V0        = 2             ; a capture dive (stage 1-4, later)
CDIVE_V1        = 3
SHOT_V          = 4             ; a shot's speed
DUAL_DX         = 16            ; the second ship of a dual fighter, a docked captive
RESC_VY         = 3             ; a rescued ship flies down ...
RESC_VX         = 2             ; ... and sideways
PULL_V          = 2             ; the captured ship is pulled up

; Sprite ids (art.inc); +1 = second animation frame, explosions are consecutive
SPR_PLAYER      = SP_PLAYER
SPR_PBUL        = SP_PBUL
SPR_EBUL        = SP_EBUL
SPR_BEE         = SP_BEE_A
SPR_BFLY        = SP_BFLY_A
SPR_BOSS        = SP_BOSS_A
SPR_BOSSP       = SP_BOSSP_A    ; the boss after one hit (purple)
SPR_EXPL1       = SP_EXPL1
SPR_PEXP        = SP_PEXP1

; Game states
GS_TITLE        = 0
GS_INTRO        = 1
GS_PLAY         = 2
GS_DYING        = 3
GS_GAMEOVER     = 4
GS_CAPTURED     = 5             ; Player is being pulled up by a tractor beam
GS_RESULT       = 6             ; Shots / hits / ratio screen after a stage
GS_READY        = 7             ; "READY" before the ship respawns

; Joystick (JOYSTICK $fcb0 is converted to the C64's active-low bits)
JS_LEFT         = $04
JS_RIGHT        = $08
JS_FIRE         = $10

SCREEN_RAM      = 0             ; The C64 text positions (row * 40 + column) survive as message positions
