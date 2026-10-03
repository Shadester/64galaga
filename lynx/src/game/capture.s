; Tractor beam, capture and rescue (the logic is in arc.s)
; cap_state: 0 none, 1 boss diving to capture, 2 beam on, 3 ship being
; pulled up, 4 captive carried by cap_boss, 5 rescued captive flying down.

; A rescued ship falls towards the spot next to the player and docks

rescue_step:
    lda cap_y
    clc
    adc #RESC_VY
    cmp #PLAYER_Y
    bcc @ynot
    lda #PLAYER_Y
@ynot:
    sta cap_y
    lda player_x            ; Dock spot: beside the player
    clc
    adc #DUAL_DX
    sta rs_tx
    lda player_x_msb
    adc #0
    sta rs_th
    lda cap_msb
    cmp rs_th
    bne @cmp
    lda cap_x
    cmp rs_tx
@cmp:
    bcs @left
    lda cap_x
    clc
    adc #RESC_VX
    sta cap_x
    bcc @steered
    inc cap_msb
    jmp @steered
@left:
    lda cap_x
    sec
    sbc #RESC_VX
    sta cap_x
    bcs @steered
    dec cap_msb
@steered:
    lda cap_y
    cmp #PLAYER_Y
    bcc @rts
    lda game_state
    cmp #GS_PLAY
    bne @rts
    lda cap_x               ; Close enough to dock?
    sec
    sbc rs_tx
    clc
    adc #HB_DOCK_L
    cmp #HB_DOCK_L+HB_DOCK_R+1
    bcs @rts
    lda #1
    sta dual
    lda #0
    sta cap_state
    lda player_x_msb        ; Keep the pair on screen
    beq @docked
    lda player_x
    cmp #<(SCREEN_RIGHT-DUAL_DX)
    bcc @docked
    lda #<(SCREEN_RIGHT-DUAL_DX)
    sta player_x
@docked:
    lda #jin_resc-jin_data
    jmp play_jingle
@rts:
    rts
