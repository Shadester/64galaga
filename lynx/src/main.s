; Spike: palette, 50 Hz display, one Suzy sprite.
        .include "lynx.inc"

SCREEN  = $a000

        .segment "STARTUP"
start:
        sei
        cld
        ldx #$ff
        txs

        ldx #15                 ; palette: pen n = grey-ish ramp with some colour
@pal:   lda greens,x
        sta $fda0,x
        lda bluered,x
        sta $fdb0,x
        dex
        bpl @pal

        lda #$bd                ; 50 Hz: 190 us per line, 105 lines
        sta TIM0BKUP
        lda #$18
        sta TIM0CTLA
        lda #$68
        sta TIM2BKUP
        lda #$1f
        sta TIM2CTLA
        lda #$31
        sta PBKUP

        lda #<SCREEN            ; clear the frame buffer (8160 bytes)
        sta $00
        lda #>SCREEN
        sta $01
        ldy #0
        ldx #32
        lda #$00
@clr:   sta ($00),y
        iny
        bne @clr
        inc $01
        dex
        bne @clr

        lda #<SCREEN
        sta DISPADRL
        sta VIDBASL
        lda #>SCREEN
        sta DISPADRH
        sta VIDBASH
        lda #$09                ; DMA on, colour
        sta DISPCTL

        lda #1
        sta SUZYBUSEN
        lda #$f3
        sta SPRINIT
        lda #<scb
        sta SCBNEXTL
        lda #>scb
        sta SCBNEXTH
        lda #1
        sta SPRGO
@wait:  stz CPUSLEEP            ; sleep until Mikey wakes the CPU (cc65 idiom)
        lda SPRSYS
        lsr
        bcs @wait
@hang:  bra @hang

        .segment "LOWCODE"      ; empty: defdir.s sizes them
        .segment "ONCE"

        .segment "RODATA"
greens: .byte $0,$1,$2,$3,$4,$5,$6,$7,$8,$9,$a,$b,$c,$d,$e,$f
bluered:.byte $00,$11,$22,$33,$44,$55,$66,$77,$88,$99,$aa,$bb,$cc,$dd,$ee,$ff

scb:    .byte $c4               ; 4 bpp, normal sprite
        .byte $90               ; literal, reload size, reload palette
        .byte 0                 ; collision
        .word 0                 ; next SCB: none
        .word art
        .word 74                ; x
        .word 46                ; y
        .word $0100, $0100      ; 1:1 size
        .byte $01,$23,$45,$67,$89,$ab,$cd,$ef

art:    .repeat 10, i
        .byte 7, $12,$34,$56,$78,$9a,$bf
        .endrepeat
        .byte 0
