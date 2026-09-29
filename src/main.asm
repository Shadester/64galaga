; ===============================================
; C64 GALAGA CLONE
; ===============================================
; A Galaga-style shooter with raster interrupt sprite multiplexing
; Based on Cadaver's sprite multiplexer technique
;
; Build:  make          (acme)
; Debug:  acme -DAUTOPLAY=1 ...   synthetic joystick input, for headless tests
;         add -DNOFIRE=1 to stop shooting during play (tests player death)
; ===============================================

!cpu 6510

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
zp_col          = $f9        ; colour RAM pointer (word)
zp_src          = $fb        ; string source (word)
zp_dst          = $fd        ; screen destination (word)

; Game Constants
MAX_ENEMIES     = 24
MAX_SPRITES     = 30            ; Player + 24 enemies + 2 player bullets + 3 enemy bullets
NUM_STARS       = 16
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

; Game states
GS_TITLE        = 0
GS_INTRO        = 1
GS_PLAY         = 2
GS_DYING        = 3
GS_GAMEOVER     = 4

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

; ===============================================
; PROGRAM START
; ===============================================

* = $0801                     ; BASIC start address

; BASIC stub: 10 SYS 2064
!byte $0c,$08,$0a,$00,$9e,$20,$32,$30,$36,$34,$00,$00,$00

* = $0810                     ; Program start

!zone init
init:
    jsr setup_colors
    jsr init_sprites
    jsr init_sound
    jsr init_multiplexer
    lda #$a5
    sta rnd
    jsr init_stars
    jsr init_raster
    jsr enter_title

!zone game_loop
game_loop:
    inc frame
    lda frame
    lsr
    lsr
    lsr
    lsr
    and #1
    sta anim                    ; Wing flap toggles every 16 frames
    jsr read_joystick
    jsr update_stars
    jsr snd_tick
    jsr run_state
    jsr update_sprite_data      ; Update sprites for IRQ multiplexer
    jsr wait_for_irq            ; CRITICAL: Wait for IRQ to finish! Paces the loop to 1 frame
    lda game_state
    beq game_loop               ; Title screen has no HUD
    lda frame
    and #3
    bne game_loop               ; HUD digits refresh every 4th frame
    jsr draw_hud
    jmp game_loop

!zone run_state
run_state:
    ldx game_state
    beq .title
    dex
    beq .intro
    dex
    beq .play
    dex
    beq .dying
    jmp st_gameover
.title:
    jmp st_title
.intro:
    jmp st_intro
.play:
    jmp st_play
.dying:
    jmp st_dying

; ===============================================
; GAME STATES
; ===============================================

; --- Title ---
!zone enter_title
enter_title:
    lda #GS_TITLE
    sta game_state
    lda #1
    sta fire_pressed            ; Fire must be released and pressed again
    jsr clear_screen
    +print msg_title, SCREEN_RAM+6*40+15, 1
    +print msg_hi, SCREEN_RAM+9*40+11, 3
    +setdst SCREEN_RAM+9*40+20
    lda hiscore+2
    jsr draw_bcd
    lda hiscore+1
    jsr draw_bcd
    lda hiscore
    jsr draw_bcd
    +print msg_press, SCREEN_RAM+15*40+15, 1
    rts

!zone st_title
st_title:
    lda joystick_state
    and #$10
    bne .rts                    ; Fire not pressed
    lda fire_pressed
    bne .rts
    jmp start_game
.rts:
    rts

; --- New game ---
!zone start_game
start_game:
    jsr clear_screen
    jsr draw_labels
    lda #0
    sta score
    sta score+1
    sta score+2
    sta player_x_msb
    sta invuln
    lda #3
    sta lives
    lda #1
    sta level
    sta diff
    sta fire_pressed            ; Fire held from the title must not shoot
    lda #160
    sta player_x
    lda $d012                   ; Seed RNG from the raster
    ora #1
    sta rnd
    jsr reset_formation
    ; fall through

; --- Stage intro ---
!zone start_stage
start_stage:
    lda #GS_INTRO
    sta game_state
    lda #120
    sta intro_timer
    +print msg_stage, SCREEN_RAM+16*40+16, 1   ; Below the formation
    +setdst SCREEN_RAM+16*40+22
    lda level
    jsr draw_bcd
    lda #jin_stage-jin_data
    jmp play_jingle

!zone st_intro
st_intro:
    dec intro_timer
    bne .rts
    jsr clear_stage_row
    lda #GS_PLAY
    sta game_state
.rts:
    rts

; --- Playing ---
!zone st_play
st_play:
    lda invuln
    beq .no_invuln
    dec invuln
.no_invuln:
    jsr update_player
    jsr update_bullets
    jsr update_formation
    jsr update_enemies
    jsr update_dives
    jsr update_ebullets
    jsr check_collisions
    lda game_state
    cmp #GS_PLAY
    bne .play_done          ; Player was hit this frame
    jmp check_level_complete
.play_done:
    rts

; --- Player exploding ---
!zone st_dying
st_dying:
    jsr update_formation
    jsr update_enemies
    jsr update_ebullets
    lda dying_timer
    beq .done
    dec dying_timer
    rts
.done:
    lda lives
    beq .game_over
    lda #160                    ; Respawn, briefly invulnerable
    sta player_x
    lda #0
    sta player_x_msb
    lda #120
    sta invuln
    lda #GS_PLAY
    sta game_state
    rts
.game_over:
    jmp enter_gameover

; --- Game over ---
!zone enter_gameover
enter_gameover:
    ; New hi-score?
    lda score+2
    cmp hiscore+2
    bcc .no_hi
    bne .new_hi
    lda score+1
    cmp hiscore+1
    bcc .no_hi
    bne .new_hi
    lda score
    cmp hiscore
    bcc .no_hi
    beq .no_hi
.new_hi:
    lda score
    sta hiscore
    lda score+1
    sta hiscore+1
    lda score+2
    sta hiscore+2
.no_hi:
    lda #GS_GAMEOVER
    sta game_state
    lda #90
    sta go_timer
    +print msg_over, SCREEN_RAM+11*40+15, 1
    lda #jin_over-jin_data
    jmp play_jingle

!zone st_gameover
st_gameover:
    lda go_timer
    beq .wait
    dec go_timer
    bne .rts
    lda #1
    sta fire_pressed        ; Held fire must be released first
    +print msg_press, SCREEN_RAM+14*40+15, 1
.rts:
    rts
.wait:
    lda joystick_state
    and #$10
    bne .rts
    lda fire_pressed
    bne .rts
    jmp enter_title

; ===============================================
; SCREEN & COLOR SETUP
; ===============================================

!zone clear_screen
clear_screen:
    ldx #0
    lda #$20
.loop:
    sta SCREEN_RAM,x
    sta SCREEN_RAM+$100,x
    sta SCREEN_RAM+$200,x
    sta SCREEN_RAM+$2e8,x
    inx
    bne .loop
    rts

!zone clear_stage_row
clear_stage_row:
    ldx #39
    lda #$20
.loop:
    sta SCREEN_RAM+16*40,x
    dex
    bpl .loop
    rts

!zone setup_colors
setup_colors:
    lda #0
    sta BG_COLOR
    sta BORDER_COLOR
    ldx #0
    lda #3
.color_loop:
    sta COLOR_RAM,x
    sta COLOR_RAM+$100,x
    sta COLOR_RAM+$200,x
    sta COLOR_RAM+$2e8,x
    inx
    bne .color_loop
    rts

; Print zero-terminated string at zp_src to zp_dst in colour txt_col
!zone print_str
print_str:
    lda zp_dst
    sta zp_col
    lda zp_dst+1
    clc
    adc #>(COLOR_RAM-SCREEN_RAM)
    sta zp_col+1
    ldy #0
.loop:
    lda (zp_src),y
    beq .done
    sta (zp_dst),y
    lda txt_col
    sta (zp_col),y
    iny
    bne .loop
.done:
    rts

