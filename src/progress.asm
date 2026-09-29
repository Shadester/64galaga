; Hits, scoring, player death and stage progression
; Player bullet hit enemy X: boss survives one hit, everything else dies
!zone hit_enemy
hit_enemy:
    dec enemy_hp,x
    beq .kill
    lda enemy_hitcol_tbl,x  ; Damaged boss changes colour
    sta spr_c,x
    jmp sound_shoot
.kill:
    stx hit_idx
    cpx cap_boss
    bne .plain
    lda cap_state
    beq .plain
    jsr boss_killed
    ldx hit_idx
.plain:
    ldy enemy_type_tbl,x
    lda enemy_state,x
    cmp #2
    beq .dive_pts
    lda pts_form_mid,y
    tax
    lda pts_form_lo,y
    jmp .add
.dive_pts:
    cpy #0
    bne .std_dive
    jsr count_escorts       ; Diving boss: 400 / 800 / 1600 with 0 / 1 / 2 escorts alive
    tay
    ldx esc_pts_mid,y
    lda #0
    jmp .add
.std_dive:
    lda pts_dive_mid,y
    tax
    lda pts_dive_lo,y
.add:
    jsr add_score
    ldx hit_idx
    jsr set_explode
    jmp sound_explosion

; Number of escorts of boss hit_idx still flying (A, 0..2); X = hit_idx
!zone count_escorts
count_escorts:
    lda hit_idx
    clc
    adc #1
    sta esc_cmp
    lda #0
    sta esc_cnt
    ldx #MAX_ENEMIES-1
.loop:
    lda enemy_esc,x
    cmp esc_cmp
    bne .next
    lda enemy_state,x
    cmp #2
    beq .yes
    cmp #3
    bne .next
.yes:
    inc esc_cnt
.next:
    dex
    bpl .loop
    ldx hit_idx
    lda esc_cnt
    rts

; Add BCD points to the 6-digit score. In: A = low pair, X = middle pair
!zone add_score
add_score:
    sed
    clc
    adc score
    sta score
    txa
    adc score+1
    sta score+1
    lda score+2
    adc #0
    sta score+2
    cld
    lda score+2             ; Bonus ship at 20,000, 70,000, then every 70,000
    cmp next_bonus
    bcc .rts
    lda next_bonus
    cmp #2
    bne .repeat
    lda #7
    bne .set_next
.repeat:
    sed
    clc
    adc #7
    cld
.set_next:
    sta next_bonus
    lda lives
    cmp #9
    bcs .rts
    inc lives
    lda #jin_bonus-jin_data
    jmp play_jingle
.rts:
    rts

!zone player_hit
player_hit:
    lda #GS_DYING
    sta game_state
    lda #63
    sta dying_timer
    dec lives
    lda #0
    sta eb_active
    sta eb_active+1
    sta eb_active+2
    sta pbul_active
    sta pbul_active+1
    sta pbul_active+2
    sta pbul_active+3
    jsr sound_player_hit
    jmp sound_player_die

; ===============================================
; LEVEL PROGRESSION
; ===============================================

; All enemies gone (and none still exploding)? Start the next stage.
!zone check_level_complete
check_level_complete:
    lda cap_state
    cmp #5
    beq .rts                ; A rescued ship is still on its way down
    ldx #MAX_ENEMIES-1
.loop:
    lda enemy_state,x
    bne .rts
    dex
    bpl .loop
    jmp next_level
.rts:
    rts

!zone next_level
next_level:
    sed
    lda level
    clc
    adc #1
    sta level
    cld
    lda diff
    cmp #8
    bcs .capped
    inc diff
.capped:
    jmp enter_result            ; Shots / hits screen, then the next stage
