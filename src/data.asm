; Variables and tables
; ===============================================
; DATA SECTION
; ===============================================

dual:                  !byte 0         ; 1 = dual fighter
cap_state:             !byte 0
cap_boss:              !byte 0
beam_len:              !byte 0         ; rows of beam drawn
beam_timer:            !byte 0
cap_x:                 !byte 0         ; rescued ship position
cap_msb:               !byte 0
cap_y:                 !byte 0
dying_quiet:           !byte 0         ; 1 = respawn delay without explosion
bd_chr:                !byte 0
bd_col:                !byte 0
bd_row0:               !byte 0
bd_r:                  !byte 0
bd_hw:                 !byte 0
bd_c0:                 !byte 0
bd_n:                  !byte 0
rs_tx:                 !byte 0
rs_th:                 !byte 0
cur_ship:              !byte 0
ship_xl:               !byte 0
ship_xh:               !byte 0
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
ov_by:                 !byte 0

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

enemy_state:    !fill MAX_ENEMIES, 0
enemy_timer:    !fill MAX_ENEMIES, 0    ; dive peel-off / explosion frames left
enemy_hp:       !fill MAX_ENEMIES, 0
enemy_dir:      !fill MAX_ENEMIES, 0    ; dive side: 0 left, 1 right
enemy_idx:      !fill MAX_ENEMIES, 0    ; flight path step
enemy_path:     !fill MAX_ENEMIES, 0    ; flight path (bit 7 = mirrored)
enemy_ptr:      !fill MAX_ENEMIES, 0    ; sprite pointer, frame A
enemy_esc:      !fill MAX_ENEMIES, 0    ; boss index + 1 for an escort of that boss
enemy_flag:     !fill MAX_ENEMIES, 0    ; 1 = has fired this dive

pbul_x:         !fill 4, 0
pbul_msb:       !fill 4, 0
pbul_y:         !fill 4, 0
pbul_active:    !fill 4, 0

eb_x:           !fill 3, 0
eb_msb:         !fill 3, 0
eb_y:           !fill 3, 0
eb_dx:          !fill 3, 0              ; -1, 0, +1 drift per 2 frames
eb_active:      !fill 3, 0

score:          !byte 0, 0, 0           ; BCD, low pair first
hiscore:        !byte 0, 0, 0
lives:          !byte 3
next_bonus:     !byte 2                 ; score+2 (BCD, x10000) of the next bonus ship
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
esc_boss:              !byte 0
esc_t:                 !byte 0
esc_cmp:               !byte 0
esc_cnt:               !byte 0
esc_slot:              !byte 0
esc_pts_mid:           !byte $04, $08, $16   ; boss dive points (x100) with 0/1/2 escorts
stage:                 !byte 1         ; Stage number (binary); every 4th is a challenge stage
in_chal:               !byte 0         ; 1 = current stage is a challenge stage
chal_mid:              !byte 0         ; BCD hundreds per hit in challenge stages
ch_hits:               !byte 0
step_dx:               !byte 0
add_hi:                !byte 0         ; extra ten-thousands for add_score
shots:                 !byte 0, 0      ; Bullets fired / enemies hit this stage
hits:                  !byte 0, 0
res_timer:             !byte 0
res_lo:                !byte 0
res_hi:                !byte 0
res_val:               !byte 0
calc_lo:               !byte 0
calc_hi:               !byte 0
n_lo:                  !byte 0
n_hi:                  !byte 0
n_dig:                 !byte 0
msg_nhits:      !scr "number of hits", 0
msg_perfect:    !scr "perfect!", 0
msg_bonus:      !scr "bonus 10000", 0
msg_chal:       !scr "challenging stage", 0
msg_shots:      !scr "shots", 0
msg_hits:       !scr "hits", 0
msg_ratio:      !scr "ratio", 0
msg_press:      !scr "press fire", 0
msg_ready:      !scr "ready", 0
msg_pause:      !scr "paused", 0
paused:         !byte 0
pause_key:      !byte 0
msg_capt:       !scr "fighter captured", 0
ready_timer:    !byte 0

row_lo:  !byte 0,40,80,120,160,200,240,24
    !byte 64,104,144,184,224,8,48,88
    !byte 128,168,208,248,32,72,112,152
    !byte 192

row_hi:  !byte 4,4,4,4,4,4,4,5
    !byte 5,5,5,5,5,6,6,6
    !byte 6,6,6,6,7,7,7,7
    !byte 7

base_x: ; formation slot X low byte (left edge): 4 bosses, then 4 rows of 7
    !byte 145,171,197,223,106,132,158,184
    !byte 210,236,6,106,132,158,184,210
    !byte 236,6,106,132,158,184,210,236
    !byte 6,106,132,158,184,210,236,6

base_xh: ; formation slot X bit 8
    !byte 0,0,0,0,0,0,0,0
    !byte 0,0,1,0,0,0,0,0
    !byte 0,1,0,0,0,0,0,0
    !byte 1,0,0,0,0,0,0,1

base_y: ; formation slot Y (clear of the HUD rows)
    !byte 72,72,72,72,100,100,100,100
    !byte 100,100,100,128,128,128,128,128
    !byte 128,128,156,156,156,156,156,156
    !byte 156,184,184,184,184,184,184,184

enemy_type_tbl: ; 0=boss 1=butterfly 2=bee
    !byte 0,0,0,0,1,1,1,1
    !byte 1,1,1,1,1,1,1,1
    !byte 1,1,2,2,2,2,2,2
    !byte 2,2,2,2,2,2,2,2

