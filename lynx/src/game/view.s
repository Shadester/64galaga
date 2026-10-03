; Draw every visible virtual sprite. C64 sprite coordinates (x 24.., y 50.., 9-bit x) become Lynx screen
; pixels: (x - 24) / 2, (y - 50) / 2, as signed 16-bit numbers (aliens enter above and beside the screen).
draw_sprites:
        ldx #0
@loop:  lda spr_y,x
        cmp #$ff
        beq @next
        sec
        sbc #50
        sta dr_y
        lda #0
        sbc #0
        sta dr_y+1
        cmp #$80                        ; arithmetic shift right
        ror dr_y+1
        ror dr_y
        lda spr_x,x
        sec
        sbc #SCREEN_LEFT
        sta dr_x
        lda spr_x_msb,x
        sbc #0
        sta dr_x+1
        cmp #$80
        ror dr_x+1
        ror dr_x
        lda spr_f,x
        phx
        jsr add_sprite_id
        plx
@next:  inx
        cpx #MAX_SPRITES
        bne @loop
        rts

; The tractor beam: beam_len rows of checkerboard cells under boss cap_boss while it is on (cap_state 2 or 3).
; The C64 writes characters; here it is drawn every frame.
draw_beam:
        lda cap_state
        cmp #2
        beq @on
        cmp #3
        bne @rts
@on:    lda beam_len
        beq @rts
        ldx cap_boss
        lda enemy_x,x               ; Column of the boss centre: (x - 18) / 8
        sec
        sbc #18
        sta bd_col
        lda enemy_x_msb,x
        sbc #0
        lsr
        ror bd_col
        lsr bd_col
        lsr bd_col
        lda enemy_y,x               ; First row: just under the boss
        sec
        sbc #36
        lsr
        lsr
        lsr
        sta bd_row0
        lda frame                   ; Colour phase, every 4 frames
        lsr
        lsr
        and #3
        sta bd_n
        stz bd_r
@row:   ldx bd_r
        cpx beam_len
        bcs @rts
        lda bd_col                  ; x = (column - half width) * 4
        sec
        sbc hw_tbl,x
        sta dr_x
        lda #0
        sbc #0
        sta dr_x+1
        asl dr_x
        rol dr_x+1
        asl dr_x
        rol dr_x+1
        lda bd_row0                 ; y = (first row + row) * 4
        clc
        adc bd_r
        asl
        asl
        sta dr_y
        stz dr_y+1
        txa                         ; sprite = SP_BEAM + row * 4 + phase
        asl
        asl
        clc
        adc bd_n
        clc
        adc #SP_BEAM
        jsr add_sprite_id
        inc bd_r
        bra @row
@rts:   rts