; Draw BCD byte A as two digits at zp_dst, then advance zp_dst by 2
!zone draw_bcd
draw_bcd:
    pha
    lsr
    lsr
    lsr
    lsr
    clc
    adc #48
    ldy #0
    sta (zp_dst),y
    pla
    and #$0f
    clc
    adc #48
    iny
    sta (zp_dst),y
    lda zp_dst
    clc
    adc #2
    sta zp_dst
    bcc .done
    inc zp_dst+1
.done:
    rts

!zone draw_labels
draw_labels:
    +print score_text, SCREEN_RAM, 3
    +print hi_text, SCREEN_RAM+27, 3
    +print lives_text, SCREEN_RAM+40, 3
    +print level_text, SCREEN_RAM+80, 3
    rts

!zone draw_hud
draw_hud:
    +setdst SCREEN_RAM+7
    lda score+2
    jsr draw_bcd
    lda score+1
    jsr draw_bcd
    lda score
    jsr draw_bcd

    +setdst SCREEN_RAM+30
    lda hiscore+2
    jsr draw_bcd
    lda hiscore+1
    jsr draw_bcd
    lda hiscore
    jsr draw_bcd

    lda lives
    clc
    adc #48
    sta SCREEN_RAM+40+7

    +setdst SCREEN_RAM+80+7
    lda level
    jmp draw_bcd

; ===============================================
; STARFIELD
; ===============================================
; Stars are '.' characters that scroll down through the free screen rows.
; They only draw on blank cells and only erase their own '.', so text is safe.

!zone init_stars
init_stars:
    ldx #NUM_STARS-1
.loop:
    jsr rand
    and #$3f
    cmp #40
    bcc .col_ok
    sbc #40
.col_ok:
    sta star_col,x
    jsr rand
    and #$1f
    cmp #22
    bcc .row_ok
    sbc #22
.row_ok:
    clc
    adc #3
    sta star_row,x
    jsr rand
    and #3
    clc
    adc #2                      ; 2..5 frames per row step
    sta star_spd,x
    sta star_cnt,x
    dex
    bpl .loop
    rts

; Point zp_dst / zp_col at the screen / colour cell of star X
!zone star_addr
star_addr:
    ldy star_row,x
    lda row_lo,y
    clc
    adc star_col,x
    sta zp_dst
    sta zp_col
    lda row_hi,y
    adc #0
    sta zp_dst+1
    clc
    adc #>(COLOR_RAM-SCREEN_RAM)
    sta zp_col+1
    rts

!zone update_stars
update_stars:
    ldx #NUM_STARS-1
.loop:
    dec star_cnt,x
    bne .next
    lda star_spd,x
    sta star_cnt,x
    jsr star_addr
    ldy #0
    lda (zp_dst),y
    cmp #$2e
    bne .moved
    lda #$20
    sta (zp_dst),y
.moved:
    inc star_row,x
    lda star_row,x
    cmp #25
    bcc .draw
    lda #3
    sta star_row,x
.draw:
    jsr star_addr
    ldy #0
    lda (zp_dst),y
    cmp #$20
    bne .next
    lda #$2e
    sta (zp_dst),y
    ldy star_spd,x
    lda star_clr_tbl,y
    ldy #0
    sta (zp_col),y
.next:
    dex
    bpl .loop
    rts

; 8-bit Galois LFSR, result in A
!zone rand
rand:
    lda rnd
    asl
    bcc .done
    eor #$1d
.done:
    sta rnd
    rts

; ===============================================
; SPRITE INITIALIZATION
; ===============================================

!zone init_sprites
init_sprites:
    ldx #0
.copy:                          ; 12 sprites = 3 pages
    lda sprite_src,x
    sta $3000,x
    lda sprite_src+$100,x
    sta $3100,x
    lda sprite_src+$200,x
    sta $3200,x
    inx
    bne .copy
    lda #$ff
    sta SPRITE_MCOLOR_EN        ; All sprites in multicolor mode
    lda #7                      ; Yellow (shared color 1)
    sta SPRITE_MCOLOR1
    lda #3                      ; Cyan (shared color 2)
    sta SPRITE_MCOLOR2
    rts

; ===============================================
; FORMATION SETUP
; ===============================================

!zone reset_formation
reset_formation:
    lda #0
    sta form_dx
    sta form_ext
    sta enemy_counter
    sta eb_active
    sta eb_active+1
    sta eb_active+2
    sta pbul_active
    sta pbul_active+1
    lda #1
    sta form_dir
    ldy diff
    lda dive_int_tbl,y
    sta dive_timer
    ldx #MAX_ENEMIES-1
.loop:
    lda #1
    sta enemy_state,x
    lda #0
    sta enemy_timer,x
    sta enemy_flag,x
    ldy enemy_type_tbl,x
    lda type_hp,y
    sta enemy_hp,x
    jsr set_slot_pos
    dex
    bpl .loop
    rts

; Put enemy X at its formation slot (X and Y)
!zone set_slot_pos
set_slot_pos:
    lda base_y,x
    sta enemy_y,x
; Put enemy X at its formation slot column (9-bit)
!zone set_slot_x
set_slot_x:
    lda base_x,x
    clc
    adc form_dx
    sta enemy_x,x
    lda form_ext                ; $00 / $ff sign extension of form_dx
    adc #0
    and #1
    sta enemy_x_msb,x
    rts

; ===============================================
; UPDATE SPRITE DATA FOR MULTIPLEXER
; ===============================================
; Copies game state to virtual sprite tables

!zone update_sprite_data
update_sprite_data:
    lda #0
    sta num_sprites             ; Count active sprites
    lda game_state
    beq .skip                   ; Title: no sprites
    cmp #GS_GAMEOVER
    bne .player
.skip:
    jmp .done

.player:
    cmp #GS_DYING
    beq .p_dying
    lda invuln
    and #4
    bne .enemies                ; Blink while invulnerable
    lda #SPR_PLAYER
    ldy #1                      ; White
    jmp .p_add
.p_dying:
    lda dying_timer
    lsr
    lsr
    lsr
    lsr
    beq .enemies                ; Gone for the last 16 frames
    sta temp
    lda #SPR_EXPL1+3
    sec
    sbc temp
    ldy #8                      ; Orange
.p_add:
    sta spr_f
    sty spr_c
    lda player_x
    sta spr_x
    lda player_x_msb
    sta spr_x_msb
    lda player_y
    sta spr_y
    inc num_sprites

.enemies:
    ldx #0
.en_loop:
    lda enemy_state,x
    beq .en_next
    ldy num_sprites
    lda enemy_x,x
    sta spr_x,y
    lda enemy_x_msb,x
    sta spr_x_msb,y
    lda enemy_y,x
    sta spr_y,y
    lda enemy_state,x
    cmp #4
    beq .en_explode
    lda enemy_ptr_tbl,x
    clc
    adc anim
    sta spr_f,y
    lda enemy_hp,x
    cmp #2
    lda enemy_col_tbl,x
    bcs .en_col
    lda enemy_hitcol_tbl,x      ; Damaged boss changes colour
.en_col:
    sta spr_c,y
    jmp .en_added
.en_explode:
    lda enemy_timer,x
    lsr
    lsr
    sta temp
    lda #SPR_EXPL1+2
    sec
    sbc temp
    sta spr_f,y
    lda #8                      ; Orange
    sta spr_c,y
.en_added:
    inc num_sprites
.en_next:
    inx
    cpx #MAX_ENEMIES
    bne .en_loop

    ; Player bullets
    ldx #1
.pb_loop:
    lda pbul_active,x
    beq .pb_next
    ldy num_sprites
    lda pbul_x,x
    sta spr_x,y
    lda pbul_msb,x
    sta spr_x_msb,y
    lda pbul_y,x
    sta spr_y,y
    lda #SPR_PBUL
    sta spr_f,y
    lda #14                     ; Light blue
    sta spr_c,y
    inc num_sprites
.pb_next:
    dex
    bpl .pb_loop

    ; Enemy bullets
    ldx #2
.eb_loop:
    lda eb_active,x
    beq .eb_next
    ldy num_sprites
    lda eb_x,x
    sta spr_x,y
    lda eb_msb,x
    sta spr_x_msb,y
    lda eb_y,x
    sta spr_y,y
    lda #SPR_EBUL
    sta spr_f,y
    lda #10                     ; Light red
    sta spr_c,y
    inc num_sprites
