; Collision detection
; ===============================================
; COLLISION DETECTION
; ===============================================

; 9-bit X overlap test
; In:  A = object X low, ov_ah = object X msb, ov_bl/ov_bh = other X
;      hit when 0 <= (a - b + ov_off) < ov_w
; Out: carry clear = hit, carry set = miss. Preserves X and Y.
!zone x_overlap
x_overlap:
    sec
    sbc ov_bl
    sta ov_t
    lda ov_ah
    sbc ov_bh
    sta ov_th
    lda ov_t
    clc
    adc ov_off
    sta ov_t
    lda ov_th
    adc #0
    bne .miss
    lda ov_t
    cmp ov_w
    rts
.miss:
    sec
    rts

!zone check_collisions
check_collisions:
    ; --- Player bullets vs enemies ---
    lda #6                  ; Bullet art centre is 3px left of enemy centre
    sta ov_off
    lda #18                 ; Hit within 9px of the alien's centre
    sta ov_w
    ldy #3
.pb_loop:
    lda pbul_active,y
    beq .pb_next
    lda pbul_y,y            ; Dead enemies have Y=$ff and never match
    sec
    sbc #8
    sta ov_by
    ldx #MAX_ENEMIES-1
.pb_enemy:
    lda enemy_y,x
    sec
    sbc ov_by
    cmp #16                 ; |enemy Y - bullet Y| < 8
    bcs .pbe_next
    lda enemy_state,x
    cmp #4
    beq .pbe_next           ; Exploding enemies can't be hit
    lda enemy_x,x
    sta ov_bl
    lda enemy_x_msb,x
    sta ov_bh
    lda pbul_msb,y
    sta ov_ah
    lda pbul_x,y
    jsr x_overlap
    bcs .pbe_next
    lda #0                  ; Hit!
    sta pbul_active,y
    inc hits
    bne .counted
    inc hits+1
.counted:
    tya
    pha
    jsr hit_enemy
    pla
    tay
    jmp .pb_next
.pbe_next:
    dex
    bpl .pb_enemy
.pb_next:
    dey
    bpl .pb_loop

    lda invuln
    beq .ships
    rts                     ; Respawn protection
.ships:
    lda #0
    sta cur_ship
.ship_loop:
    jsr check_ship
    bcs .got_hit
    lda dual
    beq .done
    lda cur_ship
    bne .done
    inc cur_ship
    bne .ship_loop
.got_hit:
    lda dual
    bne .lose_one
    jmp player_hit
.lose_one:                  ; One ship of the pair is lost, the other flies on
    lda cur_ship
    bne .keep_left
    lda player_x            ; Left ship hit: the right one takes over
    clc
    adc #16
    sta player_x
    bcc .keep_left
    inc player_x_msb
.keep_left:
    lda #0
    sta dual
    lda #90
    sta invuln
    jmp sound_player_hit
.done:
    rts

; Hit test of ship cur_ship (0 = player_x, 1 = player_x+16) against divers and
; enemy bullets. Carry set = hit (the enemy / bullet is already dealt with).
!zone check_ship
check_ship:
    lda #0
    ldy cur_ship
    beq .off
    lda #16
.off:
    clc
    adc player_x
    sta ship_xl
    lda player_x_msb
    adc #0
    sta ship_xh

    ; --- Diving enemies vs ship ---
    lda #8                  ; Ship is 16px wide
    sta ov_off
    lda #16
    sta ov_w
    lda ship_xh
    sta ov_ah
    lda frame                   ; Half of the enemies per frame (16px is a few frames of flight)
    and #1
    beq .pe_first
    lda #MAX_ENEMIES/2
    sta pe_min
    ldx #MAX_ENEMIES-1
    bne .pe_loop
.pe_first:
    lda #0
    sta pe_min
    ldx #MAX_ENEMIES/2-1
.pe_loop:
    lda enemy_state,x
    cmp #2
    beq .pe_check
    cmp #7                  ; Entering aliens ram too (waiting ones are hidden: Y=$ff)
    bne .pe_next
.pe_check:
    lda player_y
    sec
    sbc enemy_y,x
    clc
    adc #8
    cmp #16
    bcs .pe_next
    lda enemy_x,x
    sta ov_bl
    lda enemy_x_msb,x
    sta ov_bh
    lda ship_xl
    jsr x_overlap
    bcs .pe_next
    jsr set_explode         ; Enemy explodes with the ship
    cpx cap_boss
    bne .ram_done
    lda #0                  ; A capture boss rammed the ship: its captive is lost
    sta cap_state
.ram_done:
    sec
    rts
.pe_next:
    cpx pe_min
    beq .pe_done
    dex
    bpl .pe_loop
.pe_done:

    ; --- Enemy bullets vs ship ---
    lda #7
    sta ov_off
    lda #14
    sta ov_w
    ldx #2
.eb_loop:
    lda eb_active,x
    beq .eb_next
    lda eb_y,x
    sec
    sbc player_y
    clc
    adc #3
    cmp #14
    bcs .eb_next
    lda eb_x,x
    sta ov_bl
    lda eb_msb,x
    sta ov_bh
    lda ship_xl
    jsr x_overlap
    bcs .eb_next
    lda #0
    sta eb_active,x
    sec
    rts
.eb_next:
    dex
    bpl .eb_loop
    clc
    rts
