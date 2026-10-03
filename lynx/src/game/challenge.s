; Result screen of a challenge stage: number of hits and the perfect bonus

chal_result:
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
