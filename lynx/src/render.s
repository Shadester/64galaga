; Frame rendering: a chain of Suzy sprite control blocks (SCBs) is rebuilt every frame, drawn into the
; back buffer, and the buffers swap in the vertical blank. Replaces the C64 raster multiplexer.
        .include "lynx.inc"
        .include "constants.inc"
        .export pal_game, pal_title, render_init, frame_begin, add_sprite, add_sprite_id, frame_end, flip, rand
        .import sprite_lo, sprite_hi, sprite_dx, sprite_dy, title_pal_g, title_pal_br
        .exportzp dr_d, dr_x, dr_y, rnd
        .export scbs
.ifdef PROFILE
        .export late_frames, scb_peak, scb_over
.endif

        .zeropage
wp:     .res 2                  ; next free SCB
dr_d:  .res 2                  ; add_sprite arguments (keep this order): data, x, y (signed screen pixels)
dr_x:  .res 2
dr_y:  .res 2
back:   .res 1                  ; high byte of the buffer that is being drawn
rnd:    .res 1

        .bss
scbs:   .res BG_SIZE + SCB_SIZE * MAX_SCB
scbs_end:
scb_room: .res 1             ; SCBs left in the pool
scb_endp: .res 2            ; the last SCB of the last frame (its next pointer was cut), 0: none
.ifdef PROFILE
late_frames: .res 2             ; -DPROFILE: frames that were not finished at the vertical blank (the game runs slower then)
scb_peak:    .res 1             ; most sprites in one frame (without the background)
scb_cnt:     .res 1
scb_over:    .res 2             ; sprites that did not fit in the SCB pool
.endif

        .code
; Palette, 50 Hz timing, display DMA, Suzy.
render_init:
        jsr pal_game
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
        jmp scb_init

pal_game:
        ldx #15
@pal:   lda palg,x
        sta $fda0,x
        lda palbr,x
        sta $fdb0,x
        dex
        bpl @pal
        rts

pal_title:
        ldx #15
@pal:   lda title_pal_g,x
        sta $fda0,x
        lda title_pal_br,x
        sta $fdb0,x
        dex
        bpl @pal
        rts

; 8-bit Galois LFSR (the C64 game's), result in A
rand:   lda rnd
        asl
        bcc @done
        eor #$1d
@done:  sta rnd
        rts

; The SCB pool is made once (scb_init): every SCB has its control bytes, its next pointer (the SCB after it) and its size already. A sprite
; (add_sprite) only stores its data address, x and y. frame_end cuts the chain after the last SCB of the frame (next = 0); the next
; frame_begin puts that pointer back. The background SCB (which fills the screen with pen 0 and loads the pen map) is copied once.
scb_init:
        ldx #BG_SIZE - 1
@bg:    lda bgscb,x
        sta scbs,x
        dex
        bpl @bg
        lda #<(scbs + BG_SIZE)
        sta wp
        lda #>(scbs + BG_SIZE)
        sta wp+1
        ldx #MAX_SCB
@one:   ldy #0
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
        ldy #11                 ; size 1:1
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
        bcc @n
        inc wp+1
@n:     dex
        bne @one
        stz scb_endp+1
        rts

; Start a frame: put back the pointer that frame_end cut, and start at the first sprite SCB.
frame_begin:
.ifdef PROFILE
        stz scb_cnt
.endif
        lda scb_endp+1
        beq @fresh
        sta wp+1
        lda scb_endp
        sta wp
        ldy #3
        clc
        adc #SCB_SIZE
        sta (wp),y
        iny
        lda wp+1
        adc #0
        sta (wp),y
@fresh: lda #<(scbs + BG_SIZE)
        sta wp
        lda #>(scbs + BG_SIZE)
        sta wp+1
        lda #MAX_SCB
        sta scb_room
        rts

; Append a sprite: dr_d (literal 4 bpp data), dr_x, dr_y. Pen map is kept from the background SCB.
add_sprite:
        lda scb_room            ; the pool is full: drop the sprite (it would overwrite what follows the SCBs)
        bne @room
.ifdef PROFILE
        inc scb_over
        bne @rts
        inc scb_over+1
.endif
@rts:   rts
@room:  dec scb_room
.ifdef PROFILE
        inc scb_cnt
.endif
        ldy #5
        lda dr_d                ; data, x, y
        sta (wp),y
        iny
        lda dr_d+1
        sta (wp),y
        iny
        lda dr_x
        sta (wp),y
        iny
        lda dr_x+1
        sta (wp),y
        iny
        lda dr_y
        sta (wp),y
        iny
        lda dr_y+1
        sta (wp),y
        lda wp
        clc
        adc #SCB_SIZE
        sta wp
        bcc @ok
        inc wp+1
@ok:    rts

; Append sprite A (an SP_ id from art.inc) at dr_x/dr_y = the C64 box position / 2. Adds the sprite's crop
; offset to dr_x/dr_y (callers set them again for the next sprite).
add_sprite_id:
        tax
        lda sprite_lo,x
        sta dr_d
        lda sprite_hi,x
        sta dr_d+1
        lda sprite_dx,x
        clc
        adc dr_x
        sta dr_x
        bcc @x
        inc dr_x+1
@x:     lda sprite_dy,x
        clc
        adc dr_y
        sta dr_y
        bcc @y
        inc dr_y+1
@y:     jmp add_sprite

; End the chain and let Suzy draw it into the back buffer (CPU sleeps until done).
frame_end:
        lda wp                  ; last SCB: next = 0
        sec
        sbc #SCB_SIZE
        sta wp
        lda wp+1
        sbc #0
        sta wp+1
        sta scb_endp+1          ; frame_begin puts this next pointer back
        lda wp
        sta scb_endp
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
.ifdef PROFILE
        lda TIM2CTLB            ; the frame was finished late if the vertical blank has come already
        and #$08
        beq @on_time
        inc late_frames
        bne @on_time
        inc late_frames+1
@on_time:
        lda scb_cnt
        cmp scb_peak
        bcc @no_peak
        sta scb_peak
@no_peak:
.endif
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
palg:   .byte $0,$f,$2,$6,$c,$f,$d,$4,$9,$a,$5,$9,$4,$7,$a,$8
palbr:  .byte $00,$ff,$0e,$f4,$f0,$0f,$40,$ea,$0f,$aa,$55,$fa,$44,$77,$aa,$cf

bgscb:  .byte $c0               ; 4 bpp, background (pen 0 is drawn)
        .byte $90               ; literal, reload size, load pen map
        .byte $20
        .word scbs + BG_SIZE    ; patched by frame_end when nothing follows
        .word bgdata
        .word 0, 0
        .word $a000, $6600      ; the 1 source pixel (the last pixel of a line is not drawn) x160 wide, 1 line x102 high
        .byte $01,$23,$45,$67,$89,$ab,$cd,$ef
bgdata: .byte 2, $00, 0
