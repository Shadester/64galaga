; Atari Lynx Galaga
        .include "lynx.inc"
        .include "art.inc"
        .import render_init, frame_begin, add_sprite, add_sprite_id, frame_end, flip
        .import hud_draw, init_stars, stars_draw
        .import score, hiscore, stage
        .importzp spr_d, spr_x, spr_y
        .export frame

        .segment "STARTUP"      ; the boot loader jumps here ($0200)
start:  sei
        cld
        ldx #$ff
        txs
        jmp main

        .segment "LOWCODE"      ; empty: defdir.s sizes them
        .segment "ONCE"

        .code
main:   jsr render_init
        jsr init_stars
        lda #$80                ; demo values
        sta score
        lda #$34
        sta score+1
        lda #$00
        sta score+2
        lda #$30
        sta hiscore
        lda #$96
        sta hiscore+1
        stz hiscore+2
        lda #$01
        sta stage
        stz frame
@loop:  jsr frame_begin
        jsr stars_draw
        jsr hud_draw
        ldx #0                  ; art test: every sprite, 10 to a row
@art:   txa
        asl
        asl
        asl
        asl
        sta spr_x               ; 16 px apart
        stz spr_x+1
        lda #30
        cpx #10
        bcc @r
        lda #60
        pha
        txa
        sec
        sbc #10
        asl
        asl
        asl
        asl
        sta spr_x
        pla
@r:     sta spr_y
        stz spr_y+1
        phx
        txa
        jsr add_sprite_id
        plx
        inx
        cpx #SP_COUNT
        bne @art
        jsr frame_end
        jsr flip
        inc frame
        bra @loop

        .bss
frame:  .res 1