.eb_next:
    dex
    bpl .eb_loop

.done:
    lda #1
    sta spr_update_flag         ; Signal IRQ to sort and display
    rts

; ===============================================
; JOYSTICK INPUT
; ===============================================

!zone read_joystick
read_joystick:
!ifdef AUTOPLAY {
    ; Synthetic input: sweep the screen left/right, fire in bursts
    lda #$ff
    sta joystick_state
    lda frame
    and #$80                ; 128 frames per direction = 256px sweep
    beq .auto_right
    lda joystick_state
    and #$fb
    sta joystick_state
    jmp .auto_fire
.auto_right:
    lda joystick_state
    and #$f7
    sta joystick_state
.auto_fire:
!ifdef NOFIRE {
    lda game_state          ; -DNOFIRE: only fire to leave title / game over
    cmp #GS_PLAY
    beq .auto_done
}
    lda frame
    and #$08
    bne .auto_done
    lda joystick_state
    and #$ef
    sta joystick_state
.auto_done:
} else {
    lda CIA1_PRA
    sta joystick_state
}
    lda joystick_state
    and #$10
    beq .held
    lda #0
    sta fire_pressed            ; Released: next press counts
.held:
    rts

; ===============================================
; PLAYER UPDATE
; ===============================================

!zone update_player
update_player:
    ; Check left
    lda joystick_state
    and #$04
    bne .check_right
    lda player_x_msb
    bne .pl_left            ; X >= 256, always above left limit
    lda player_x
    cmp #SCREEN_LEFT+2         ; Stop at SCREEN_LEFT after the 2px step
    bcc .check_right
.pl_left:
    lda player_x
    sec
    sbc #2
    sta player_x
    bcs .check_right
    dec player_x_msb

.check_right:
    lda joystick_state
    and #$08
    bne .check_fire
    lda player_x_msb
    beq .pl_right           ; X < 256, below right limit
    lda player_x
    cmp #<SCREEN_RIGHT
    bcs .check_fire
.pl_right:
    lda player_x
    clc
    adc #2
    sta player_x
    bcc .check_fire
    inc player_x_msb

.check_fire:
    lda joystick_state
    and #$10
    bne .player_done
    lda fire_pressed
    bne .player_done
    lda #1
    sta fire_pressed
    jmp shoot_bullet
.player_done:
    rts

; ===============================================
; SHOOTING (two shots in flight)
; ===============================================

!zone shoot_bullet
shoot_bullet:
    ldx #0
    lda pbul_active
    beq .use
    inx
    lda pbul_active+1
    bne .none
.use:
    lda #1
    sta pbul_active,x
    lda player_x
    clc
    adc #3                  ; Bullet art sits 3px left of the ship nose
    sta pbul_x,x
    lda player_x_msb
    adc #0
    sta pbul_msb,x
    lda #PLAYER_Y-16
    sta pbul_y,x
    jmp sound_shoot
.none:
    rts

!zone update_bullets
update_bullets:
    ldx #1
.loop:
    lda pbul_active,x
    beq .next
    lda pbul_y,x
    sec
    sbc #4
    sta pbul_y,x
    cmp #20
    bcs .next
    lda #0
    sta pbul_active,x
.next:
    dex
    bpl .loop
    rts

; ===============================================
; FORMATION SWAY
; ===============================================
; The whole formation shifts by form_dx (signed); enemies in formation
; are placed at slot + form_dx each frame.

!zone update_formation
update_formation:
    inc enemy_counter
    lda #10
    sec
    sbc diff                ; Threshold shrinks with difficulty (min 2)
    sta temp
    lda enemy_counter
    cmp temp
    bcc .done

    lda #0
    sta enemy_counter
    lda form_dir
    beq .left
    lda form_dx
    clc
    adc #3
    sta form_dx
    cmp #42
    bne .ext
    lda #0
    sta form_dir
    jmp .ext
.left:
    lda form_dx
    sec
    sbc #3
    sta form_dx
    cmp #$d6                ; -42
    bne .ext
    lda #1
    sta form_dir
.ext:
    lda #0
    ldx form_dx
    bpl .ext_set
    lda #$ff
.ext_set:
    sta form_ext
    ldx #MAX_ENEMIES-1      ; Re-place everything that is in formation
.sync:
    lda enemy_state,x
    cmp #1
    bne .sync_next
    jsr set_slot_pos
.sync_next:
    dex
    bpl .sync
.done:
    rts

; ===============================================
; ENEMY UPDATE
; ===============================================
; enemy_state: 0 dead, 1 in formation, 2 diving, 3 returning, 4 exploding

!zone update_enemies
update_enemies:
    ldx #MAX_ENEMIES-1
.loop:
    lda enemy_state,x
    beq .next
    cmp #2
    bcc .next               ; In formation: placed by update_formation
    beq .dive
    cmp #4
    beq .explode
    jsr return_step
    jmp .next
.dive:
    jsr dive_step
    jmp .next
.explode:
    dec enemy_timer,x
    bne .next
    lda #0
    sta enemy_state,x
.next:
    dex
    bpl .loop
    rts

; Fly back in from the top of the screen to the formation slot
!zone return_step
return_step:
    jsr set_slot_x
    lda enemy_y,x
    clc
    adc #2
    sta enemy_y,x
    cmp base_y,x
    bcc .done
    lda #1
    sta enemy_state,x
.done:
    rts

; One frame of a dive. Phase A (timer > 0): peel off sideways.
; Phase B: swoop down, home in on the player, fire once.
!zone dive_step
dive_step:
    lda enemy_timer,x
    beq .attack
    dec enemy_timer,x
    inc enemy_y,x
    lda enemy_dir,x
    beq .peel_left
    lda enemy_x,x
    clc
    adc #2
    sta enemy_x,x
    bcc .rts
    inc enemy_x_msb,x
    rts
.peel_left:
    lda enemy_x,x
    sec
    sbc #2
    sta enemy_x,x
    bcs .rts
    dec enemy_x_msb,x
.rts:
    rts

.attack:
    lda enemy_y,x
    clc
    adc #2
    sta enemy_y,x
    lda enemy_flag,x
    bne .steer                  ; Already fired
    lda enemy_y,x
    cmp #100
    bcc .steer
    lda #1
    sta enemy_flag,x
    jsr rand
    ldy diff
    and fire_mask_tbl,y
    bne .steer
    jsr spawn_ebullet
.steer:
    lda frame
    and #1
    bne .check_end          ; Steer every other frame
    lda enemy_x_msb,x
    cmp player_x_msb
    bne .cmp_done
    lda enemy_x,x
    cmp player_x
.cmp_done:
    bcs .go_left            ; Enemy right of (or level with) player
    inc enemy_x,x
    bne .check_end
    inc enemy_x_msb,x
    jmp .check_end
.go_left:
    lda enemy_x,x
    bne .dec_lo
    dec enemy_x_msb,x
.dec_lo:
    dec enemy_x,x
.check_end:
    lda enemy_y,x
    cmp #244
    bcc .rts
    lda #3                  ; Off the bottom: re-enter from the top
    sta enemy_state,x
    lda #0
    sta enemy_y,x
    sta enemy_flag,x
    rts

; Start a dive for enemy X
!zone start_dive
start_dive:
    lda #2
    sta enemy_state,x
    lda #20
    sta enemy_timer,x
    lda #0
    sta enemy_flag,x
    lda base_x,x
    cmp #184
    lda #0
    rol                     ; 1 = slot right of centre: peel off to the right
    sta enemy_dir,x
    lda #24
    sta swoop_cnt
    rts

; Every dive_timer frames, send a random formation enemy diving
; (up to max_div_tbl[diff] out of formation at once)
!zone update_dives
update_dives:
    lda dive_timer
    beq .try
    dec dive_timer
    rts
.try:
    ldy diff
    lda dive_int_tbl,y
    sta dive_timer
    lda #0
    sta temp
    ldx #MAX_ENEMIES-1
