; Memory map, screen geometry and shared limits

; The rules: the arcade's (the default: 40 aliens) or, with -D RULES_C64=1, the rules of the C64 game (32 aliens)
.ifndef RULES_C64
.ifndef ARCADE
ARCADE = 1
.endif
.endif
SCR_W       = 160
SCR_H       = 102
BUF0        = $a000             ; two 8160-byte frame buffers (code and data end below $a000)
BUF1        = $c000
BUF_FLIP    = (BUF0 ^ BUF1) >> 8
SCB_SIZE    = 15                ; control, flags, collision, next, data, x, y, hsize, vsize
BG_SIZE     = 23                ; background SCB: the same plus the 8-byte pen map
.ifdef ARCADE
MAX_SCB     = 140               ; 40 aliens (the arcade formation) need 8 more
.else
MAX_SCB     = 120
.endif
NUM_STARS   = 12

        .include "art.inc"

; ---- Game constants (C64 values: the rules run in C64 sprite coordinates, x 24..343, y 50..249) ----
.ifdef ARCADE
MAX_ENEMIES     = 40            ; the arcade formation: 4 bosses, 16 butterflies, 20 bees (tools/gen_arcade.py)
.else
MAX_ENEMIES     = 32
.endif
.ifdef ARCADE
EBN             = 8             ; enemy bombs on the screen
.else
EBN             = 3
.endif
VS_PLAYER       = MAX_ENEMIES
VS_PBUL         = VS_PLAYER+1   ; 4 slots
VS_EBUL         = VS_PBUL+4     ; EBN slots
VS_DUAL         = VS_EBUL+EBN   ; second ship of the dual fighter
VS_CAPT         = VS_DUAL+1     ; captured ship carried by a boss
MAX_SPRITES     = VS_CAPT+3     ; ship + enemies + 4 player bullets + enemy bullets + extras
VS_NONE         = MAX_SPRITES
PLAYER_Y        = 230
SCREEN_LEFT     = 24
SCREEN_RIGHT    = 320           ; Max player X (9-bit), sprite right edge at 344

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
