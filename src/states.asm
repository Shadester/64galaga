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
    sta shots
    sta shots+1
    sta hits
    sta hits+1
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
!ifdef LIVES {
    lda #LIVES                  ; -DLIVES=n: start with n lives (testing)
}
    sta lives
    lda #1
    sta level
    sta diff
    sta stage
!ifdef DIFF {
    lda #DIFF                   ; -DDIFF=n: start at difficulty n (1..8)
    sta diff
}
    sta fire_pressed            ; Fire held from the title must not shoot
    lda #160
    sta player_x
!ifdef HALT {
    lda #$5b                    ; Tests: same seed every run
} else {
    lda $d012                   ; Seed RNG from the raster
}
    ora #1
    sta rnd
    lda #0
    sta in_chal
    sta chal_mid
    sta paused
    jsr begin_stage             ; Stage 1 (fly-in)
!ifdef STAGE {
    lda #STAGE                  ; -DSTAGE=n: start at stage n (challenge stage testing)
    sta stage
    sta level
    jsr begin_stage
}
    ; fall through

; --- Stage intro ---
!zone start_stage
start_stage:
    lda #GS_INTRO
    sta game_state
    lda #120
    sta intro_timer
    lda in_chal
    bne .chal
    +print msg_stage, SCREEN_RAM+16*40+16, 1   ; Below the formation
    +setdst SCREEN_RAM+16*40+22
    lda level
    jsr draw_bcd
    lda #jin_stage-jin_data
    jmp play_jingle
.chal:
    +print msg_chal, SCREEN_RAM+16*40+11, 1
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

; --- Stage result: shots, hits and hit ratio ---
!zone enter_result
enter_result:
    lda #GS_RESULT
    sta game_state
    lda #150
    sta res_timer
    ldx #199                    ; print_num only writes characters: start from white,
    lda #1                      ; not from whatever the stars left in colour RAM
.white:
    sta COLOR_RAM+9*40,x
    dex
    cpx #$ff
    bne .white
    lda in_chal
    beq .std
    jmp chal_result
.std:
    +print msg_shots, SCREEN_RAM+9*40+14, 1
    +setdst SCREEN_RAM+9*40+21
    lda shots
    ldx shots+1
    jsr print_num
    +print msg_hits, SCREEN_RAM+11*40+14, 1
    +setdst SCREEN_RAM+11*40+21
    lda hits
    ldx hits+1
    jsr print_num
    +print msg_ratio, SCREEN_RAM+13*40+14, 1
    jsr calc_ratio              ; A = hits * 100 / shots
    sta res_val
    +setdst SCREEN_RAM+13*40+21
    lda res_val
    ldx #0
    jsr print_num
    lda #$25                    ; '%'
    ldy #0
    sta (zp_dst),y
    rts

!zone st_result
st_result:
    jsr update_player           ; The ship stays under control
    jsr update_bullets
    dec res_timer
    bne .rts
    jsr clear_result
    lda #0                      ; Next stage starts with fresh counters
    sta shots
    sta shots+1
    sta hits
    sta hits+1
    jsr begin_stage
    jmp start_stage
.rts:
    rts

!zone clear_result
clear_result:
    ldx #199
    lda #$20
.loop:
    sta SCREEN_RAM+9*40,x
    dex
    cpx #$ff
    bne .loop
    rts

; A = hits * 100 / shots (0 when nothing was fired, at most 100)
!zone calc_ratio
calc_ratio:
    lda #0
    sta res_lo
    sta res_hi
    lda shots
    ora shots+1
    beq .none
    lda #0                      ; num = hits * 100 (hits stays below 256 per stage)
    sta calc_lo
    sta calc_hi
    ldx hits
    beq .div
.mul:
    lda calc_lo
    clc
    adc #100
    sta calc_lo
    bcc .m1
    inc calc_hi
.m1:
    dex
    bne .mul