.count:
    lda enemy_state,x
    cmp #2
    bcc .count_next
    cmp #4
    bcs .count_next
    inc temp                ; diving or returning
.count_next:
    dex
    bpl .count
    lda temp
    cmp max_div_tbl,y
    bcs .rts
    lda #8                  ; Up to 8 random picks
    sta temp
.pick:
    jsr rand
    and #$1f
    cmp #MAX_ENEMIES
    bcs .retry
    tax
    lda enemy_state,x
    cmp #1
    beq .start
.retry:
    dec temp
    bne .pick
.rts:
    rts
.start:
    jmp start_dive

; ===============================================
; ENEMY BULLETS
; ===============================================

; Fire a bullet from enemy X (X preserved), drifting toward the player
!zone spawn_ebullet
spawn_ebullet:
    ldy #0
.find:
    lda eb_active,y
    beq .found
    iny
    cpy #3
    bne .find
    rts
.found:
    lda #1
    sta eb_active,y
    lda enemy_x,x
    sta eb_x,y
    lda enemy_x_msb,x
    sta eb_msb,y
    lda enemy_y,x
    clc
    adc #8
    sta eb_y,y
    lda player_x_msb
    cmp enemy_x_msb,x
    bne .far
    lda player_x
    sec
    sbc enemy_x,x
    bcs .pos
    eor #$ff
    clc
    adc #1
    cmp #16
    bcc .zero
    lda #$ff                ; Drift left
    jmp .store
.pos:
    cmp #16
    bcc .zero
    lda #1                  ; Drift right
    jmp .store
.far:
    lda #1
    bcs .store              ; Player MSB higher: right
    lda #$ff
    jmp .store
.zero:
    lda #0
.store:
    sta eb_dx,y
    rts

!zone update_ebullets
update_ebullets:
    ldx #2
.loop:
    lda eb_active,x
    beq .next
    lda eb_y,x
    clc
    adc #3
    sta eb_y,x
    cmp #250
    bcc .move
    lda #0
    sta eb_active,x
    jmp .next
.move:
    lda frame
    and #1
    bne .next               ; Sideways drift at half speed
    lda eb_dx,x
    beq .next
    bmi .left
    inc eb_x,x
    bne .next
    inc eb_msb,x
    jmp .next
.left:
    lda eb_x,x
    bne .dec_lo
    dec eb_msb,x
.dec_lo:
    dec eb_x,x
.next:
    dex
    bpl .loop
    rts

; ===============================================
; COLLISION DETECTION
; ===============================================

; 9-bit X overlap test
; In:  A = object X low, ov_ah = object X msb, ov_bl/ov_bh = other X
;      hit when 0 <= (a - b + ov_off) < ov_w
; Out: carry clear = hit, carry set = miss. Preserves X and Y.
!zone x_overlap
x_overlap:
    sec
    sbc ov_bl
    sta ov_t
    lda ov_ah
    sbc ov_bh
    sta ov_th
    lda ov_t
    clc
    adc ov_off
    sta ov_t
    lda ov_th
    adc #0
    bne .miss
    lda ov_t
    cmp ov_w
    rts
.miss:
    sec
    rts

!zone check_collisions
check_collisions:
    ; --- Player bullets vs enemies ---
    lda #6                  ; Bullet art centre is 3px left of enemy centre
    sta ov_off
    lda #18                 ; Hit within 9px of the alien's centre
    sta ov_w
    ldy #1
.pb_loop:
    lda pbul_active,y
    beq .pb_next
    ldx #MAX_ENEMIES-1
.pb_enemy:
    lda enemy_state,x
    beq .pbe_next
    cmp #4
    beq .pbe_next           ; Exploding enemies can't be hit
    lda pbul_y,y
    sec
    sbc enemy_y,x
    clc
    adc #8
    cmp #16
    bcs .pbe_next
    lda enemy_x,x
    sta ov_bl
    lda enemy_x_msb,x
    sta ov_bh
    lda pbul_msb,y
    sta ov_ah
    lda pbul_x,y
    jsr x_overlap
    bcs .pbe_next
    lda #0                  ; Hit!
    sta pbul_active,y
    tya
    pha
    jsr hit_enemy
    pla
    tay
    jmp .pb_next
.pbe_next:
    dex
    bpl .pb_enemy
.pb_next:
    dey
    bpl .pb_loop

    lda invuln
    beq .pe_start
    rts                     ; Respawn protection
.pe_start:

    ; --- Diving enemies vs player ---
    lda #8                  ; Ship is 16px wide
    sta ov_off
    lda #16
    sta ov_w
    lda player_x_msb
    sta ov_ah
    ldx #MAX_ENEMIES-1
.pe_loop:
    lda enemy_state,x
    cmp #2
    bne .pe_next
    lda player_y
    sec
    sbc enemy_y,x
    clc
    adc #8
    cmp #16
    bcs .pe_next
    lda enemy_x,x
    sta ov_bl
    lda enemy_x_msb,x
    sta ov_bh
    lda player_x
    jsr x_overlap
    bcs .pe_next
    lda #4                  ; Enemy explodes with the ship
    sta enemy_state,x
    lda #11
    sta enemy_timer,x
    jmp player_hit
.pe_next:
    dex
    bpl .pe_loop

    ; --- Enemy bullets vs player ---
    lda #7
    sta ov_off
    lda #14
    sta ov_w
    ldx #2
.eb_loop:
    lda eb_active,x
    beq .eb_next
    lda eb_y,x
    sec
    sbc player_y
    clc
    adc #3
    cmp #14
    bcs .eb_next
    lda eb_x,x
    sta ov_bl
    lda eb_msb,x
    sta ov_bh
    lda player_x
    jsr x_overlap
    bcs .eb_next
    jmp player_hit
.eb_next:
    dex
    bpl .eb_loop
.done:
    rts

; Player bullet hit enemy X: boss survives one hit, everything else dies
!zone hit_enemy
hit_enemy:
    dec enemy_hp,x
    beq .kill
    jmp sound_shoot         ; Damaged, not dead
.kill:
    stx hit_idx
    ldy enemy_type_tbl,x
    lda enemy_state,x
    cmp #2
    beq .dive_pts
    lda pts_form_mid,y
    tax
    lda pts_form_lo,y
    jmp .add
.dive_pts:
    lda pts_dive_mid,y
    tax
    lda pts_dive_lo,y
.add:
    jsr add_score
    ldx hit_idx
    lda #4
    sta enemy_state,x
    lda #11
    sta enemy_timer,x
    jmp sound_explosion

; Add BCD points to the 6-digit score. In: A = low pair, X = middle pair
!zone add_score
add_score:
    sed
    clc
    adc score
    sta score
    txa
    adc score+1
    sta score+1
    lda score+2
    adc #0
    sta score+2
    cld
    rts

!zone player_hit
player_hit:
    lda #GS_DYING
    sta game_state
    lda #63
    sta dying_timer
    dec lives
    lda #0
    sta eb_active
    sta eb_active+1
    sta eb_active+2
    sta pbul_active
    sta pbul_active+1
    jsr sound_player_hit
    jmp sound_player_die

; ===============================================
; LEVEL PROGRESSION
; ===============================================

; All enemies gone (and none still exploding)? Start the next stage.
!zone check_level_complete
check_level_complete:
    ldx #MAX_ENEMIES-1
.loop:
    lda enemy_state,x
    bne .rts
    dex
    bpl .loop
    jmp next_level
.rts:
    rts

!zone next_level
next_level:
    sed
    lda level
    clc
    adc #1
    sta level
    cld
    lda diff
    cmp #8
    bcs .capped
    inc diff
.capped:
    jsr reset_formation
    jmp start_stage

; ===============================================
; SOUND EFFECTS
; ===============================================

; Initialize SID chip
!zone init_sound
init_sound:
    ; Clear all SID registers first
    ldx #$18
    lda #0
.clear_loop:
    sta $d400,x
    dex
    bpl .clear_loop

    ; Set master volume to max (15) in lower nibble
    lda #$0f
    sta SID_FILTER_MODE

    ; Voice 3: pulse wave for jingles
    lda #$08
    sta SID_V3_PW_HI
    lda #$08                ; Attack=0, Decay=8
    sta SID_V3_AD
    lda #$a5                ; Sustain=10, Release=5
    sta SID_V3_SR
    rts

