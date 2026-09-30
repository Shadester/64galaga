; Hardware registers, memory map, game constants and macros
; ===============================================
; MEMORY MAP & HARDWARE REGISTERS
; ===============================================

; VIC-II Registers
SPRITE_ENABLE   = $d015
SPRITE_MCOLOR_EN = $d01c        ; Sprite multicolor enable
SPRITE_MCOLOR1  = $d025         ; Shared multicolor 1
SPRITE_MCOLOR2  = $d026         ; Shared multicolor 2
SPRITE_COLORS   = $d027
SPRITE_PTR      = $07f8
BORDER_COLOR    = $d020
BG_COLOR        = $d021
SCREEN_RAM      = $0400
COLOR_RAM       = $d800

; CIA Registers
CIA1_PRA        = $dc00      ; Joystick port 2

; SID Registers (Sound Interface Device)
SID_V1_FREQ_LO  = $d400      ; Voice 1 frequency low byte
SID_V1_FREQ_HI  = $d401      ; Voice 1 frequency high byte
SID_V1_CTRL     = $d404      ; Voice 1 control register
SID_V1_AD       = $d405      ; Voice 1 attack/decay
SID_V1_SR       = $d406      ; Voice 1 sustain/release

SID_V2_FREQ_LO  = $d407      ; Voice 2 frequency low byte
SID_V2_FREQ_HI  = $d408      ; Voice 2 frequency high byte
SID_V2_CTRL     = $d40b      ; Voice 2 control register
SID_V2_AD       = $d40c      ; Voice 2 attack/decay
SID_V2_SR       = $d40d      ; Voice 2 sustain/release

SID_V3_FREQ_LO  = $d40e      ; Voice 3 (jingles + dive swoop)
SID_V3_FREQ_HI  = $d40f
SID_V3_PW_LO    = $d410
SID_V3_PW_HI    = $d411
SID_V3_CTRL     = $d412
SID_V3_AD       = $d413
SID_V3_SR       = $d414

SID_FILTER_MODE  = $d418     ; Filter mode/volume

; Zero page (free on a C64 once BASIC/KERNAL IRQ are out of the way)
zp_path         = $f7        ; flight path table pointer (word)
zp_col          = $f9        ; colour RAM pointer (word)
zp_src          = $fb        ; string source (word)
zp_dst          = $fd        ; screen destination (word)

; Game Constants
MAX_ENEMIES     = 32
MAX_SPRITES     = 44            ; Player + 32 enemies + 4 player bullets + 3 enemy bullets + extras
NUM_STARS       = 12

; Virtual sprite slots (stable indices keep the per-frame sort cheap)
VS_PLAYER       = MAX_ENEMIES
VS_PBUL         = VS_PLAYER+1   ; 4 slots
VS_EBUL         = VS_PBUL+4     ; 3 slots
VS_DUAL         = VS_EBUL+3     ; second ship of the dual fighter
VS_CAPT         = VS_DUAL+1     ; captured ship carried by a boss
PLAYER_Y        = 230
SCREEN_LEFT     = 24
SCREEN_RIGHT    = 320           ; Max player X (9-bit), sprite right edge at 344

; Sprite pointers (block = pointer * 64, data starts at $3000)
SPR_PLAYER      = $c0
SPR_PBUL        = $c1
SPR_EBUL        = $c2
SPR_BEE         = $c3           ; +1 = second animation frame
SPR_BFLY        = $c5
SPR_BOSS        = $c7
SPR_EXPL1       = $c9           ; three explosion frames
SPR_PEXP        = $cc           ; four player explosion frames

; Game states
GS_TITLE        = 0
GS_INTRO        = 1
GS_PLAY         = 2
GS_DYING        = 3
GS_GAMEOVER     = 4
GS_CAPTURED     = 5             ; Player is being pulled up by a tractor beam
GS_RESULT       = 6             ; Shots / hits / ratio screen after a stage
GS_READY        = 7             ; "READY" before the ship respawns

; Raster IRQ Constants
IRQ1_LINE       = $fc           ; Sorting interrupt at bottom of screen
IRQ2_LINE       = $2a           ; Display interrupt start (line 42)
IRQ_LEAD        = 16            ; Lines before a sprite group's Y to start loading it

; Print a zero-terminated screen-code string: message, screen address, colour
!macro print .msg, .addr, .col {
    lda #<.msg
    sta zp_src
    lda #>.msg
    sta zp_src+1
    lda #<.addr
    sta zp_dst
    lda #>.addr
    sta zp_dst+1
    lda #.col
    sta txt_col
    jsr print_str
}

!macro setdst .addr {
    lda #<.addr
    sta zp_dst
    lda #>.addr
    sta zp_dst+1
}
