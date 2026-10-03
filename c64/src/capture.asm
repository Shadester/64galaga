; Tractor beam, capture and rescue
; ===============================================
; TRACTOR BEAM / CAPTURE
; ===============================================
; cap_state: 0 none, 1 boss diving to capture, 2 beam on, 3 ship being
; pulled up, 4 captive carried by cap_boss, 5 rescued captive flying down.

; The capture boss was shot. In: X = boss. Preserves nothing.
!zone boss_killed
boss_killed:
    lda cap_state
    cmp #4
    beq .carrying
    cmp #2
    bne .clear
    jsr beam_erase
.clear:
    lda #0
    sta cap_state
    rts
.carrying:
    lda enemy_state,x
    cmp #1
    beq .clear              ; Shot in formation: the captive is destroyed
    lda enemy_x,x           ; Shot while diving: the captive is freed
    sta cap_x
    lda enemy_x_msb,x
    sta cap_msb
    lda enemy_y,x
    sec
    sbc #16
    sta cap_y
    lda #5
    sta cap_state
    lda #$00                ; +1000
    ldx #$10
    jsr add_score
    lda #jin_resc-jin_data
    jmp play_jingle

; Per-frame beam logic and drawing (cap_state 2 or 3) and rescue flight (5)
!zone update_capture
update_capture:
    lda cap_state
    cmp #5
    bne .n5
    jmp rescue_step
.n5:
    cmp #2
    beq .beam
    cmp #3
    bne .none
    jmp .draw
.none:
    rts
.beam:
    lda arc_beamph
    beq .grow
    cmp #2
    bne .hold
    jmp .shrink
.hold:
    lda game_state              ; Hold: the ship under the beam is taken
    cmp #GS_PLAY
    bne .timer
    lda invuln
    bne .timer
    ldx cap_boss
    lda enemy_x,x
    sta ov_bl
    lda enemy_x_msb,x
    sta ov_bh
    lda player_x_msb
    sta ov_ah
    lda #20
    sta ov_off
    lda #40
    sta ov_w
    lda player_x
    jsr x_overlap
    bcs .timer
    lda #GS_CAPTURED        ; Caught!
    sta game_state
    lda #3
    sta cap_state
    lda #0
    sta pbul_active
    sta pbul_active+1
    sta pbul_active+2
    sta pbul_active+3
    lda #jin_capt-jin_data
    jmp play_jingle
.timer:
    dec beam_timer
    bne .draw
    lda #2                  ; Missed: the beam shrinks again
    sta arc_beamph
    lda #0
    sta arc_beamacc
    jmp .draw
.grow:
    inc arc_beamacc         ; A row every arc_bstep ticks
    lda arc_beamacc
    cmp arc_bstep
    bcc .draw
    lda #0
    sta arc_beamacc
    inc beam_len
    lda beam_len
    cmp #4
    bcc .draw
    lda #1                  ; Full length: it holds for 53 ticks
    sta arc_beamph
    lda #53
    sta beam_timer
    jmp .draw
.shrink:
    inc arc_beamacc
    lda arc_beamacc
    cmp arc_bstep
    bcc .draw
    lda #0
    sta arc_beamacc
    lda #$20                ; One row less
    jsr beam_draw
    dec beam_len
    beq .gone
    lda #$66
    jsr beam_draw
    jmp .draw
.gone:
    ldx cap_boss            ; The boss gives up and flies home
    lda #3
    sta enemy_state,x
    lda #0
    sta enemy_y,x
    sta enemy_flag,x
    sta cap_state
    rts
.draw:
    lda frame
    and #31
    bne .nosnd
    lda #24
    sta swoop_cnt           ; Beam hum on voice 3
.nosnd:
    lda frame
    and #3
    bne .rts
    lda #$66
    jmp beam_draw
.rts:
    rts

!zone beam_erase
beam_erase:
    lda #$20
    jsr beam_draw
    lda #0
    sta beam_len
    rts

; Draw (A = $66) or erase (A = $20) the cone of the beam under boss cap_boss
!zone beam_draw
beam_draw:
    sta bd_chr
    ldx cap_boss
    lda enemy_x,x           ; Column of the boss centre: (x - 18) / 8
    sec
    sbc #18
    sta bd_col
    lda enemy_x_msb,x
    sbc #0
    lsr
    ror bd_col
    lsr bd_col
    lsr bd_col
    lda enemy_y,x           ; First row: just under the boss
    sec
    sbc #36
    lsr
    lsr
    lsr
    sta bd_row0
    lda #0
    sta bd_r
.row:
    ldx bd_r
    cpx beam_len
    bcs .end
    lda hw_tbl,x
    sta bd_hw
    lda bd_col
    sec
    sbc bd_hw
    bcs .c0ok
    lda #0
.c0ok:
    sta bd_c0
    lda bd_col
    clc
    adc bd_hw
    cmp #40
    bcc .c1ok
    lda #39
.c1ok:
    sec
    sbc bd_c0
    sta bd_n                ; Cells in this row - 1
    lda bd_row0
    clc
    adc bd_r
    cmp #25
    bcs .end
    tax
    lda row_lo,x
    clc
    adc bd_c0
    sta zp_dst
    sta zp_col
    lda row_hi,x
    adc #0
    sta zp_dst+1
    clc
    adc #>(COLOR_RAM-SCREEN_RAM)
    sta zp_col+1
    ldy #0
.cell:
    lda bd_chr
    sta (zp_dst),y
    tya
    clc
    adc bd_r
    sta temp
    lda frame
    lsr
    lsr
    clc
    adc temp
    and #3
    tax
    lda beam_clr_tbl,x
    sta (zp_col),y
    iny
    cpy bd_n
    beq .cell
    bcc .cell
    inc bd_r
    jmp .row
.end:
    rts

; A rescued ship falls towards the spot next to the player and docks
!zone rescue_step
rescue_step:
    lda cap_y
    clc
    adc #3
    cmp #PLAYER_Y
    bcc .ynot
    lda #PLAYER_Y
.ynot:
    sta cap_y
    lda player_x            ; Dock spot: 16px right of the player
    clc
    adc #16
    sta rs_tx
    lda player_x_msb
    adc #0
    sta rs_th
    lda cap_msb
    cmp rs_th
    bne .cmp
    lda cap_x
    cmp rs_tx
    beq .steered                ; level: stays
.cmp:
    bcs .left
    lda cap_x
    clc
    adc #2
    sta cap_x
    bcc .steered
    inc cap_msb
    jmp .steered
.left:
    lda cap_x
    sec
    sbc #2
    sta cap_x
    bcs .steered
    dec cap_msb
.steered:
    lda cap_y
    cmp #PLAYER_Y
    bcc .rts
    lda game_state
    cmp #GS_PLAY
    bne .rts
    lda cap_x               ; Close enough to dock?
    sec
    sbc rs_tx
    clc
    adc #4
    cmp #8
    bcs .rts
    lda #1
    sta dual
    lda #0
    sta cap_state
    lda player_x_msb        ; Keep the pair on screen
    beq .docked
    lda player_x
    cmp #<(SCREEN_RIGHT-16)
    bcc .docked
    lda #<(SCREEN_RIGHT-16)
    sta player_x
.docked:
    lda #jin_resc-jin_data
    jmp play_jingle
.rts:
    rts