; Shoot sound effect - quick high beep
!zone sound_shoot
sound_shoot:
    lda #$50
    sta SID_V1_FREQ_HI
    lda #$00
    sta SID_V1_FREQ_LO
    lda #$07                ; Attack=0, Decay=7
    sta SID_V1_AD
    lda #$00                ; Sustain=0, Release=0
    sta SID_V1_SR
    lda #$10                ; Triangle wave, gate off
    sta SID_V1_CTRL
    lda #$11                ; Triangle wave, gate on
    sta SID_V1_CTRL
    rts

; Explosion sound effect - noise burst
!zone sound_explosion
sound_explosion:
    lda #$20
    sta SID_V2_FREQ_HI
    lda #$00
    sta SID_V2_FREQ_LO
    lda #$0A                ; Attack=0, Decay=A
    sta SID_V2_AD
    lda #$00                ; Sustain=0, Release=0
    sta SID_V2_SR
    lda #$80                ; Noise wave, gate off
    sta SID_V2_CTRL
    lda #$81                ; Noise wave, gate on
    sta SID_V2_CTRL
    rts

; Player hit sound effect - lower descending tone
!zone sound_player_hit
sound_player_hit:
    lda #$18
    sta SID_V1_FREQ_HI
    lda #$00
    sta SID_V1_FREQ_LO
    lda #$09                ; Attack=0, Decay=9
    sta SID_V1_AD
    lda #$00                ; Sustain=0, Release=0
    sta SID_V1_SR
    lda #$20                ; Sawtooth wave, gate off
    sta SID_V1_CTRL
    lda #$21                ; Sawtooth wave, gate on
    sta SID_V1_CTRL
    rts

; Player explosion - long low noise rumble
!zone sound_player_die
sound_player_die:
    lda #$0c
    sta SID_V2_FREQ_HI
    lda #$00
    sta SID_V2_FREQ_LO
    lda #$0B                ; Attack=0, Decay=B
    sta SID_V2_AD
    lda #$80
    sta SID_V2_CTRL
    lda #$81
    sta SID_V2_CTRL
    rts

; Start jingle at offset A into jin_data
!zone play_jingle
play_jingle:
    sta jin_pos
    lda #1
    sta jin_on
    lda #0
    sta jin_dur
    rts

; Per-frame voice 3: jingle player, or the dive swoop when silent
!zone snd_tick
snd_tick:
    lda jin_on
    bne .jingle
    lda swoop_cnt
    beq .rts
    dec swoop_cnt
    beq .swoop_end
    asl
    clc
    adc #8
    sta SID_V3_FREQ_HI      ; Falling pitch
    lda #0
    sta SID_V3_FREQ_LO
    lda #$21                ; Sawtooth, gate on
    sta SID_V3_CTRL
.rts:
    rts
.swoop_end:
    lda #$20
    sta SID_V3_CTRL
    rts
.jingle:
    lda jin_dur
    beq .next_note
    dec jin_dur
    rts
.next_note:
    ldx jin_pos
    lda jin_data+2,x        ; Duration, 0 ends the tune
    beq .jin_end
    sta jin_dur
    lda jin_data,x
    sta SID_V3_FREQ_LO
    lda jin_data+1,x
    sta SID_V3_FREQ_HI
    inx
    inx
    inx
    stx jin_pos
    lda #$40                ; Pulse wave, gate off
    sta SID_V3_CTRL
    lda #$41                ; Pulse wave, gate on
    sta SID_V3_CTRL
    rts
.jin_end:
    lda #0
    sta jin_on
    lda #$40
    sta SID_V3_CTRL
    rts

; ===============================================
; WAIT FOR IRQ
; ===============================================

; Wait for IRQ to finish processing sprites
!zone wait_for_irq
wait_for_irq:
.wait_loop:
    lda spr_update_flag
    bne .wait_loop
    rts

; ===============================================
; SPRITE MULTIPLEXER SYSTEM
; ===============================================
; Raster interrupt-based multiplexer

; Initialize the multiplexer
!zone init_multiplexer
init_multiplexer:
    lda #0
    sta sorted_sprites
    sta spr_update_flag

    ; Init order table with 0,1,2,3... order
    ldx #MAX_SPRITES-1
.init_order:
    txa
    sta sort_order,x
    dex
    bpl .init_order
    rts

; Initialize raster interrupt system
!zone init_raster
init_raster:
    sei
    lda #<irq1
    sta $0314
    lda #>irq1
    sta $0315
    lda #$7f                ; CIA interrupt off
    sta $dc0d
    lda #$01                ; Raster interrupt on
    sta $d01a
    lda #27                 ; High bit of IRQ position = 0
    sta $d011
    lda #IRQ1_LINE          ; Sorting interrupt line
    sta $d012
    lda $dc0d               ; Acknowledge IRQ
    cli
    rts

; IRQ1: Sorting interrupt (runs at bottom of screen)
!zone irq1
irq1:
    cld                     ; IRQ may hit inside score sed/cld window
    dec $d019               ; Acknowledge raster interrupt

    ; Move all sprites to bottom to prevent glitches
    lda #$ff
    sta $d001
    sta $d003
    sta $d005
    sta $d007
    sta $d009
    sta $d00b
    sta $d00d
    sta $d00f

    ; Check if new sprites need sorting
    lda spr_update_flag
    beq .check_display

    lda #0
    sta spr_update_flag
    lda num_sprites
    sta sorted_sprites
    beq .check_display      ; If zero, check if we have sprites to display

    ; Sort sprites by Y coordinate
    jsr sort_sprites

.check_display:
    ; Always display sorted sprites each frame
    ldx sorted_sprites
    beq .no_sprites_at_all   ; If zero sprites, skip display
    cpx #9
    bcc .not_more_than_8
    ldx #8
.not_more_than_8:
    lda d015_table,x
    sta $d015

    ; Set up display interrupt
    lda #0
    sta spr_irq_counter
    lda #<irq2
    sta $0314
    lda #>irq2
    sta $0315
    lda #IRQ2_LINE          ; Start display interrupt
    sta $d012
    jmp $ea81               ; Return from IRQ

.no_sprites_at_all:
    lda #0
    sta $d015               ; Disable all sprites
    jmp $ea81               ; Return from IRQ

; Sort sprites by Y coordinate
!zone sort_sprites
sort_sprites:
    ; Clear unused sprite Y positions
    ldx #MAX_SPRITES
    dex
    cpx sorted_sprites
    bcc sort_clear_done
    lda #$ff
!zone sort_clear_loop
sort_clear_loop:
    sta spr_y,x
    dex
    cpx sorted_sprites
    bcs sort_clear_loop

!zone sort_clear_done
sort_clear_done:
    ; Insertion sort on order table
    ldx #0
!zone sort_main_loop
sort_main_loop:
    ldy sort_order+1,x
    lda spr_y,y
    ldy sort_order,x
    cmp spr_y,y
    bcs sort_skip_swap

    ; Swap needed - store X for later reload
    stx sort_temp_x
!zone sort_swap_loop
sort_swap_loop:
    lda sort_order+1,x
    pha
    lda sort_order,x
    sta sort_order+1,x
    pla
    sta sort_order,x
    cpx #0
    beq sort_reload_x
    dex
    ldy sort_order+1,x
    lda spr_y,y
    ldy sort_order,x
    cmp spr_y,y
    bcc sort_swap_loop

!zone sort_reload_x
sort_reload_x:
    ldx sort_temp_x
!zone sort_skip_swap
sort_skip_swap:
    inx
    cpx #MAX_SPRITES-1
    bcc sort_main_loop

    ; Copy sorted data
    ldx sorted_sprites
    lda #$ff
    sta sort_spr_y,x        ; End marker

    ldx #0
