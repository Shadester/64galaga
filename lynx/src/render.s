; Frame rendering: a chain of Suzy sprite control blocks (SCBs) is rebuilt every frame, drawn into the
; back buffer, and the buffers swap in the vertical blank. Replaces the C64 raster multiplexer.
        .include "lynx.inc"
        .include "constants.inc"
        .export render_init, frame_begin, add_sprite, frame_end, flip, rand
        .exportzp spr_d, spr_x, spr_y, rnd
        .export scbs

        .zeropage
wp:     .res 2                  ; next free SCB
spr_d:  .res 2                  ; add_sprite arguments (keep this order): data, x, y (signed screen pixels)
spr_x:  .res 2
spr_y:  .res 2
back:   .res 1                  ; high byte of the buffer that is being drawn
rnd:    .res 1

        .bss
scbs:   .res BG_SIZE + SCB_SIZE * MAX_SCB

        .code
; Palette, 50 Hz timing, display DMA, Suzy.
render_init:
        ldx #15
@pal:   lda palg,x
        sta $fda0,x
        lda palbr,x
        sta $fdb0,x
        dex
        bpl @pal
        lda #$bd                ; 50 Hz: 190 us per line, 105 lines
        sta TIM0BKUP
        lda #$18
        sta TIM0CTLA
        lda #$68
        sta TIM2BKUP
        lda #$1f                ; no interrupt: a pending IRQ would wake the CPU from CPUSLEEP while Suzy draws
        sta TIM2CTLA
        lda #$31
        sta PBKUP
        lda #<BUF0
        sta DISPADRL
        lda #>BUF0
        sta DISPADRH
        lda #$09                ; DMA on, colour
        sta DISPCTL
        lda #>BUF1              ; draw into the other one
        sta back
        lda #1
        sta SUZYBUSEN
        lda #$f3
        sta SPRINIT
        lda #$20                ; no collision buffer (COLLBAS would be written otherwise)
        sta SPRSYS
        lda #$a5
        sta rnd
        rts

; 8-bit Galois LFSR (the C64 game's), result in A
rand:   lda rnd
        asl
        bcc @done
        eor #$1d
@done:  sta rnd
        rts

; Start a frame: the first SCB fills the screen with pen 0 (and loads the pen map).
frame_begin:
        ldx #BG_SIZE - 1
@cp:    lda bgscb,x
        sta scbs,x
        dex
        bpl @cp
        lda #<(scbs + BG_SIZE)
        sta wp
        lda #>(scbs + BG_SIZE)
        sta wp+1
        rts

; Append a sprite: spr_d (literal 4 bpp data), spr_x, spr_y. Pen map is kept from the background SCB.
add_sprite:
        ldy #0
        lda #$c4                ; 4 bpp, normal sprite (pen 0 transparent)
        sta (wp),y
        iny
        lda #$98                ; literal, reload size, keep pen map
        sta (wp),y
        iny
        lda #$20                ; no collision
        sta (wp),y
        iny
        lda wp                  ; next SCB follows directly
        clc
        adc #SCB_SIZE
        sta (wp),y
        iny
        lda wp+1
        adc #0
        sta (wp),y
        ldx #0
@arg:   iny
        lda spr_d,x             ; data, x, y
        sta (wp),y
        inx
        cpx #6
        bne @arg
        iny                     ; size 1:1
        lda #0
        sta (wp),y
        iny
        lda #1
        sta (wp),y
        iny
        lda #0
        sta (wp),y
        iny
        lda #1
        sta (wp),y
        lda wp
        clc
        adc #SCB_SIZE
        sta wp
        bcc @ok
        inc wp+1
@ok:    rts

; End the chain and let Suzy draw it into the back buffer (CPU sleeps until done).
frame_end:
        lda wp                  ; last SCB: next = 0
        sec
        sbc #SCB_SIZE
        sta wp
        lda wp+1
        sbc #0
        sta wp+1
        ldy #3
        lda #0
        sta (wp),y
        iny
        sta (wp),y
        lda #0
        sta VIDBASL
        lda back
        sta VIDBASH
        lda #<scbs
        sta SCBNEXTL
        lda #>scbs
        sta SCBNEXTH
        lda #1
        sta SPRGO
@wait:  stz CPUSLEEP
        lda SPRSYS
        lsr
        bcs @wait
        stz SDONEACK            ; acknowledge "Suzy done", or the next frame's sleep never ends
        rts

; Wait for the vertical blank, show the finished buffer, draw into the other one next.
flip:
@vbl:   lda TIM2CTLB            ; bit 3: timer done (set at the end of every frame)
        and #$08
        beq @vbl
        stz TIM2CTLB
        lda back
        sta DISPADRH
        eor #BUF_FLIP
        sta back
        rts

        .rodata
; pen: 0 black, 1 white, 2 red, 3 blue, 4 cyan, 5 yellow, 6 green, 7 purple, 8 orange, 9 light grey,
;      a dark grey, b light blue, c..e star greys, f pink
palg:   .byte $0,$f,$2,$4,$c,$f,$d,$3,$9,$a,$5,$9,$4,$7,$a,$7
palbr:  .byte $00,$ff,$0e,$f4,$0a,$0f,$04,$d5,$0f,$aa,$55,$fa,$44,$77,$aa,$dc

bgscb:  .byte $c0               ; 4 bpp, background (pen 0 is drawn)
        .byte $90               ; literal, reload size, load pen map
        .byte $20
        .word scbs + BG_SIZE    ; patched by frame_end when nothing follows
        .word bgdata
        .word 0, 0
        .word $a000, $6600      ; the 1 source pixel (the last pixel of a line is not drawn) x160 wide, 1 line x102 high
        .byte $01,$23,$45,$67,$89,$ab,$cd,$ef
bgdata: .byte 2, $00, 0
