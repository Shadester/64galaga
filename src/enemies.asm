; Formation sway, enemy movement, dives and enemy bullets
; ===============================================
; FORMATION SWAY
; ===============================================
; The whole formation shifts by form_dx (signed); enemies in formation
; are placed at slot + form_dx each frame.

!zone update_formation
update_formation:
    lda entering                ; The formation holds still while it is flying in
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
    beq .dive
    cmp #4
    beq .explode
    cmp #5
    beq .next               ; Beaming boss holds still
    cmp #6
    beq .next               ; Challenge stage aliens move in update_challenge
    cmp #7
    beq .next               ; Entering aliens move in update_entry
    jsr return_step
    jmp .next
.dive:
    jsr dive_step
    jmp .next
.explode:
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
    jmp .next
.gone:
    lda #0
    sta enemy_state,x
    lda #$ff                    ; Dead enemies are hidden (Y=$ff)
    sta enemy_y,x
.next:
    dex
    bpl .loop
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
    lda #1
    sta enemy_state,x
.done:
    rts

; One frame of a dive. Phase A (timer > 0): peel off sideways.
; Phase B: swoop down, home in on the player, fire once.
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
    bne .not_cap
    lda cap_state
    cmp #1
    bne .not_cap
    lda enemy_y,x           ; Capture dive: stop below the formation, fire the beam
    cmp #196
    bcc .not_cap
    lda #5
    sta enemy_state,x
    lda #2
    sta cap_state
    lda #0
    sta beam_len
    lda #180
    sta beam_timer
    rts
.not_cap:
    lda enemy_flag,x            ; 0 not fired yet, 1 done (or never fires), 2 second shot due
    beq .first
    cmp #2
    bne .steer
    lda enemy_y,x
    cmp #150
    bcc .steer
    lda #1
    sta enemy_flag,x
    jmp .fire
.first:
    lda enemy_y,x
    cmp #100
    bcc .steer
    ldy diff
    lda shots_tbl,y
    sta enemy_flag,x
.fire:
    jsr rand
    ldy diff
    and fire_mask_tbl,y
    bne .steer
    jsr spawn_ebullet
.steer:
    cpx cap_boss
    bne .half
    lda cap_state
    cmp #1
    beq .do_steer           ; A capture boss homes in on the player every frame
.half:
    lda frame
    and #1
    bne .check_end          ; Steer every other frame
.do_steer:
    lda enemy_x_msb,x
    cmp player_x_msb
    bne .cmp_done
    lda enemy_x,x
    cmp player_x
.cmp_done:
    bcs .go_left            ; Enemy right of (or level with) player
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
    lda enemy_y,x
    cmp #244
    bcs .off_bottom
    rts
.off_bottom:
    lda #3                  ; Off the bottom: re-enter from the top
    sta enemy_state,x
    lda #0
    sta enemy_y,x
    sta enemy_flag,x
    rts

; Start a dive for enemy X
!zone start_dive
start_dive:
    lda #2
    sta enemy_state,x
    lda #20
    sta enemy_timer,x
    lda #0
    sta enemy_flag,x
    sta enemy_esc,x         ; Not (yet) an escort
    lda enemy_x_msb,x
    bne .right              ; X >= 256: right of centre
    lda enemy_x,x
    cmp #184
    lda #0
    rol                     ; 1 = right of centre: peel off to the right
    jmp .set_dir
.right:
    lda #1
.set_dir:
    sta enemy_dir,x
    lda #24
    sta swoop_cnt
    rts

; Every dive_timer frames, send a random formation enemy diving
; (up to max_div_tbl[diff] out of formation at once)
!zone update_dives
update_dives:
    lda entering            ; No dives while the formation is still flying in
    bne .rts
    lda dive_timer
    beq .try
    dec dive_timer
    rts
.try:
    ldy diff
    lda dive_int_tbl,y
    sta dive_timer
    lda #0
    sta temp
    ldx #MAX_ENEMIES-1
.count:
    lda enemy_state,x
    cmp #2
    bcc .count_next
    cmp #4
    bcs .count_next
    inc temp                ; diving or returning
.count_next:
    dex
    bpl .count
    lda temp
    cmp max_div_tbl,y
    bcs .rts
    lda #8                  ; Up to 8 random picks
    sta temp
