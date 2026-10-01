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
