; Messages, HUD and starfield. The C64 prints text into screen RAM and it stays; here a message is a
; string, a position and a colour in a small list that is drawn every frame until it is cleared.
; Positions keep the C64 character grid (column * 4, row * 4 pixels).

MAX_MSG = 8

msg_n:          .byte 0
msg_lo:         .res MAX_MSG
msg_hi:         .res MAX_MSG
msg_x:          .res MAX_MSG
msg_y:          .res MAX_MSG
msg_col:        .res MAX_MSG

; Number buffers for print_num / draw_bcd (print_num writes 3 characters, 'ratio' adds a '%')
num_a:          .byte 32, 32, 32, 0, 0
num_b:          .byte 32, 32, 32, 0, 0
num_c:          .byte 32, 32, 32, 0, 0
num_d:          .byte 32, 32, 0

; Add the message at zp_src; zp_dst = x, zp_dst+1 = y (pixels), txt_col = C64 colour (2 = red, else white)
msg_add:
        ldx msg_n
        cpx #MAX_MSG
        bcs @full
        lda zp_src
        sta msg_lo,x
        lda zp_src+1
        sta msg_hi,x
        lda zp_dst
        sta msg_x,x
        lda zp_dst+1
        sta msg_y,x
        lda txt_col
        sta msg_col,x
        inc msg_n
@full:  rts

msg_clear_all:
        stz msg_n
        rts

; Remove the messages with ymin <= y <= ymax (A = ymin, X = ymax)
msg_clear_y:
        sta ov_t
        stx ov_by
        ldx #0                          ; read index
        ldy #0                          ; write index
@next:  cpx msg_n
        bcs @done
        lda msg_y,x
        cmp ov_t
        bcc @keep
        cmp ov_by
        beq @drop
        bcc @drop
@keep:  lda msg_lo,x
        sta msg_lo,y
        lda msg_hi,x
        sta msg_hi,y
        lda msg_x,x
        sta msg_x,y
        lda msg_y,x
        sta msg_y,y
        lda msg_col,x
        sta msg_col,y
        iny
@drop:  inx
        bra @next
@done:  sty msg_n
        rts

clear_screen = msg_clear_all

; Blank the message rows: 16 (stage intro) and 20 (READY, FIGHTER CAPTURED)
clear_stage_row:
        lda #16*4
        ldx #20*4
        jmp msg_clear_y

clear_result:
        lda #9*4
        ldx #13*4
        jmp msg_clear_y

; Draw the zero-terminated string at zp_src in the font at zp_dst..., see draw_msgs: dr_x/dr_y = position,
; txt (zp_src) = string, fnt = font.
draw_text:
        ldy #0
@next:  lda (zp_src),y
        beq @end
        sty ov_t
        sec
        sbc #32
        jsr draw_glyph
        ldy ov_t
        iny
        bra @next
@end:   rts

; Draw glyph A (ASCII - 32) of font fnt at dr_x/dr_y and move dr_x on by 4. Keeps nothing.
draw_glyph:
        sta dr_d
        stz dr_d+1
        .repeat 4
        asl dr_d                        ; glyph = font + index * 16
        rol dr_d+1
        .endrepeat
        lda dr_d
        clc
        adc fnt
        sta dr_d
        lda dr_d+1
        adc fnt+1
        sta dr_d+1
        jsr add_sprite
        lda dr_x
        clc
        adc #4
        sta dr_x
        bcc @nc
        inc dr_x+1
@nc:    rts

draw_msgs:
        ldx #0
@msg:   cpx msg_n
        bcs @end
        phx
        lda msg_lo,x
        sta zp_src
        lda msg_hi,x
        sta zp_src+1
        lda msg_x,x
        sta dr_x
        stz dr_x+1
        lda msg_y,x
        sta dr_y
        stz dr_y+1
        ldy #<font_w
        lda msg_col,x
        cmp #2
        bne @white
        ldy #<font_r
        lda #>font_r
        bra @set
@white: lda #>font_w
@set:   sty fnt
        sta fnt+1
        jsr draw_text
        plx
        inx
        bra @msg
@end:   rts

; Draw the 3-byte BCD number at zp_src (low pair first) as 6 digits in font fnt
draw_bcd6:
        ldy #2
@byte:  phy
        lda (zp_src),y
        pha
        lsr
        lsr
        lsr
        lsr
        clc
        adc #'0' - 32
        jsr draw_glyph
        pla
        and #$0f
        clc
        adc #'0' - 32
        jsr draw_glyph
        ply
        dey
        bpl @byte
        rts

; Draw BCD byte A as two digits at zp_dst (a buffer), then advance zp_dst by 2
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
        bcc @done
        inc zp_dst+1