!ifdef BOSSDIVE {
    ldx #1                  ; -DBOSSDIVE=1: boss 1 always dives (escort test)
    lda enemy_state,x
    cmp #1
    beq .start
    rts
}
!ifdef CAPTURE {
    ldx #1                  ; -DCAPTURE=1: boss 1 always dives (capture test)
    lda enemy_state,x
    cmp #1
    beq .start
    rts
}
    lda cap_state           ; Bosses are 4 of 32 slots: when a capture is possible
    ora dual                ; look at them directly half of the time
    bne .pick
    jsr rand
    and #1
    bne .pick
    jsr rand
    and #3
    tax
    lda enemy_state,x
    cmp #1
    bne .pick
    jmp .start
.pick:
    jsr rand
    and #$1f
    cmp #MAX_ENEMIES
    bcs .retry
    tax
    lda enemy_state,x
    cmp #1
    beq .start
.retry:
    dec temp
    bne .pick
.rts:
    rts
.start:
    lda enemy_type_tbl,x
    bne .normal             ; Only bosses capture
    lda cap_state
    ora dual
    bne .normal
    lda game_state
    cmp #GS_PLAY
    bne .normal
    jsr start_dive
    stx cap_boss
    lda #1
    sta cap_state
    sta enemy_flag,x        ; No bullets on a capture dive
    lda enemy_x,x           ; Peel off towards the player's side
    cmp player_x
    lda #0
    rol
    eor #1
    sta enemy_dir,x
    rts
.normal:
    jsr start_dive
    lda enemy_type_tbl,x
    bne .rts2               ; Only bosses bring escorts
    jmp start_escorts
.rts2:
    rts

; Boss X dives: the two butterflies next to it in the row below go along as
; escorts (boss i has the butterflies in slots 5+i and 6+i).
!zone start_escorts
start_escorts:
    stx esc_boss
    txa
    clc
    adc #5
    sta esc_slot
    lda #26                 ; First escort peels off a little later
    sta esc_t
    jsr .one
    inc esc_slot
    lda #32
    sta esc_t
    jsr .one
    ldx esc_boss
    rts
.one:
    ldx esc_slot
    lda enemy_state,x
    cmp #1
    bne .no                 ; Already gone or away
    jsr start_dive
    lda esc_t
    sta enemy_timer,x
    lda esc_boss
    clc
    adc #1
    sta enemy_esc,x         ; Boss index + 1
    ldy esc_boss
    lda enemy_dir,y
    sta enemy_dir,x         ; Same side as the boss
    lda #1
    sta enemy_flag,x        ; Escorts don't shoot
.no:
    rts

; ===============================================
; ENEMY BULLETS
; ===============================================

; Fire a bullet from enemy X (X preserved), drifting toward the player
!zone spawn_ebullet
spawn_ebullet:
    ldy #0
.find:
    lda eb_active,y
    beq .found
    iny
    cpy #3
    bne .find
    rts
.found:
    lda #1
    sta eb_active,y
    lda enemy_x,x
    sta eb_x,y
    lda enemy_x_msb,x
    sta eb_msb,y
    lda enemy_y,x
    clc
    adc #8
    sta eb_y,y
    lda player_x_msb
    cmp enemy_x_msb,x
    bne .far
    lda player_x
    sec
    sbc enemy_x,x
    bcs .pos
    eor #$ff
    clc
    adc #1
    cmp #16
    bcc .zero
    lda #$ff                ; Drift left
    jmp .store
.pos:
    cmp #16
    bcc .zero
    lda #1                  ; Drift right
    jmp .store
.far:
    lda #1
    bcs .store              ; Player MSB higher: right
    lda #$ff
    jmp .store
.zero:
    lda #0
.store:
    sta eb_dx,y
    rts

!zone update_ebullets
update_ebullets:
    ldx #2
.loop:
    lda eb_active,x
    beq .next
    lda eb_y,x
    clc
    adc #3
    sta eb_y,x
    cmp #250
    bcc .move
    lda #0
    sta eb_active,x
    jmp .next
.move:
    lda frame
    and #1
    bne .next               ; Sideways drift at half speed
    lda eb_dx,x
    beq .next
    bmi .left
    inc eb_x,x
    bne .next
    inc eb_msb,x
    jmp .next
.left:
    lda eb_x,x
    bne .dec_lo
    dec eb_msb,x
.dec_lo:
    dec eb_x,x
.next:
    dex
    bpl .loop
    rts