.div:
    lda calc_lo                 ; while num >= shots: num -= shots, q++
    sec
    sbc shots
    tax
    lda calc_hi
    sbc shots+1
    bcc .done
    sta calc_hi
    stx calc_lo
    inc res_lo
    lda res_lo
    cmp #100
    bcc .div
.done:
.none:
    lda res_lo
    rts

; Print the number in A (low) / X (high, at most 999) as 3 digits at zp_dst,
; blanking leading zeros. Advances zp_dst by 3.
!zone print_num
print_num:
    sta n_lo
    stx n_hi
    lda n_hi
    cmp #4
    bcc .ok
    lda #<999
    sta n_lo
    lda #>999
    sta n_hi
.ok:
    ldy #0                      ; hundreds
.h:
    lda n_lo
    sec
    sbc #100
    tax
    lda n_hi
    sbc #0
    bcc .h_done
    sta n_hi
    stx n_lo
    iny
    bne .h
.h_done:
    sty n_dig
    tya
    beq .blank1
    ora #$30
    bne .put1
.blank1:
    lda #$20
.put1:
    ldy #0
    sta (zp_dst),y
    ldy #0                      ; tens
.t:
    lda n_lo
    cmp #10
    bcc .t_done
    sbc #10
    sta n_lo
    iny
    bne .t
.t_done:
    tya
    ora n_dig                   ; blank only if hundreds and tens are both zero
    beq .blank2
    tya
    ora #$30
    bne .put2
.blank2:
    lda #$20
.put2:
    ldy #1
    sta (zp_dst),y
    lda n_lo
    ora #$30
    iny
    sta (zp_dst),y
    lda zp_dst
    clc
    adc #3
    sta zp_dst
    bcc .rts
    inc zp_dst+1
.rts:
    rts

; --- Playing ---
!zone st_play
st_play:
!ifdef DIEAT {
    lda halt_cnt+1              ; -DDIEAT=n (with HALT): the ship is hit at frame n
    cmp #>DIEAT
    bne .no_die
    lda halt_cnt
    cmp #<DIEAT
    bne .no_die
    jmp player_hit
.no_die:
}
    lda invuln
    beq .no_invuln
    dec invuln
.no_invuln:
    jsr update_player
    jsr update_bullets
    lda in_chal
    beq .std_stage
    jsr update_challenge        ; Bonus stage: scripted flights, no shooting back
    jmp .coll
.std_stage:
    jsr update_formation
    jsr update_entry
    jsr update_enemies
    jsr update_dives
    jsr update_ebullets
.coll:
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
    jsr update_entry
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
    jsr clear_stage_row
    +print msg_ready, SCREEN_RAM+20*40+17, 1
    lda #90
    sta ready_timer
    lda #GS_READY
    sta game_state
    rts
.game_over:
    jmp enter_gameover

; --- READY: the aliens carry on, then the ship respawns ---
!zone st_ready
st_ready:
    jsr update_formation
    jsr update_entry
    jsr update_enemies
    dec ready_timer
    bne .rts
    jsr clear_stage_row
    lda #160                    ; Respawn, briefly invulnerable
    sta player_x
    lda #0
    sta player_x_msb
    sta dying_quiet
    lda #120
    sta invuln
    lda #GS_PLAY
    sta game_state
.rts:
    rts

; --- Ship caught in a tractor beam ---
!zone st_captured
st_captured:
    jsr update_formation
    jsr update_entry
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
    lda #100
    sta dying_timer
    +print msg_capt, SCREEN_RAM+20*40+12, 2
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
    lda #1
    sta hs_dirty                ; Saved once the game over jingle is done
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
    lda hs_dirty
    beq .no_save
    jsr save_hiscore
.no_save:
    lda #1
    sta fire_pressed        ; Held fire must be released first
    +print msg_press, SCREEN_RAM+14*40+15, 1
!ifdef HALTOVER {
    jmp *                       ; -DHALTOVER=1: freeze on the game over screen (tests/run.sh)
}
.rts:
    rts
.wait:
    lda joystick_state
    and #$10
    bne .rts
    lda fire_pressed
    bne .rts
    jmp enter_title