@done:  rts

.macro hud_text xx, yy, str, font
        lda #<str
        sta zp_src
        lda #>str
        sta zp_src+1
        lda #<font
        sta fnt
        lda #>font
        sta fnt+1
        lda #xx
        sta dr_x
        lda #yy
        sta dr_y
        stz dr_x+1
        stz dr_y+1
        jsr draw_text
.endmacro

.macro hud_bcd6 xx, yy, var
        lda #<var
        sta zp_src
        lda #>var
        sta zp_src+1
        lda #<font_w
        sta fnt
        lda #>font_w
        sta fnt+1
        lda #xx
        sta dr_x
        lda #yy
        sta dr_y
        stz dr_x+1
        stz dr_y+1
        jsr draw_bcd6
.endmacro

; Top rows: red labels on y 0..4, white numbers on y 6..10 (the formation starts at y 11).
; The HUD is one sprite (a 160 x 11 literal picture): 38 glyph sprites made the frame too long for Suzy. The picture is built again
; only when the score, the hi-score, the lives or the level change.
HUD_ROW  = 81                           ; one line of the picture: the length byte and 80 bytes (160 pixels)
HUD_ROWS = 11

; Put the string str in the picture at pixel column xx (even), line yy, in the font font
.macro hud_str xx, yy, str, font
        lda #<str
        sta zp_src
        lda #>str
        sta zp_src+1
        lda #<font
        sta fnt
        lda #>font
        sta fnt+1
        lda #<(hud_buf + yy * HUD_ROW + 1 + xx / 2)
        sta zp_dst
        lda #>(hud_buf + yy * HUD_ROW + 1 + xx / 2)
        sta zp_dst+1
        jsr hud_put
.endmacro

hud_buf:        .res HUD_ROW * HUD_ROWS + 1
hud_sig:        .byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff   ; what the picture shows now: score, hi-score, lives, level (no BCD byte is $ff)
hn:             .byte 0
hr:             .byte 0
hy:             .byte 0
htmp:           .byte 0
tg_lo:          .res 24
tg_hi:          .res 24
hs_score:       .res 7
hs_hi:          .res 7

draw_hud:
        lda score
        cmp hud_sig
        bne @build
        lda score+1
        cmp hud_sig+1
        bne @build
        lda score+2
        cmp hud_sig+2
        bne @build
        lda hiscore
        cmp hud_sig+3
        bne @build
        lda hiscore+1
        cmp hud_sig+4
        bne @build
        lda hiscore+2
        cmp hud_sig+5
        bne @build
        lda lives
        cmp hud_sig+6
        bne @build
        lda level
        cmp hud_sig+7
        beq @draw
@build: jsr hud_build
@draw:  lda #<hud_buf
        sta dr_d
        lda #>hud_buf
        sta dr_d+1
        stz dr_x
        stz dr_x+1
        stz dr_y
        stz dr_y+1
        jmp add_sprite

; Set the picture: clear it, put the labels and the numbers in
hud_build:
        lda score
        sta hud_sig
        lda score+1
        sta hud_sig+1
        lda score+2
        sta hud_sig+2
        lda hiscore
        sta hud_sig+3
        lda hiscore+1
        sta hud_sig+4
        lda hiscore+2
        sta hud_sig+5
        lda lives
        sta hud_sig+6
        lda level
        sta hud_sig+7
        lda #<hud_buf                   ; 11 lines of 81 bytes: the length, then 80 bytes of transparent pixels
        sta zp_dst
        lda #>hud_buf
        sta zp_dst+1
        ldx #HUD_ROWS
@line:  lda #HUD_ROW
        sta (zp_dst)
        ldy #HUD_ROW - 1
        lda #0
@z:     sta (zp_dst),y
        dey
        bne @z
        lda zp_dst
        clc
        adc #HUD_ROW
        sta zp_dst
        bcc @nc
        inc zp_dst+1
@nc:    dex
        bne @line
        lda #0                          ; end of the picture
        sta (zp_dst)
        hud_str 2, 0, h_score, font_r
        hud_str 32, 0, h_lives, font_r
        hud_str 62, 0, h_hi, font_r
        hud_str 134, 0, h_level, font_r
        ldx #2                          ; the two 6-digit numbers as text
        ldy #0
@sc:    lda score,x
        jsr hud_two
        dex
        bpl @sc
        lda #0
        sta hs_score,y
        ldx #2
        ldy #0
