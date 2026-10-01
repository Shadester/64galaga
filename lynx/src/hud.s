; Text (3x5 sprite font), the HUD and the starfield
        .include "constants.inc"
        .import font_w, font_r, add_sprite, rand
        .importzp spr_d, spr_x, spr_y
        .export draw_text, draw_bcd, hud_draw, init_stars, stars_draw
        .export score, hiscore, stage

        .zeropage
txt:    .res 2                  ; draw_text: string pointer
fnt:    .res 2                  ; draw_text: font (font_w or font_r)
ch:     .res 1

        .bss
score:  .res 3                  ; BCD, low pair first (as on the C64)
hiscore: .res 3
stage:  .res 1                  ; BCD
starx:  .res NUM_STARS
stary:  .res NUM_STARS
starv:  .res NUM_STARS          ; 1..3 pixels a frame; also picks the brightness

        .code
; Draw the zero-terminated string at txt in font fnt, at spr_x/spr_y (4 pixels a character).
draw_text:
        ldy #0
@next:  lda (txt),y
        beq @end
        sty ch                  ; ch = index, keep Y for the loop
        sec
        sbc #32
        sta spr_d
        lda #0
        sta spr_d+1
        .repeat 4
        asl spr_d               ; glyph = font + (c - 32) * 16
        rol spr_d+1
        .endrepeat
        lda spr_d
        clc
        adc fnt
        sta spr_d
        lda spr_d+1
        adc fnt+1
        sta spr_d+1
        jsr add_sprite
        lda spr_x
        clc
        adc #4
        sta spr_x
        bcc @nc
        inc spr_x+1
@nc:    ldy ch
        iny
        bra @next
@end:   rts

; Draw the 3-byte BCD number at txt (low pair first) as 6 digits, in font fnt.
draw_bcd:
        ldy #2
@byte:  lda (txt),y
        pha
        lsr
        lsr
        lsr
        lsr
        jsr @digit
        pla
        and #$0f
        jsr @digit
        dey
        bpl @byte
        rts
@digit: phy
        clc
        adc #'0' - 32
        sta spr_d
        lda #0
        sta spr_d+1
        .repeat 4
        asl spr_d
        rol spr_d+1
        .endrepeat
        lda spr_d
        clc
        adc fnt
        sta spr_d
        lda spr_d+1
        adc fnt+1
        sta spr_d+1
        jsr add_sprite
        lda spr_x
        clc
        adc #4
        sta spr_x
        bcc @nc
        inc spr_x+1
@nc:    ply
        rts

.macro text_at xx, yy, font, str
        lda #<str
        sta txt
        lda #>str
        sta txt+1
        lda #<font
        sta fnt
        lda #>font
        sta fnt+1
        lda #xx
        sta spr_x
        lda #yy
        sta spr_y
        stz spr_x+1
        stz spr_y+1
        jsr draw_text
.endmacro

.macro bcd_at xx, yy, var
        lda #<var
        sta txt
        lda #>var
        sta txt+1
        lda #<font_w
        sta fnt
        lda #>font_w
        sta fnt+1
        lda #xx
        sta spr_x
        lda #yy
        sta spr_y
        stz spr_x+1
        stz spr_y+1
        jsr draw_bcd
.endmacro

; Top rows: labels in red on y 0..4, numbers in white on y 6..10 (the formation starts at y 11).
hud_draw:
        text_at 2, 0, font_r, s_score
        text_at 62, 0, font_r, s_hi
        text_at 134, 0, font_r, s_stage
        bcd_at 2, 6, score
        bcd_at 62, 6, hiscore
        lda stage               ; two BCD digits
        pha
        lsr
        lsr
        lsr
        lsr
        clc
        adc #'0'
        sta stagetxt
        pla
        and #$0f
        clc
        adc #'0'
        sta stagetxt+1
        text_at 142, 6, font_w, stagetxt
        rts

init_stars:
        ldx #NUM_STARS - 1
@s:     jsr rand
        sta starx,x
        cmp #SCR_W
        bcc @xok
        sbc #SCR_W
        sta starx,x
@xok:   jsr rand
        and #$7f
        cmp #SCR_H
        bcc @yok
        sbc #SCR_H
@yok:   sta stary,x
        jsr rand
        and #3
        bne @v
        lda #1
@v:     sta starv,x
        dex
        bpl @s
        rts

; Move every star down by its speed and add it to the frame.
stars_draw:
        ldx #NUM_STARS - 1
@s:     lda stary,x
        clc
        adc starv,x
        cmp #SCR_H
        bcc @keep
        lda #0
@keep:  sta stary,x
        sta spr_y
        stz spr_y+1
        lda starx,x
        sta spr_x
        stz spr_x+1
        ldy starv,x
        lda stardata_lo-1,y
        sta spr_d
        lda stardata_hi-1,y
        sta spr_d+1
        phx
        jsr add_sprite
        plx
        dex
        bpl @s
        rts

        .rodata
s_score: .asciiz "SCORE"
s_hi:    .asciiz "HI-SCORE"
s_stage: .asciiz "STAGE"

; one pixel (the second nibble is pen 0: transparent), dim to bright for slow to fast
star1:  .byte 2, $c0, 0
star2:  .byte 2, $d0, 0
star3:  .byte 2, $e0, 0
stardata_lo: .byte <star1, <star2, <star3
stardata_hi: .byte >star1, >star2, >star3

        .bss
stagetxt: .res 3
