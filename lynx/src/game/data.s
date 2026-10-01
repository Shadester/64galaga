; Variables and tables
; ===============================================
; DATA SECTION
; ===============================================

dual:                  .byte 0         ; 1 = dual fighter
cap_state:             .byte 0
cap_boss:              .byte 0
beam_len:              .byte 0         ; rows of beam drawn
beam_timer:            .byte 0
cap_x:                 .byte 0         ; rescued ship position
cap_msb:               .byte 0
cap_y:                 .byte 0
dying_quiet:           .byte 0         ; 1 = respawn delay without explosion
bd_chr:                .byte 0
bd_col:                .byte 0
bd_row0:               .byte 0
bd_r:                  .byte 0
bd_hw:                 .byte 0
bd_c0:                 .byte 0
bd_n:                  .byte 0
rs_tx:                 .byte 0
rs_th:                 .byte 0
cur_ship:              .byte 0
ship_xl:               .byte 0
ship_xh:               .byte 0
game_state:            .byte GS_TITLE
frame:                 .byte 0
anim:                  .byte 0
joystick_state:        .byte 0
fire_pressed:          .byte 0
temp:                  .byte 0
hit_idx:               .byte 0
txt_col:               .byte 1

; Overlap test parameters
ov_ah:                 .byte 0
ov_bl:                 .byte 0
ov_bh:                 .byte 0
ov_off:                .byte 0
ov_w:                  .byte 0
ov_t:                  .byte 0
ov_th:                 .byte 0
ov_by:                 .byte 0

; Timers
intro_timer:           .byte 0
dying_timer:           .byte 0
go_timer:              .byte 0
invuln:                .byte 0
dive_timer:            .byte 0
swoop_cnt:             .byte 0

; Jingle player
jin_on:                .byte 0
jin_pos:               .byte 0
jin_dur:               .byte 0

; Player
player_x:              .byte 160
player_x_msb:          .byte 0
player_y:              .byte PLAYER_Y

; Formation (form_dx is signed, form_ext its $00/$ff sign extension)
form_dx:               .byte 0
form_ext:              .byte 0
form_dir:              .byte 1
enemy_counter:         .byte 0

enemy_state:    .res MAX_ENEMIES
enemy_timer:    .res MAX_ENEMIES; dive peel-off / explosion frames left
enemy_hp:       .res MAX_ENEMIES
enemy_dir:      .res MAX_ENEMIES; dive side: 0 left, 1 right
enemy_idx:      .res MAX_ENEMIES; flight path step
enemy_path:     .res MAX_ENEMIES; flight path (bit 7 = mirrored)
enemy_ptr:      .res MAX_ENEMIES; sprite pointer, frame A
enemy_esc:      .res MAX_ENEMIES; boss index + 1 for an escort of that boss
enemy_flag:     .res MAX_ENEMIES; 1 = has fired this dive

pbul_x:         .res 4
pbul_msb:       .res 4
pbul_y:         .res 4
pbul_active:    .res 4

eb_x:           .res 3
eb_msb:         .res 3
eb_y:           .res 3
eb_dx:          .res 3; -1, 0, +1 drift per 2 frames
eb_active:      .res 3

score:          .byte 0, 0, 0           ; BCD, low pair first
hiscore:        .byte 0, 0, 0
lives:          .byte 3
next_bonus:     .byte 2                 ; score+2 (BCD, x10000) of the next bonus ship
level:          .byte 1                 ; BCD
diff:           .byte 1                 ; Difficulty 1..8

esc_boss:              .byte 0
esc_t:                 .byte 0
esc_cmp:               .byte 0
esc_cnt:               .byte 0
esc_slot:              .byte 0
esc_pts_mid:           .byte $04, $08, $16   ; boss dive points (x100) with 0/1/2 escorts
stage:                 .byte 1         ; Stage number (binary); every 4th is a challenge stage
in_chal:               .byte 0         ; 1 = current stage is a challenge stage
chal_mid:              .byte 0         ; BCD hundreds per hit in challenge stages
ch_hits:               .byte 0
step_dx:               .byte 0
path_id:               .byte 0
pe_min:                .byte 0         ; Lowest enemy checked against the ship this frame
add_hi:                .byte 0         ; extra ten-thousands for add_score
shots:                 .byte 0, 0      ; Bullets fired / enemies hit this stage
hits:                  .byte 0, 0
res_timer:             .byte 0
res_lo:                .byte 0
res_hi:                .byte 0
res_val:               .byte 0
calc_lo:               .byte 0
calc_hi:               .byte 0
n_lo:                  .byte 0
n_hi:                  .byte 0
n_dig:                 .byte 0
msg_nhits:      .asciiz "NUMBER OF HITS"
msg_perfect:    .asciiz "PERFECT!"
msg_bonus:      .asciiz "BONUS 10000"
msg_chal:       .asciiz "CHALLENGING STAGE"
msg_shots:      .asciiz "SHOTS"
msg_hits:       .asciiz "HITS"
msg_ratio:      .asciiz "RATIO"
msg_press:      .asciiz "PRESS FIRE"
msg_ready:      .asciiz "READY"
msg_pause:      .asciiz "PAUSED"
paused:         .byte 0
pause_key:      .byte 0
msg_capt:       .asciiz "FIGHTER CAPTURED"
ready_timer:    .byte 0