@hi:    lda hiscore,x
        jsr hud_two_hi
        dex
        bpl @hi
        lda #0
        sta hs_hi,y
        hud_str 2, 6, hs_score, font_w
        hud_str 62, 6, hs_hi, font_w
        lda lives                       ; one digit
        clc
        adc #'0'
        sta hudnum
        stz hudnum+1
        hud_str 38, 6, hudnum, font_w
        lda level                       ; two BCD digits
        pha
        lsr
        lsr
        lsr
        lsr
        clc
        adc #'0'
        sta hudnum
        pla
        and #$0f
        clc
        adc #'0'
        sta hudnum+1
        stz hudnum+2
        hud_str 142, 6, hudnum, font_w
        rts

; The two digits of BCD byte A at hs_score,y (y advances by 2)
hud_two:
        pha
        lsr
        lsr
        lsr
        lsr
        clc
        adc #'0'
        sta hs_score,y
        pla
        and #$0f
        clc
        adc #'0'
        sta hs_score+1,y
        iny
        iny
        rts

hud_two_hi:
        pha
        lsr
        lsr
        lsr
        lsr
        clc
        adc #'0'
        sta hs_hi,y
        pla
        and #$0f
        clc
        adc #'0'
        sta hs_hi+1,y
        iny
        iny
        rts

; Copy the glyphs of the string at zp_src (font fnt) into the picture at zp_dst (the first line; the next line is HUD_ROW further)
hud_put:
        ldy #0
@g:     lda (zp_src),y                  ; the address of every glyph: font + (char - 32) * 16
        beq @gd
        sec
        sbc #32
        sta dr_d
        stz dr_d+1
        .repeat 4
        asl dr_d
        rol dr_d+1
        .endrepeat
        lda dr_d
        clc
        adc fnt
        sta tg_lo,y
        lda dr_d+1
        adc fnt+1
        sta tg_hi,y
        iny
        cpy #24
        bcc @g
@gd:    sty hn
        stz hr                          ; glyph line 0..4
@row:   ldy #0                          ; char
@c:     cpy hn
        bcs @rd
        sty hy
        lda tg_lo,y
        sta dr_d
        lda tg_hi,y
        sta dr_d+1
        lda hr                          ; the two data bytes of line hr: offset 1 + 3 * hr (the first byte of a line is its length)
        asl
        clc
        adc hr
        inc
        tay
        lda (dr_d),y
        sta htmp
        iny
        lda (dr_d),y
        pha
        lda hy                          ; two bytes a character
        asl
        tay
        lda htmp
        sta (zp_dst),y
        iny
        pla
        sta (zp_dst),y
        ldy hy
        iny
        bra @c
@rd:    lda zp_dst                      ; the next line of the picture
        clc
        adc #HUD_ROW
        sta zp_dst
        bcc @nl
        inc zp_dst+1
@nl:    inc hr
        lda hr
        cmp #5
        bcc @row
        rts

hudnum:         .res 3
h_score:        .asciiz "SCORE"
h_lives:        .asciiz "LIVES"
h_hi:           .asciiz "HI-SCORE"
h_level:        .asciiz "LEVEL"

; ---- Starfield: 12 stars scroll down at 1..3 pixels a frame (not on the title) ----
star_x:         .res NUM_STARS
star_y:         .res NUM_STARS
star_v:         .res NUM_STARS

init_stars:
        ldx #NUM_STARS - 1
@s:     jsr rand
        and #$7f
        cmp #SCR_W
        bcc @xok
        sbc #SCR_W
@xok:   sta star_x,x
        jsr rand
        and #$7f
        cmp #SCR_H
        bcc @yok
        sbc #SCR_H
@yok:   sta star_y,x
        jsr rand
        and #3
        bne @v
        lda #1
@v:     sta star_v,x
        dex
        bpl @s
        rts

draw_stars:
        ldx #NUM_STARS - 1
@s:     lda paused
        bne @still                      ; Paused: the stars hold still
        lda star_y,x
        clc
        adc star_v,x
        cmp #SCR_H
        bcc @keep
        lda #0
@keep:  sta star_y,x
@still: lda star_y,x
        sta dr_y
        stz dr_y+1
        lda star_x,x
        sta dr_x
        stz dr_x+1
        ldy star_v,x
        lda stardata_lo-1,y
        sta dr_d
        lda stardata_hi-1,y
        sta dr_d+1
        phx
        jsr add_sprite
        plx
        dex
        bpl @s
        rts

; one pixel (the second nibble is pen 0: transparent), dim to bright for slow to fast
star1:  .byte 2, $c0, 0
star2:  .byte 2, $d0, 0
star3:  .byte 2, $e0, 0
stardata_lo: .byte <star1, <star2, <star3
stardata_hi: .byte >star1, >star2, >star3
