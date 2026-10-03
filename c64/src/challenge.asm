; Challenge (bonus) stages: 32 aliens fly the arcade's paths in four groups of 8,
; never shoot, and pay points for every hit.

; Entry and challenge stage flights: the arcade's paths on the 32 slots (arcade_wave.asm, arcade_paths.asm,
; made by tools/gen_arcade.py). A path is a list of bytes, one for each tick: an index in pair_dx / pair_dy, $ff ends it.
; enemy_path = the path of an alien, enemy_pl / enemy_ph = where it is in the list.
; The launches of a stage are a list of 32 (tick, slot, path), sorted by tick, for the row of the stage (arc_rowof):
; wave_clk counts the ticks in which the ship is in play, wave_off is the place in the list.

type_ptr:       !byte SPR_BOSS, SPR_BFLY, SPR_BEE    ; sprite of a challenge alien, by kind (chal_type)
type_col:       !byte 5, 2, 14

wave_clk:       !word 0
wave_off:       !byte 0
wave_row_lo:    !byte 0
wave_row_hi:    !byte 0

; A new stage: the clock and the list of its row
!zone wave_reset
wave_reset:
    lda #0
    sta wave_clk
    sta wave_clk+1
    sta wave_off
    ldy arc_sidx
    lda arc_rowof,y
    lsr
    pha
    lda #0
    ror                         ; $80 for an odd row: a row is 128 bytes
    sta wave_row_lo
    pla
    clc
    adc #>arc_wl
    sta wave_row_hi
    rts

; One tick has passed in which the ship is in play: launch every alien whose time has come
!zone wave_launch
wave_launch:
    inc wave_clk
    bne .c
    inc wave_clk+1
.c:
    lda wave_row_lo
    sta zp_col
    lda wave_row_hi
    sta zp_col+1
.next:
    ldy wave_off
    cpy #128
    bcs .rts
    lda wave_clk
    sec
    sbc (zp_col),y              ; clock - tick (16 bits)
    iny
    lda wave_clk+1
    sbc (zp_col),y
    bcc .rts                    ; not yet
    iny
    lda (zp_col),y
    tax
    iny
    lda (zp_col),y
    sta enemy_path,x
    iny
    sty wave_off
    lda enemy_state,x
    cmp #6
    beq .go
    cmp #7
    bne .next                   ; not there (FEW)
.go:
    lda #1
    sta enemy_flag,x
    jsr place_start
    jmp .next
.rts:
    rts

; Is this a challenge stage? Stages 3, 7, 11, ... are. Sets up the stage.
!zone begin_stage
begin_stage:
    lda stage
    and #3
    cmp #3
    bne .normal
    lda #1
    sta in_chal
    lda #1                      ; 100 points per hit
    sta chal_mid
    jmp reset_challenge
.normal:
    lda #0
    sta in_chal
    jsr reset_formation
    jmp setup_entry             ; Aliens fly in

; Every alien waits (hidden) for its turn to fly in
!zone reset_challenge
reset_challenge:
    jsr reset_formation         ; Clears bullets, capture, sway ...
    lda #0
    sta ch_hits
    ldx #MAX_ENEMIES-1
.loop:
    lda #6
    sta enemy_state,x
    lda #0
    sta enemy_flag,x
    lda #1
    sta enemy_hp,x
    ldy chal_type,x
    lda type_ptr,y
    sta enemy_ptr,x
    clc
    adc anim
    sta spr_f,x
    lda type_col,y
    sta spr_c,x
    lda #$ff
    sta enemy_y,x               ; Hidden
    dex
    bpl .loop
    jmp wave_reset

; Per tick: move the flying aliens along their paths, then launch the ones whose time has come
!zone update_challenge
update_challenge:
    ldx #MAX_ENEMIES-1
.loop:
    lda enemy_state,x
    cmp #6
    beq .flying
    cmp #4
    bne .next
    jsr step_explosion          ; (update_enemies is not needed in a challenge stage)
    jmp .next
.flying:
    lda enemy_flag,x
    beq .next                   ; waiting
    jsr chal_step
.next:
    dex
    bpl .loop
    jmp wave_launch

; Put alien X at the start of its path
!zone place_start
place_start:
    ldy enemy_path,x
    lda path_sy,y
    sta enemy_y,x
    lda path_sx_lo,y
    sta enemy_x,x
    lda path_sx_hi,y
    sta enemy_x_msb,x
    lda path_lo,y
    sta enemy_pl,x
    lda path_hi,y
    sta enemy_ph,x
    rts

; One step of alien X along its path. At the end of the path a challenge
; alien (state 6) leaves; an entering alien (state 7) starts homing (one tick later).
!zone chal_step
chal_step:
    lda enemy_pl,x
    sta zp_path
    lda enemy_ph,x
    sta zp_path+1
    ldy #0
    lda (zp_path),y
    cmp #$ff
    beq .over                   ; The step after the last one ends the path (as in psp/game.c)
    tay
    lda pair_dy,y
    clc
    adc enemy_y,x
    sta enemy_y,x
    lda pair_dx,y
    bmi .neg
    clc
    adc enemy_x,x
    sta enemy_x,x
    bcc .moved
    inc enemy_x_msb,x
    jmp .moved
.neg:
    clc
    adc enemy_x,x
    sta enemy_x,x
    bcs .moved
    dec enemy_x_msb,x
.moved:
    inc enemy_pl,x
    bne .rts
    inc enemy_ph,x
.rts:
    rts
.over:
    lda enemy_state,x
    cmp #7
    beq .arrive
    lda #0                      ; End of the path: gone
    sta enemy_state,x
    lda #$ff
    sta enemy_y,x
    rts
.arrive:
    lda #2                      ; Now home in on the formation slot
    sta enemy_flag,x
    rts

; Result screen of a challenge stage: number of hits and the perfect bonus
!zone chal_result
chal_result:
!ifdef FORCEPERFECT {
    lda #MAX_ENEMIES            ; -DFORCEPERFECT=1: pretend every alien was hit
    sta ch_hits
}
    +print msg_nhits, SCREEN_RAM+9*40+12, 1
    +setdst SCREEN_RAM+9*40+27
    lda ch_hits
    ldx #0
    jsr print_num
    lda ch_hits
    cmp #MAX_ENEMIES
    bne .rts
    +print msg_perfect, SCREEN_RAM+11*40+16, 7
    +print msg_bonus, SCREEN_RAM+13*40+14, 1
    lda #1                      ; 10,000 points
    sta add_hi
    lda #0
    tax
    jsr add_score
.rts:
    rts
