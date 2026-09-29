; Sprite setup, formation setup and the game -> multiplexer sprite copy
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
    sta pbul_active+2
    sta pbul_active+3
    sta cap_state
    sta beam_len
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
    lda enemy_ptr_tbl,x
    sta enemy_ptr,x
    clc
    adc anim
    sta spr_f,x
    lda enemy_col_tbl,x
    sta spr_c,x
    jsr set_slot_pos
!ifdef FEW {
    cpx #29                     ; -DFEW=1: only 3 bees per stage (fast stage clears)
    bcs .keep
    lda #0
    sta enemy_state,x
    lda #$ff
    sta enemy_y,x
.keep:
}
    dex
    bpl .loop
    rts

; Point every enemy's sprite at the current wing-flap frame
!zone refresh_anim
refresh_anim:
    ldx #MAX_ENEMIES-1
.loop:
    lda enemy_state,x
    cmp #4
    beq .next                   ; Exploding: keeps its explosion frame
    lda enemy_ptr,x
    clc
    adc anim
    sta spr_f,x
.next:
    dex
    bpl .loop
    rts

; Enemy X turns into an explosion (state 4). Preserves X.
!zone set_explode
set_explode:
    lda #4
    sta enemy_state,x
    lda #11
    sta enemy_timer,x
    lda #8                      ; Orange
    sta spr_c,x
    lda #SPR_EXPL1
    sta spr_f,x
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
    adc base_xh,x               ; plus slot bit 8 and the carry from the low byte
    and #1
    sta enemy_x_msb,x
    rts

; ===============================================
; UPDATE SPRITE DATA FOR MULTIPLEXER
; ===============================================
; Copies game state to virtual sprite tables

!zone update_sprite_data
update_sprite_data:
    lda game_state
    beq .hide_all               ; Title: no sprites
    cmp #GS_GAMEOVER
    bne .player
.hide_all:
    ldx #MAX_SPRITES-1
    lda #$ff
.hide:
    sta spr_y,x
    dex
    bpl .hide
    jmp .done

; Every sprite has a fixed virtual slot: enemy i is slot i and shares its
; x / y (and msb, pointer, colour) with the multiplexer tables, so only the
; other sprites are copied here. Hidden sprites have Y=$ff. Stable slots keep
; last frame's sort order nearly correct, which makes the sort cheap.
.player:
    cmp #GS_DYING
    beq .p_dying
    lda invuln
    and #4
    bne .p_hide                 ; Blink while invulnerable
    lda #SPR_PLAYER
    ldx #1                      ; White
    jmp .p_add
.p_dying:
    lda dying_quiet
    bne .p_hide                 ; Captured: no explosion
    lda dying_timer
    lsr
    lsr
    lsr
    lsr
    beq .p_hide                 ; Gone for the last 16 frames
    sta temp
    lda #SPR_EXPL1+3
    sec
    sbc temp
    ldx #8                      ; Orange
.p_add:
    sta spr_f+VS_PLAYER
    stx spr_c+VS_PLAYER
    lda player_x
    sta spr_x+VS_PLAYER
    lda player_x_msb
    sta spr_x_msb+VS_PLAYER
    lda player_y
    sta spr_y+VS_PLAYER
    jmp .dual
.p_hide:
    lda #$ff
    sta spr_y+VS_PLAYER

    ; Second ship of the dual fighter
.dual:
    lda dual
    beq .d_hide
    lda invuln
    and #4
    bne .d_hide
    lda #SPR_PLAYER
    sta spr_f+VS_DUAL
    lda #1
    sta spr_c+VS_DUAL
    lda player_x
    clc
    adc #16
    sta spr_x+VS_DUAL
    lda player_x_msb
    adc #0
    sta spr_x_msb+VS_DUAL
    lda player_y
    sta spr_y+VS_DUAL
    jmp .dual_done
.d_hide:
    lda #$ff
    sta spr_y+VS_DUAL
.dual_done:

    ; Captured ship: carried by its boss, or falling back to the player
    lda cap_state
    cmp #4
    bne .c_resc
    ldx cap_boss
    lda enemy_state,x
    beq .c_hide
    lda enemy_y,x
    cmp #32
    bcc .c_hide
    sec
    sbc #16
    sta spr_y+VS_CAPT
    lda enemy_x,x
    sta spr_x+VS_CAPT
    ldy #1                      ; White
    lda enemy_x_msb,x
    jmp .c_set
.c_resc:
    cmp #5
    bne .c_hide
    lda cap_y
    sta spr_y+VS_CAPT
    lda cap_x
    sta spr_x+VS_CAPT
    ldy #1                      ; White
    lda cap_msb
.c_set:
    sta spr_x_msb+VS_CAPT
    lda #SPR_PLAYER
    sta spr_f+VS_CAPT
    sty spr_c+VS_CAPT
    jmp .c_done
.c_hide:
    lda #$ff
    sta spr_y+VS_CAPT
.c_done:

    ; Player bullets
    ldx #3
.pb_loop:
    lda pbul_active,x
    bne .pb_on
    lda #$ff
    sta spr_y+VS_PBUL,x
    jmp .pb_next
.pb_on:
    lda pbul_x,x
    sta spr_x+VS_PBUL,x
    lda pbul_msb,x
    sta spr_x_msb+VS_PBUL,x
    lda pbul_y,x
    sta spr_y+VS_PBUL,x
    lda #SPR_PBUL
    sta spr_f+VS_PBUL,x
    lda #14                     ; Light blue
    sta spr_c+VS_PBUL,x
.pb_next:
    dex
    bpl .pb_loop

    ; Enemy bullets
    ldx #2
.eb_loop:
    lda eb_active,x
    bne .eb_on
    lda #$ff
    sta spr_y+VS_EBUL,x
    jmp .eb_next
.eb_on:
    lda eb_x,x
    sta spr_x+VS_EBUL,x
    lda eb_msb,x
    sta spr_x_msb+VS_EBUL,x
    lda eb_y,x
    sta spr_y+VS_EBUL,x
    lda #SPR_EBUL
    sta spr_f+VS_EBUL,x
    lda #10                     ; Light red
    sta spr_c+VS_EBUL,x
.eb_next:
    dex
    bpl .eb_loop

.done:
    lda #1
    sta spr_update_flag         ; Signal IRQ to sort and display
    rts