base_x: ; formation slot X low byte (left edge): 4 bosses, then 4 rows of 7
    .byte 145,171,197,223,106,132,158,184
    .byte 210,236,6,106,132,158,184,210
    .byte 236,6,106,132,158,184,210,236
    .byte 6,106,132,158,184,210,236,6

base_xh: ; formation slot X bit 8
    .byte 0,0,0,0,0,0,0,0
    .byte 0,0,1,0,0,0,0,0
    .byte 0,1,0,0,0,0,0,0
    .byte 1,0,0,0,0,0,0,1

base_y: ; formation slot Y (clear of the HUD rows)
    .byte 72,72,72,72,100,100,100,100
    .byte 100,100,100,128,128,128,128,128
    .byte 128,128,156,156,156,156,156,156
    .byte 156,184,184,184,184,184,184,184

enemy_type_tbl: ; 0=boss 1=butterfly 2=bee
    .byte 0,0,0,0,1,1,1,1
    .byte 1,1,1,1,1,1,1,1
    .byte 1,1,2,2,2,2,2,2
    .byte 2,2,2,2,2,2,2,2

enemy_ptr_tbl: ; sprite id, frame A
    .byte SPR_BOSS,SPR_BOSS,SPR_BOSS,SPR_BOSS
    .byte SPR_BFLY,SPR_BFLY,SPR_BFLY,SPR_BFLY,SPR_BFLY,SPR_BFLY,SPR_BFLY,SPR_BFLY
    .byte SPR_BFLY,SPR_BFLY,SPR_BFLY,SPR_BFLY,SPR_BFLY,SPR_BFLY
    .byte SPR_BEE,SPR_BEE,SPR_BEE,SPR_BEE,SPR_BEE,SPR_BEE,SPR_BEE,SPR_BEE
    .byte SPR_BEE,SPR_BEE,SPR_BEE,SPR_BEE,SPR_BEE,SPR_BEE

; Per enemy type: 0 boss, 1 butterfly, 2 bee
type_hp:        .byte 2, 1, 1
pts_form_lo:    .byte $50, $80, $50     ; 150 / 80 / 50
pts_form_mid:   .byte $01, $00, $00
pts_dive_lo:    .byte $00, $60, $00     ; 400 / 160 / 100
pts_dive_mid:   .byte $04, $01, $01

; Difficulty tables, index 1..8 (stage 9 on stays at 8)
dive_int_tbl:   .byte 0, 130, 115, 100, 85, 70, 58, 48, 34   ; frames between dives
max_div_tbl:    .byte 0, 1, 1, 2, 2, 3, 3, 4, 5             ; aliens out of formation at once
fire_mask_tbl:  .byte 0, 1, 1, 0, 0, 0, 0, 0, 0     ; fire when rand & mask == 0
dive_dy_tbl:    .byte 0, 2, 2, 2, 2, 3, 3, 3, 3             ; dive speed, pixels per frame
shots_tbl:      .byte 0, 1, 1, 1, 2, 2, 2, 2, 2             ; shots per dive

hw_tbl:         .byte 2, 3, 4, 5                          ; beam half-width per row

jin_data:
jin_stage:
    .byte $13,$1a,7   ; G4
    .byte $ce,$22,7   ; C5
    .byte $da,$2b,7   ; E5
    .byte $26,$34,7   ; G5
    .byte $9c,$45,30   ; C6
    .byte 0,0,0             ; end
jin_over:
    .byte $ce,$22,12   ; C5
    .byte $45,$1d,12   ; A4
    .byte $3b,$17,12   ; F4
    .byte $67,$11,40   ; C4
    .byte 0,0,0             ; end
jin_capt:
    .byte $ce,$22,6   ; C5
    .byte $45,$1d,6   ; A4
    .byte $3b,$17,6   ; F4
    .byte $89,$13,6   ; D4
    .byte $67,$11,20   ; C4
    .byte 0,0,0             ; end
jin_resc:
    .byte $ce,$22,5   ; C5
    .byte $da,$2b,5   ; E5
    .byte $26,$34,5   ; G5
    .byte $9c,$45,5   ; C6
    .byte $26,$34,5   ; G5
    .byte $9c,$45,20   ; C6
    .byte 0,0,0             ; end
jin_bonus:
    .byte $26,$34,4   ; G5
    .byte $9c,$45,4   ; C6
    .byte $26,$34,4   ; G5
    .byte $9c,$45,4   ; C6
    .byte $26,$34,4   ; G5
    .byte $9c,$45,16   ; C6
    .byte 0,0,0             ; end

; Virtual sprites: slot i < 32 is enemy i (dead enemies have Y=$ff), then the ship, bullets, extras.
; spr_f is a sprite id (art.inc); the colour of the C64 sprites is part of the art here.
spr_x:              .res MAX_SPRITES+1
spr_x_msb:          .res MAX_SPRITES+1    ; MSB for X coordinates
spr_y:              .res MAX_SPRITES
                    .byte $ff               ; VS_NONE
spr_f:              .res MAX_SPRITES+1

enemy_x     = spr_x
enemy_x_msb = spr_x_msb
enemy_y     = spr_y

.ifdef HALT
halt_cnt:              .word 0
.endif
