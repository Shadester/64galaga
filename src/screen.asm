; Screen, colours, text printing, HUD and the starfield
; ===============================================
; SCREEN & COLOR SETUP
; ===============================================

!zone clear_screen
clear_screen:
    ldx #0
    lda #$20
.loop:
    sta SCREEN_RAM,x
    sta SCREEN_RAM+$100,x
    sta SCREEN_RAM+$200,x
    sta SCREEN_RAM+$2e8,x
    inx
    bne .loop
    rts

; Blank the message rows: 16 (stage intro) and 20 (READY, FIGHTER CAPTURED)
!zone clear_stage_row
clear_stage_row:
    ldx #39
    lda #$20
.loop:
    sta SCREEN_RAM+16*40,x
    sta SCREEN_RAM+20*40,x
    dex
    bpl .loop
    rts

!zone setup_colors
setup_colors:
    lda #0
    sta BG_COLOR
    sta BORDER_COLOR
    ldx #0
    lda #3
.color_loop:
    sta COLOR_RAM,x
    sta COLOR_RAM+$100,x
    sta COLOR_RAM+$200,x
    sta COLOR_RAM+$2e8,x
    inx
    bne .color_loop
    rts

; Print zero-terminated string at zp_src to zp_dst in colour txt_col
!zone print_str
print_str:
    lda zp_dst
    sta zp_col
    lda zp_dst+1
    clc
    adc #>(COLOR_RAM-SCREEN_RAM)
    sta zp_col+1
    ldy #0
.loop:
    lda (zp_src),y
    beq .done
    sta (zp_dst),y
    lda txt_col
    sta (zp_col),y
    iny
    bne .loop
.done:
    rts

; Draw BCD byte A as two digits at zp_dst, then advance zp_dst by 2
!zone draw_bcd
draw_bcd:
    pha
    lsr
    lsr
    lsr
    lsr
    clc
    adc #48
    ldy #0
    sta (zp_dst),y
    pla
    and #$0f
    clc
    adc #48
    iny
    sta (zp_dst),y
    lda zp_dst
    clc
    adc #2
    sta zp_dst
    bcc .done
    inc zp_dst+1
.done:
    rts

!zone draw_labels
draw_labels:
    +print lives_text, SCREEN_RAM, 3
    +print hi_text, SCREEN_RAM+27, 3
    +print level_text, SCREEN_RAM+40, 3
    +print score_text, SCREEN_RAM+40+24, 3
    rts

!zone draw_hud
draw_hud:
    +setdst SCREEN_RAM+40+30
    lda score+2
    jsr draw_bcd
    lda score+1
    jsr draw_bcd
    lda score
    jsr draw_bcd

    +setdst SCREEN_RAM+30
    lda hiscore+2
    jsr draw_bcd
    lda hiscore+1
    jsr draw_bcd
    lda hiscore
    jsr draw_bcd

    lda lives
    clc
    adc #48
    sta SCREEN_RAM+7

    +setdst SCREEN_RAM+40+7
    lda level
    jmp draw_bcd

; ===============================================
; STARFIELD
; ===============================================
; Stars are '.' characters that scroll down through the free screen rows.
; They only draw on blank cells and only erase their own '.', so text is safe.

!zone init_stars
init_stars:
    ldx #NUM_STARS-1
.loop:
    jsr rand
    and #$3f
    cmp #40
    bcc .col_ok
    sbc #40
.col_ok:
    sta star_col,x
    jsr rand
    and #$1f
    cmp #22
    bcc .row_ok
    sbc #22
.row_ok:
    clc
    adc #3
    sta star_row,x
    jsr rand
    and #3
    clc
    adc #2                      ; 2..5 frames per row step
    sta star_spd,x
    sta star_cnt,x
    dex
    bpl .loop
    rts

; Point zp_dst / zp_col at the screen / colour cell of star X
!zone star_addr
star_addr:
    ldy star_row,x
    lda row_lo,y
    clc
    adc star_col,x
    sta zp_dst
    sta zp_col
    lda row_hi,y
    adc #0
    sta zp_dst+1
    clc
    adc #>(COLOR_RAM-SCREEN_RAM)
    sta zp_col+1
    rts

!zone update_stars
update_stars:
    ldx #NUM_STARS-1
.loop:
    dec star_cnt,x
    bne .next
    lda star_spd,x
    sta star_cnt,x
    jsr star_addr
    ldy #0
    lda (zp_dst),y
    cmp #$2e
    bne .moved
    lda #$20
    sta (zp_dst),y
.moved:
    inc star_row,x
    lda star_row,x
    cmp #25
    bcc .draw
    lda #3
    sta star_row,x
.draw:
    jsr star_addr
    ldy #0
    lda (zp_dst),y
    cmp #$20
    bne .next
    lda #$2e
    sta (zp_dst),y
    ldy star_spd,x
    lda star_clr_tbl,y
    ldy #0
    sta (zp_col),y
.next:
    dex
    bpl .loop
    rts

; 8-bit Galois LFSR, result in A
!zone rand
rand:
    lda rnd
    asl
    bcc .done
    eor #$1d
.done:
    sta rnd
    rts
