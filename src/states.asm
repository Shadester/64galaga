; Game states: title, stage intro, play, dying, captured, game over
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
    sta dual
    sta cap_state
    sta beam_len
    sta dying_quiet
    lda #2                      ; First bonus ship at 20,000
    sta next_bonus
    lda #0
!ifdef DUAL {
    lda #1                      ; -DDUAL=1: start with a dual fighter (testing)
    sta dual
}
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
    jsr update_capture
    lda game_state
    cmp #GS_PLAY
    bne .play_done          ; Player was hit or captured this frame
    jmp check_level_complete
.play_done:
    rts

; --- Player exploding ---
!zone st_dying
st_dying:
    jsr update_formation
    jsr update_enemies
    jsr update_ebullets
    jsr update_capture
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
    lda #0
    sta dying_quiet
    lda #GS_PLAY
    sta game_state
    rts
.game_over:
    jmp enter_gameover

; --- Ship caught in a tractor beam ---
!zone st_captured
st_captured:
    jsr update_formation
    jsr update_enemies
    jsr update_ebullets
    jsr update_capture
    lda player_y                ; Pulled up towards the boss
    sec
    sbc #2
    sta player_y
    ldx cap_boss
    sec
    sbc enemy_y,x
    cmp #22
    bcs .rts                    ; Not there yet
    jsr beam_erase              ; Caught: the boss carries the ship away
    lda #PLAYER_Y
    sta player_y
    ldx cap_boss
    lda #3                      ; Boss flies back to its slot with the captive
    sta enemy_state,x
    lda #0
    sta enemy_y,x
    sta enemy_flag,x
    lda #4
    sta cap_state
    lda #1
    sta dying_quiet             ; No explosion for a captured ship
    dec lives
    beq .last
    lda #GS_DYING
    sta game_state
    lda #45
    sta dying_timer
.rts:
    rts
.last:
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