enemy_ptr_tbl: ; sprite pointer, frame A
    !byte 199,199,199,199,197,197,197,197
    !byte 197,197,197,197,197,197,197,197
    !byte 197,197,195,195,195,195,195,195
    !byte 195,195,195,195,195,195,195,195

enemy_col_tbl: ; sprite colour
    !byte 5,5,5,5,2,2,2,2
    !byte 2,2,2,2,2,2,2,2
    !byte 2,2,14,14,14,14,14,14
    !byte 14,14,14,14,14,14,14,14

enemy_hitcol_tbl: ; colour once damaged
    !byte 4,4,4,4,2,2,2,2
    !byte 2,2,2,2,2,2,2,2
    !byte 2,2,14,14,14,14,14,14
    !byte 14,14,14,14,14,14,14,14

; Per enemy type: 0 boss, 1 butterfly, 2 bee
type_hp:        !byte 2, 1, 1
pts_form_lo:    !byte $50, $80, $50     ; 150 / 80 / 50
pts_form_mid:   !byte $01, $00, $00
pts_dive_lo:    !byte $00, $60, $00     ; 400 / 160 / 100
pts_dive_mid:   !byte $04, $01, $01

; Difficulty tables, index 1..8 (stage 9 on stays at 8)
dive_int_tbl:   !byte 0, 130, 115, 100, 85, 70, 58, 48, 34   ; frames between dives
max_div_tbl:    !byte 0, 1, 1, 2, 2, 3, 3, 4, 5             ; aliens out of formation at once
fire_mask_tbl:  !byte 0, 1, 1, 0, 0, 0, 0, 0, 0     ; fire when rand & mask == 0
dive_dy_tbl:    !byte 0, 2, 2, 2, 2, 3, 3, 3, 3             ; dive speed, pixels per frame
shots_tbl:      !byte 0, 1, 1, 1, 2, 2, 2, 2, 2             ; shots per dive

; Last used art row per sprite pointer ($c0..$cb): a hardware sprite can be
; reused once the raster is past y + lastrow
lastrow_tbl:    !byte 13, 8, 7, 10, 10, 9, 9, 9, 9, 6, 7, 8

hw_tbl:         !byte 2, 3, 4, 5                          ; beam half-width per row
beam_clr_tbl:   !byte 6, 14, 3, 14                     ; blue / light blue / cyan shimmer

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
jin_capt:
    !byte $ce,$22,6   ; C5
    !byte $45,$1d,6   ; A4
    !byte $3b,$17,6   ; F4
    !byte $89,$13,6   ; D4
    !byte $67,$11,20   ; C4
    !byte 0,0,0             ; end
jin_resc:
    !byte $ce,$22,5   ; C5
    !byte $da,$2b,5   ; E5
    !byte $26,$34,5   ; G5
    !byte $9c,$45,5   ; C6
    !byte $26,$34,5   ; G5
    !byte $9c,$45,20   ; C6
    !byte 0,0,0             ; end
jin_bonus:
    !byte $26,$34,4   ; G5
    !byte $9c,$45,4   ; C6
    !byte $26,$34,4   ; G5
    !byte $9c,$45,4   ; C6
    !byte $26,$34,4   ; G5
    !byte $9c,$45,16   ; C6
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
sort_prev:          !byte 0
sort_ky:            !byte 0
sort_key:           !byte 0

; Virtual sprite tables (unsorted)
spr_x:              !fill MAX_SPRITES, 0
spr_x_msb:          !fill MAX_SPRITES, 0    ; MSB for X coordinates
spr_y:              !fill MAX_SPRITES, 0
spr_f:              !fill MAX_SPRITES, 0    ; Frame/pointer
spr_c:              !fill MAX_SPRITES, 0    ; Color

; Enemies are virtual sprites 0..MAX_ENEMIES-1 (dead enemies have Y=$ff)
enemy_x     = spr_x
enemy_x_msb = spr_x_msb
enemy_y     = spr_y

; Sort order table
sort_order:         !fill MAX_SPRITES, 0

; Sorted sprite tables
sort_spr_x:         !fill MAX_SPRITES, 0
sort_spr_y:         !fill MAX_SPRITES+1, 0  ; +1 for $ff end marker
sort_spr_f:         !fill MAX_SPRITES, 0
sort_spr_c:         !fill MAX_SPRITES, 0
sort_d010:          !fill MAX_SPRITES, 0    ; $d010 value after loading this sprite
sort_d01c:          !fill MAX_SPRITES+8, $ff ; $d01c value after loading this sprite
pk_n:               !byte 0
pk_list:            !fill 4, 0              ; sorted indices of hires ships
sh_msb:             !byte 0
sh_mc:              !byte 0
sh_mask:            !byte 0
sh_val:             !byte 0

; Hardware sprite bit for sorted index 0..47
bit_tbl:            !byte 1,2,4,8,16,32,64,128
                    !byte 1,2,4,8,16,32,64,128
                    !byte 1,2,4,8,16,32,64,128
                    !byte 1,2,4,8,16,32,64,128
                    !byte 1,2,4,8,16,32,64,128
                    !byte 1,2,4,8,16,32,64,128

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
                    !byte 0,1,2,3,4,5,6,7
                    !byte 0,1,2,3,4,5,6,7

phys_spr_tbl_2:     !byte 0,2,4,6,8,10,12,14
                    !byte 0,2,4,6,8,10,12,14
                    !byte 0,2,4,6,8,10,12,14
                    !byte 0,2,4,6,8,10,12,14
                    !byte 0,2,4,6,8,10,12,14
                    !byte 0,2,4,6,8,10,12,14

!ifdef HALT {
halt_cnt:              !word 0
}