!zone sort_copy_loop
sort_copy_loop:
    ldy sort_order,x
    lda spr_y,y
    sta sort_spr_y,x
    lda spr_x,y
    sta sort_spr_x,x
    lda spr_x_msb,y
    sta sort_spr_x_msb,x    ; Copy MSB
    lda spr_f,y
    sta sort_spr_f,x
    lda spr_c,y
    sta sort_spr_c,x
    inx
    cpx sorted_sprites
    bcc sort_copy_loop

    ; Per sorted sprite: running $d010 / $d01c values (the player ship is the
    ; only hires sprite) and the raster line its hardware sprite is free at.
!zone sort_shadow
    lda #0
    sta sh_msb
    lda #$ff
    sta sh_mc
    ldx #0
.loop:
    txa
    and #7
    tay
    lda d015_msb_tbl,y
    sta sh_mask
    eor #$ff
    and sh_msb
    ldy sort_spr_x_msb,x
    beq .msb0
    ora sh_mask
.msb0:
    sta sh_msb
    sta sort_d010,x
    lda sh_mask
    ldy sort_spr_f,x
    cpy #SPR_PLAYER
    beq .hires
    ora sh_mc
    jmp .mc_st
.hires:
    eor #$ff
    and sh_mc
.mc_st:
    sta sh_mc
    sta sort_d01c,x
    lda #0
    cpx #8
    bcc .free_set
    ldy sort_spr_f-8,x
    lda sort_spr_y-8,x
    clc
    adc lastrow_tbl-SPR_PLAYER,y
    bcs .none
    cmp #$f0                    ; Near the bottom border: never wait across the raster wrap
    bcc .free_set
.none:
    lda #0
.free_set:
    sta sort_free,x
    inx
    cpx sorted_sprites
    bcc .loop
    rts

; IRQ2: Display interrupt (runs multiple times per frame)
!zone irq2
irq2:
    cld
    dec $d019               ; Acknowledge raster interrupt

!zone irq2_direct
irq2_direct:
    ldy spr_irq_counter     ; Get sprite index
    lda sort_spr_y,y        ; Get Y of first sprite to display
    clc
    adc #$10                ; 16 lines down is endpoint
    bcc irq2_not_over
    lda #$ff                ; Cap at $ff
!zone irq2_not_over
irq2_not_over:
    sta temp_var

    ; Display sprites until we reach endpoint
!zone irq2_sprite_loop
irq2_sprite_loop:
    lda sort_spr_y,y
    cmp temp_var
    bcc .load
    jmp irq2_end_sprites
.load:
.wait:                          ; Wait until the hardware sprite's previous user
    lda sort_free,y             ; has drawn its last art row (0 = no wait)
    cmp $d012
    bcs .wait
    lda sort_spr_y,y
    cmp $d012                   ; Y line already passed (IRQ ran late)?
    bcs .on_time
    lda $d012                   ; Draw a few lines low instead of skipping the sprite
    clc
    adc #2
.on_time:
    ldx phys_spr_tbl_2,y        ; Physical sprite * 2
    sta $d001,x                 ; Y
    lda sort_spr_x,y
    sta $d000,x                 ; X low
    lda sort_d010,y             ; X high bits and multicolor bits are
    sta $d010                   ; precomputed per sprite by sort_sprites
    lda sort_d01c,y
    sta SPRITE_MCOLOR_EN
    ldx phys_spr_tbl_1,y        ; Physical sprite * 1
    lda sort_spr_f,y
    sta SPRITE_PTR,x
    lda sort_spr_c,y
    sta SPRITE_COLORS,x
    iny
    jmp irq2_sprite_loop        ; Ends via the sorted list's $ff marker

!zone irq2_end_sprites
irq2_end_sprites:
    cmp #$ff                ; Was it the end marker?
    beq irq2_last_sprite

    ; More sprites to come, set up next interrupt
    sty spr_irq_counter
    sec
    sbc #IRQ_LEAD           ; Start early: the loop waits for sprites to free up
    bcc .go_direct          ; Underflow: too close to the top
    ldx $d012
    inx
    inx                     ; Margin: raster may move before the write
    stx sort_temp_x
    cmp sort_temp_x
    bcs .set_line
.go_direct:
    jmp irq2_direct         ; Already late? Go direct
.set_line:
    sta $d012
    jmp $ea81

!zone irq2_last_sprite
irq2_last_sprite:
    ; Last sprite displayed, return to sorting IRQ
    lda #<irq1
    sta $0314
    lda #>irq1
    sta $0315
    lda #IRQ1_LINE
    sta $d012
    jmp $ea81


; ===============================================
; DATA SECTION
; ===============================================

game_state:            !byte GS_TITLE
frame:                 !byte 0
anim:                  !byte 0
rnd:                   !byte $a5
joystick_state:        !byte 0
fire_pressed:          !byte 0
temp:                  !byte 0
hit_idx:               !byte 0
txt_col:               !byte 1

; Overlap test parameters
ov_ah:                 !byte 0
ov_bl:                 !byte 0
ov_bh:                 !byte 0
ov_off:                !byte 0
ov_w:                  !byte 0
ov_t:                  !byte 0
ov_th:                 !byte 0

; Timers
intro_timer:           !byte 0
dying_timer:           !byte 0
go_timer:              !byte 0
invuln:                !byte 0
dive_timer:            !byte 0
swoop_cnt:             !byte 0

; Jingle player
jin_on:                !byte 0
jin_pos:               !byte 0
jin_dur:               !byte 0

; Player
player_x:              !byte 160
player_x_msb:          !byte 0
player_y:              !byte PLAYER_Y

; Formation (form_dx is signed, form_ext its $00/$ff sign extension)
form_dx:               !byte 0
form_ext:              !byte 0
form_dir:              !byte 1
enemy_counter:         !byte 0

enemy_x:        !fill MAX_ENEMIES, 0
enemy_x_msb:    !fill MAX_ENEMIES, 0    ; 9th bit for X coordinates (0 or 1)
enemy_y:        !fill MAX_ENEMIES, 0
enemy_state:    !fill MAX_ENEMIES, 0
enemy_timer:    !fill MAX_ENEMIES, 0    ; dive peel-off / explosion frames left
enemy_hp:       !fill MAX_ENEMIES, 0
enemy_dir:      !fill MAX_ENEMIES, 0    ; dive side: 0 left, 1 right
enemy_flag:     !fill MAX_ENEMIES, 0    ; 1 = has fired this dive

pbul_x:         !fill 2, 0
pbul_msb:       !fill 2, 0
pbul_y:         !fill 2, 0
pbul_active:    !fill 2, 0

eb_x:           !fill 3, 0
eb_msb:         !fill 3, 0
eb_y:           !fill 3, 0
eb_dx:          !fill 3, 0              ; -1, 0, +1 drift per 2 frames
eb_active:      !fill 3, 0

score:          !byte 0, 0, 0           ; BCD, low pair first
hiscore:        !byte 0, 0, 0
lives:          !byte 3
level:          !byte 1                 ; BCD
diff:           !byte 1                 ; Difficulty 1..8

star_col:       !fill NUM_STARS, 0
star_row:       !fill NUM_STARS, 0
star_spd:       !fill NUM_STARS, 0
star_cnt:       !fill NUM_STARS, 0

score_text:     !scr "score:", 0
hi_text:        !scr "hi:", 0
lives_text:     !scr "lives:", 0
level_text:     !scr "level:", 0
msg_over:       !scr "game over", 0
msg_stage:      !scr "stage   ", 0
msg_title:      !scr "galaga 64", 0
msg_hi:         !scr "hi-score", 0
msg_press:      !scr "press fire", 0

row_lo:  !byte 0,40,80,120,160,200,240,24
    !byte 64,104,144,184,224,8,48,88
    !byte 128,168,208,248,32,72,112,152
    !byte 192

row_hi:  !byte 4,4,4,4,4,4,4,5
    !byte 5,5,5,5,5,6,6,6
    !byte 6,6,6,6,7,7,7,7
    !byte 7

base_x: ; formation slot X (left edge), 4 rows of 6
    !byte 119,145,171,197,223,249,119,145,171,197,223,249
    !byte 119,145,171,197,223,249,119,145,171,197,223,249

