; Formation sway, enemy movement, dives and enemy bullets
; ===============================================
; FORMATION SWAY
; ===============================================
; The whole formation shifts by form_dx (signed); enemies in formation
; are placed at slot + form_dx each frame.

!zone update_formation
update_formation:
    lda entering                ; The formation holds still while it is flying in
    sta ent_start               ; (and the dive scheduler looks at this value, not at a newer one)
    bne .done
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
; enemy_state: 0 dead, 1 in formation, 2 diving, 3 returning, 4 exploding,
; 5 beaming boss, 6 challenge stage flight, 7 entering (fly-in)

!zone update_enemies
update_enemies:
    ldx #MAX_ENEMIES-1
.loop:
    lda enemy_state,x
    beq .next
    cmp #2
    bcc .next               ; In formation: placed by update_formation
    cmp #6
    bcs .next               ; Challenge stage aliens move in update_challenge, entering
                            ; aliens in update_entry
    cmp #2
    beq .dive
    cmp #4
    beq .explode
    cmp #5
    beq .next               ; Beaming boss holds still
    jsr return_step
    jmp .next
.dive:
    jsr dive_step
    jmp .next
.explode:
    jsr step_explosion
    jmp .next
.next:
    dex
    bpl .loop
    rts

; One frame of alien X's explosion: animate, then remove it
!zone step_explosion
step_explosion:
    dec enemy_timer,x
    beq .gone
    lda enemy_timer,x
    lsr
    lsr
    sta temp
    lda #SPR_EXPL1+2
    sec
    sbc temp
    sta spr_f,x                 ; Explosion frame
    rts
.gone:
    lda #0
    sta enemy_state,x
    lda #$ff                    ; Dead enemies are hidden (Y=$ff)
    sta enemy_y,x
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
    lda base_y,x                ; home: in the slot, and no longer an escort
    sta enemy_y,x
    lda #0
    sta enemy_esc,x
    lda #1
    sta enemy_state,x
.done:
    rts

; One frame of a dive. Phase A (timer > 0): peel off sideways.
; Phase B: swoop down and home in on the player. (The bombs are dropped by arc_bombs.)
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
    ldy diff
    lda enemy_y,x
    clc
    adc dive_dy_tbl,y           ; Dive speed rises with the difficulty
    sta enemy_y,x
    cpx cap_boss
    bne .half
    lda cap_state
    cmp #1
    beq .do_steer               ; A capture boss homes in on the player every frame
.half:
    lda frame
    and #1
    beq .check_end              ; Steer every other frame (the odd ones)
.do_steer:
    lda enemy_x_msb,x
    cmp player_x_msb
    bne .cmp_done
    lda enemy_x,x
    cmp player_x
    beq .check_end              ; Level with the player: stays
.cmp_done:
    bcs .go_left                ; Enemy right of the player
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
    cpx cap_boss
    bne .not_cap
    lda cap_state
    cmp #1
    bne .not_cap
    lda enemy_y,x               ; Capture dive: stop below the formation, fire the beam
    cmp #196
    bcc .not_cap
    lda #5
    sta enemy_state,x
    lda #2
    sta cap_state
    lda #0
    sta beam_len
    sta arc_beamph
    sta arc_beamacc
    lda #180
    sta beam_timer
    ldy arc_sidx                ; ticks of one beam step, by stage
    lda arc_beamstep,y
    sta arc_bstep
    rts
.not_cap:
    lda enemy_y,x
    cmp #244
    bcs .off_bottom
    rts
.off_bottom:
    lda #3                      ; Off the bottom: re-enter from the top
    sta enemy_state,x
    lda #0
    sta enemy_y,x
    sta enemy_flag,x
    rts
