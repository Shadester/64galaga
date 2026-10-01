; Atari Lynx Galaga
        .include "lynx.inc"
        .import render_init, frame_begin, add_sprite, frame_end, flip
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
        lda frame               ; test sprite sweeping across the screen
        sta spr_x
        stz spr_x+1
        lda #46
        sta spr_y
        stz spr_y+1
        lda #<testspr
        sta spr_d
        lda #>testspr
        sta spr_d+1
        jsr add_sprite
        jsr frame_end
        jsr flip
        inc frame
        bra @loop

        .bss
frame:  .res 1

        .rodata
testspr:.repeat 10
        .byte 7, $12,$34,$56,$78,$9a,$bf
        .endrepeat
        .byte 0