base_y: ; formation slot Y (clear of the HUD rows)
    !byte 76,76,76,76,76,76,104,104,104,104,104,104
    !byte 132,132,132,132,132,132,160,160,160,160,160,160

enemy_type_tbl: ; 0=boss 1=butterfly 2=bee
    !byte 0,0,0,0,0,0,1,1,1,1,1,1
    !byte 2,2,2,2,2,2,2,2,2,2,2,2

enemy_ptr_tbl: ; sprite pointer, frame A
    !byte 199,199,199,199,199,199,197,197,197,197,197,197
    !byte 195,195,195,195,195,195,195,195,195,195,195,195

enemy_col_tbl: ; sprite colour
    !byte 5,5,5,5,5,5,2,2,2,2,2,2
    !byte 14,14,14,14,14,14,14,14,14,14,14,14

enemy_hitcol_tbl: ; colour once damaged
    !byte 4,4,4,4,4,4,2,2,2,2,2,2
    !byte 14,14,14,14,14,14,14,14,14,14,14,14

; Per enemy type: 0 boss, 1 butterfly, 2 bee
type_hp:        !byte 2, 1, 1
pts_form_lo:    !byte $50, $80, $50     ; 150 / 80 / 50
pts_form_mid:   !byte $01, $00, $00
pts_dive_lo:    !byte $00, $60, $00     ; 400 / 160 / 100
pts_dive_mid:   !byte $04, $01, $01

; Difficulty tables, index 1..8
dive_int_tbl:   !byte 0, 130, 115, 100, 85, 70, 58, 48, 40
max_div_tbl:    !byte 0, 1, 1, 2, 2, 3, 3, 4, 4
fire_mask_tbl:  !byte 0, 1, 1, 0, 0, 0, 0, 0, 0     ; fire when rand & mask == 0

; Last used art row per sprite pointer ($c0..$cb): a hardware sprite can be
; reused once the raster is past y + lastrow
lastrow_tbl:    !byte 13, 8, 7, 12, 12, 9, 9, 9, 9, 6, 7, 8

star_clr_tbl:   !byte 0, 0, 1, 15, 12, 11           ; by speed: fast = bright

jin_data:
jin_stage:
    !byte $13,$1a,7   ; G4
    !byte $ce,$22,7   ; C5
    !byte $da,$2b,7   ; E5
    !byte $26,$34,7   ; G5
    !byte $9c,$45,30   ; C6
    !byte 0,0,0             ; end
jin_over:
    !byte $ce,$22,12   ; C5
    !byte $45,$1d,12   ; A4
    !byte $3b,$17,12   ; F4
    !byte $67,$11,40   ; C4
    !byte 0,0,0             ; end

; ===============================================
; MULTIPLEXER DATA TABLES
; ===============================================

; Multiplexer control variables
num_sprites:        !byte 0
spr_update_flag:    !byte 0
sorted_sprites:     !byte 0
spr_irq_counter:    !byte 0
temp_var:           !byte 0
sort_temp_x:        !byte 0

; Virtual sprite tables (unsorted)
spr_x:              !fill MAX_SPRITES, 0
spr_x_msb:          !fill MAX_SPRITES, 0    ; MSB for X coordinates
spr_y:              !fill MAX_SPRITES, 0
spr_f:              !fill MAX_SPRITES, 0    ; Frame/pointer
spr_c:              !fill MAX_SPRITES, 0    ; Color

; Sort order table
sort_order:         !fill MAX_SPRITES, 0

; Sorted sprite tables
sort_spr_x:         !fill MAX_SPRITES, 0
sort_spr_x_msb:     !fill MAX_SPRITES, 0    ; MSB for sorted X
sort_spr_y:         !fill MAX_SPRITES+1, 0  ; +1 for $ff end marker
sort_spr_f:         !fill MAX_SPRITES, 0
sort_spr_c:         !fill MAX_SPRITES, 0
sort_d010:          !fill MAX_SPRITES, 0    ; $d010 value after loading this sprite
sort_d01c:          !fill MAX_SPRITES, 0    ; $d01c value after loading this sprite
sort_free:          !fill MAX_SPRITES, 0    ; raster line the hardware sprite frees up (0 = now)
sh_msb:             !byte 0
sh_mc:              !byte 0
sh_mask:            !byte 0

; Sprite enable table for $d015
d015_table:         !byte %00000000
                    !byte %00000001
                    !byte %00000011
                    !byte %00000111
                    !byte %00001111
                    !byte %00011111
                    !byte %00111111
                    !byte %01111111
                    !byte %11111111

; MSB bit masks for $d010 (one bit per sprite)
d015_msb_tbl:       !byte %00000001  ; Sprite 0
                    !byte %00000010  ; Sprite 1
                    !byte %00000100  ; Sprite 2
                    !byte %00001000  ; Sprite 3
                    !byte %00010000  ; Sprite 4
                    !byte %00100000  ; Sprite 5
                    !byte %01000000  ; Sprite 6
                    !byte %10000000  ; Sprite 7

; Physical sprite mapping tables
phys_spr_tbl_1:     !byte 0,1,2,3,4,5,6,7
                    !byte 0,1,2,3,4,5,6,7
                    !byte 0,1,2,3,4,5,6,7
                    !byte 0,1,2,3,4,5,6,7

phys_spr_tbl_2:     !byte 0,2,4,6,8,10,12,14
                    !byte 0,2,4,6,8,10,12,14
                    !byte 0,2,4,6,8,10,12,14
                    !byte 0,2,4,6,8,10,12,14

; ===============================================
; SPRITE DATA (copied to $3000 at startup: pointer $c0 = $3000)
; ===============================================
; 12 sprites of 64 bytes, in pointer order $c0..$cb

sprite_src:

player_sprite:
    ; Hires player fighter (single colour, 1 bit per pixel), 16px wide
    !byte %00000000, %00000000, %00000000   ; ........................
    !byte %00000000, %00011000, %00000000   ; ...........##...........
    !byte %00000000, %00011000, %00000000   ; ...........##...........
    !byte %00000000, %00011000, %00000000   ; ...........##...........
    !byte %00000000, %00111100, %00000000   ; ..........####..........
    !byte %00000000, %00111100, %00000000   ; ..........####..........
    !byte %00000000, %00111100, %00000000   ; ..........####..........
    !byte %00000000, %01111110, %00000000   ; .........######.........
    !byte %00001100, %01111110, %00110000   ; ....##...######...##....
    !byte %00001100, %11111111, %00110000   ; ....##..########..##....
    !byte %00001111, %11111111, %11110000   ; ....################....
    !byte %00001111, %11111111, %11110000   ; ....################....
    !byte %00001111, %00111100, %11110000   ; ....####..####..####....
    !byte %00001100, %00111100, %00110000   ; ....##....####....##....
    !byte %00000000, %00000000, %00000000   ; ........................
    !byte %00000000, %00000000, %00000000   ; ........................
    !byte %00000000, %00000000, %00000000   ; ........................
    !byte %00000000, %00000000, %00000000   ; ........................
    !byte %00000000, %00000000, %00000000   ; ........................
    !byte %00000000, %00000000, %00000000   ; ........................
    !byte %00000000, %00000000, %00000000   ; ........................
    !byte %00000000                         ; Padding byte to make 64 bytes

bullet_sprite:
    ; Multicolor bullet - simple energy projectile
    ; 00=transparent, 01=yellow, 10=light blue, 11=cyan
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %10000000, %00000000   ; Tip
    !byte %00000000, %10000000, %00000000
    !byte %00000000, %11000000, %00000000   ; Bright center (cyan)
    !byte %00000000, %11000000, %00000000
    !byte %00000000, %10000000, %00000000
    !byte %00000000, %10000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000                         ; Padding byte to make 64 bytes

ebullet_sprite:
    ; Enemy bullet
    ; 00=transparent, 01=yellow, 10=own colour, 11=cyan
    !byte %00000000, %00010100, %00000000   ; .....aa.....
    !byte %00000000, %00101000, %00000000   ; .....bb.....
    !byte %00000000, %00101000, %00000000   ; .....bb.....
    !byte %00000000, %00101000, %00000000   ; .....bb.....
    !byte %00000000, %00101000, %00000000   ; .....bb.....
    !byte %00000000, %00101000, %00000000   ; .....bb.....
    !byte %00000000, %00101000, %00000000   ; .....bb.....
    !byte %00000000, %00010100, %00000000   ; .....aa.....
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000                         ; Padding byte to make 64 bytes

