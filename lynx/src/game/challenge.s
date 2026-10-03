; Challenge (bonus) stages: 32 aliens fly through set paths in four waves,
; never shoot, and pay points for every hit.

; Flight path data (src/paths.asm), indexed by path: 0 = A, 1 = B (challenge
; stages), 2 = C, 3 = D (fly-in). enemy_path = path | $80 when mirrored.
.ifndef ARCADE
path_x0:        .byte <PATHA_X0, <PATHB_X0, <PATHC_X0, <PATHD_X0
path_x0h:       .byte >PATHA_X0, >PATHB_X0, >PATHC_X0, >PATHD_X0
path_y0:        .byte PATHA_Y0, PATHB_Y0, PATHC_Y0, PATHD_Y0
path_len:       .byte PATHA_LEN, PATHB_LEN, PATHC_LEN, PATHD_LEN
chal_path_tbl:  .byte 0, 1, $80, $81            ; path per wave

wave_delay:     .byte 0, 55, 110, 165           ; frames before a wave starts
pos_delay:      .byte 0, 6, 12, 18, 24, 30, 36, 42  ; ... and between its aliens
chal_ptr_tbl:   .byte SPR_BEE, SPR_BFLY, SPR_BEE, SPR_BOSS    ; sprite per wave
.endif

; Slot s belongs to wave s>>3. Waves 0/2 fly path A, waves 1/3 path B, and
; waves 2/3 are mirrored left-right (chal_path_tbl).

.ifndef ARCADE
; Is this a challenge stage? Stages 3, 7, 11, ... are. Sets up the stage.

begin_stage:
    lda stage
    and #3
    cmp #3
    bne @normal
    lda #1
    sta in_chal
    lda chal_mid                ; Points per hit: 100, 200, ... up to 900
    cmp #$09
    bcs @set
    sed
    clc
    adc #1
    cld
    sta chal_mid
@set:
    jmp reset_challenge
@normal:
    lda #0
    sta in_chal
    jsr reset_formation
.ifdef ARCADE
    rts                         ; no fly-in yet in the 40-alien build: the aliens stand in their slots
.else
    jmp setup_entry             ; Aliens fly in
.endif

; Every alien waits (hidden) for its turn to fly in

reset_challenge:
    jsr reset_formation         ; Clears bullets, capture, sway ...
    lda #0
    sta ch_hits
    ldx #MAX_ENEMIES-1
@loop:
    txa
    and #7
    tay
    lda pos_delay,y
    sta temp
    txa
    lsr
    lsr
    lsr
    tay
    lda wave_delay,y
    clc
    adc temp
    sta enemy_timer,x           ; Launch delay
    lda chal_path_tbl,y
    sta enemy_path,x
    lda #6
    sta enemy_state,x
    lda #0
    sta enemy_flag,x            ; 0 = waiting, 1 = flying
    sta enemy_idx,x
    lda #1
    sta enemy_hp,x
    lda chal_ptr_tbl,y
    sta enemy_ptr,x
    clc
    adc anim
    sta spr_f,x
    lda #$ff
    sta enemy_y,x               ; Hidden
    dex
    bpl @loop
    rts

; Per-frame: launch waiting aliens and move flying ones along their path

update_challenge:
    ldx #MAX_ENEMIES-1
@loop:
    lda enemy_state,x
    cmp #6
    beq @flying
    cmp #4
    bne @next
    jsr step_explosion          ; (update_enemies is not needed in a challenge stage)
    jmp @next
@flying:
    lda enemy_flag,x
    bne @fly
    lda enemy_timer,x
    beq @launch
    dec enemy_timer,x
    jmp @next
@launch:
    lda #1
    sta enemy_flag,x
    jsr place_start
    jmp @next
@fly:
    jsr chal_step
@next:
    dex
    bpl @loop
    rts

; Put alien X at the start of its path

place_start:
    lda enemy_path,x
    and #3
    tay
    lda path_y0,y
    sta enemy_y,x
    lda path_x0,y
    sta enemy_x,x
    lda path_x0h,y
    sta enemy_x_msb,x
    lda enemy_path,x
    bpl @rts                    ; Not mirrored
    lda #<344                   ; Mirror x -> 344 - x
    sec
    sbc enemy_x,x
    sta enemy_x,x
    lda #>344
    sbc enemy_x_msb,x
    sta enemy_x_msb,x
@rts:
    rts

; One step of alien X along its path. At the end of the path a challenge
; alien (state 6) leaves; an entering alien (state 7) starts homing.

chal_step:
    lda enemy_path,x
    and #3
    sta path_id
    asl                         ; The tables sit on their own pages: dx A, dy A, dx B, ...
    adc #>pathA_dx              ; (carry is clear)
    sta zp_path+1
    adc #1
    sta zp_col+1                ; (the colour pointer is free here)
    lda #0
    sta zp_path
    sta zp_col
    ldy enemy_idx,x
    lda (zp_path),y
    sta step_dx
    lda (zp_col),y
    clc
    adc enemy_y,x
    sta enemy_y,x
    lda enemy_path,x
    bpl @dx                     ; Not mirrored
    lda step_dx                 ; Mirrored: negate dx
    eor #$ff
    clc
    adc #1
    sta step_dx
@dx:
    lda step_dx
    bmi @neg
    clc
    adc enemy_x,x
    sta enemy_x,x
    bcc @moved
    inc enemy_x_msb,x
    jmp @moved
@neg:
    clc
    adc enemy_x,x
    sta enemy_x,x
    bcs @moved
    dec enemy_x_msb,x
@moved:
    inc enemy_idx,x
    ldy path_id
    lda enemy_idx,x
    cmp path_len,y
    bcc @rts
    lda enemy_state,x
    cmp #7
    beq @arrive
    lda #0                      ; End of the path: gone
    sta enemy_state,x
    lda #$ff
    sta enemy_y,x
    rts
@arrive:
    lda #2                      ; Now home in on the formation slot
    sta enemy_flag,x
@rts:
    rts

.endif
; Result screen of a challenge stage: number of hits and the perfect bonus

chal_result:
.ifdef FORCEPERFECT
    lda #MAX_ENEMIES            ; -DFORCEPERFECT=1: pretend every alien was hit
    sta ch_hits
.endif
    print msg_nhits, SCREEN_RAM+9*40+12, 1
    setnum num_a
    lda ch_hits
    ldx #0
    jsr print_num
    print num_a, SCREEN_RAM+9*40+27, 1
    lda ch_hits
    cmp #MAX_ENEMIES
    bne @rts
    print msg_perfect, SCREEN_RAM+11*40+16, 7
    print msg_bonus, SCREEN_RAM+13*40+14, 1
    lda #1                      ; 10,000 points
    sta add_hi
    lda #0
    tax
    jsr add_score
@rts:
    rts