bee_a_sprite:
    ; Bee, wings up
    ; 00=transparent, 01=yellow, 10=own colour, 11=cyan
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000001, %00000000, %01000000   ; ...a....a...
    !byte %00000000, %01000001, %00000000   ; ....a..a....
    !byte %00000000, %10101010, %00000000   ; ....bbbb....
    !byte %00000010, %10101010, %10000000   ; ...bbbbbb...
    !byte %00001010, %11101011, %10100000   ; ..bbcbbcbb..
    !byte %00101010, %10101010, %10101000   ; .bbbbbbbbbb.
    !byte %10101000, %10101010, %00101010   ; bbb.bbbb.bbb
    !byte %10100000, %10101010, %00001010   ; bb..bbbb..bb
    !byte %10000000, %10101010, %00000010   ; b...bbbb...b
    !byte %00000000, %10101010, %00000000   ; ....bbbb....
    !byte %00000000, %00101000, %00000000   ; .....bb.....
    !byte %00000000, %01000001, %00000000   ; ....a..a....
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000                         ; Padding byte to make 64 bytes

bee_b_sprite:
    ; Bee, wings down
    ; 00=transparent, 01=yellow, 10=own colour, 11=cyan
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000001, %00000000, %01000000   ; ...a....a...
    !byte %00000000, %01000001, %00000000   ; ....a..a....
    !byte %00000000, %10101010, %00000000   ; ....bbbb....
    !byte %00000010, %10101010, %10000000   ; ...bbbbbb...
    !byte %00001010, %11101011, %10100000   ; ..bbcbbcbb..
    !byte %00101010, %10101010, %10101000   ; .bbbbbbbbbb.
    !byte %00101000, %10101010, %00101000   ; .bb.bbbb.bb.
    !byte %10000000, %10101010, %00000010   ; b...bbbb...b
    !byte %10100000, %10101010, %00001010   ; bb..bbbb..bb
    !byte %10101000, %10101010, %00101010   ; bbb.bbbb.bbb
    !byte %00000000, %00101000, %00000000   ; .....bb.....
    !byte %00000000, %01000001, %00000000   ; ....a..a....
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000                         ; Padding byte to make 64 bytes

bfly_a_sprite:
    ; Butterfly, wings open
    ; 00=transparent, 01=yellow, 10=own colour, 11=cyan
    !byte %10000001, %00000000, %01000010   ; b..a....a..b
    !byte %10100001, %00000000, %01001010   ; bb.a....a.bb
    !byte %10101000, %10101010, %00101010   ; bbb.bbbb.bbb
    !byte %10101010, %10111110, %10101010   ; bbbbbccbbbbb
    !byte %10101010, %10111110, %10101010   ; bbbbbccbbbbb
    !byte %10101010, %10101010, %10101010   ; bbbbbbbbbbbb
    !byte %00101010, %00101000, %10101000   ; .bbb.bb.bbb.
    !byte %00001010, %00101000, %10100000   ; ..bb.bb.bb..
    !byte %00000010, %00101000, %10000000   ; ...b.bb.b...
    !byte %00000000, %00101000, %00000000   ; .....bb.....
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000                         ; Padding byte to make 64 bytes

bfly_b_sprite:
    ; Butterfly, wings closed
    ; 00=transparent, 01=yellow, 10=own colour, 11=cyan
    !byte %00000000, %01000001, %00000000   ; ....a..a....
    !byte %00000000, %01000001, %00000000   ; ....a..a....
    !byte %00000010, %10101010, %10000000   ; ...bbbbbb...
    !byte %00001010, %10111110, %10100000   ; ..bbbccbbb..
    !byte %00001010, %10111110, %10100000   ; ..bbbccbbb..
    !byte %00000010, %10101010, %10000000   ; ...bbbbbb...
    !byte %00000000, %10000010, %00000000   ; ....b..b....
    !byte %00000000, %10000010, %00000000   ; ....b..b....
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000                         ; Padding byte to make 64 bytes

boss_a_sprite:
    ; Boss, frame A
    ; 00=transparent, 01=yellow, 10=own colour, 11=cyan
    !byte %00001100, %00000000, %00110000   ; ..c......c..
    !byte %00001111, %00000000, %11110000   ; ..cc....cc..
    !byte %00000011, %11111111, %11000000   ; ...cccccc...
    !byte %00001010, %10101010, %10100000   ; ..bbbbbbbb..
    !byte %00101001, %10101010, %01101000   ; .bbabbbbabb.
    !byte %10101010, %10101010, %10101010   ; bbbbbbbbbbbb
    !byte %10100010, %10101010, %10001010   ; bb.bbbbbb.bb
    !byte %10000010, %10101010, %10000010   ; b..bbbbbb..b
    !byte %00000010, %10000010, %10000000   ; ...bb..bb...
    !byte %00000010, %10000010, %10000000   ; ...bb..bb...
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000                         ; Padding byte to make 64 bytes

boss_b_sprite:
    ; Boss, frame B
    ; 00=transparent, 01=yellow, 10=own colour, 11=cyan
    !byte %00001100, %00000000, %00110000   ; ..c......c..
    !byte %00001111, %00000000, %11110000   ; ..cc....cc..
    !byte %00000011, %11111111, %11000000   ; ...cccccc...
    !byte %00001010, %10101010, %10100000   ; ..bbbbbbbb..
    !byte %00101001, %10101010, %01101000   ; .bbabbbbabb.
    !byte %10101010, %10101010, %10101010   ; bbbbbbbbbbbb
    !byte %00101010, %10101010, %10101000   ; .bbbbbbbbbb.
    !byte %00001010, %10101010, %10100000   ; ..bbbbbbbb..
    !byte %00000010, %10000010, %10000000   ; ...bb..bb...
    !byte %00001010, %00000000, %10100000   ; ..bb....bb..
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000                         ; Padding byte to make 64 bytes

expl1_sprite:
    ; Explosion 1
    ; 00=transparent, 01=yellow, 10=own colour, 11=cyan
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00010100, %00000000   ; .....aa.....
    !byte %00000000, %01101001, %00000000   ; ....abba....
    !byte %00000000, %01101001, %00000000   ; ....abba....
    !byte %00000000, %00010100, %00000000   ; .....aa.....
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000                         ; Padding byte to make 64 bytes

expl2_sprite:
    ; Explosion 2
    ; 00=transparent, 01=yellow, 10=own colour, 11=cyan
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %01000001, %00000000   ; ....a..a....
    !byte %00000100, %00101000, %00010000   ; ..a..bb..a..
    !byte %00000010, %10010110, %10000000   ; ...bbaabb...
    !byte %00010010, %01111101, %10000100   ; .a.baccab.a.
    !byte %00000010, %10010110, %10000000   ; ...bbaabb...
    !byte %00000100, %00101000, %00010000   ; ..a..bb..a..
    !byte %00000000, %01000001, %00000000   ; ....a..a....
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000                         ; Padding byte to make 64 bytes

expl3_sprite:
    ; Explosion 3
    ; 00=transparent, 01=yellow, 10=own colour, 11=cyan
    !byte %00000100, %00000000, %00010000   ; ..a......a..
    !byte %00000000, %01000001, %00000000   ; ....a..a....
    !byte %00010000, %00000000, %00000100   ; .a........a.
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %01000000, %00010000, %00010000   ; a....a...a..
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00010000, %00000000, %00000100   ; .a........a.
    !byte %00000000, %01000001, %00000000   ; ....a..a....
    !byte %00000100, %00000000, %00010000   ; ..a......a..
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000, %00000000, %00000000   ; ............
    !byte %00000000                         ; Padding byte to make 64 bytes

!if * > $3000 {
    !error "Code and sprite data have grown into the sprite area at $3000"
}
