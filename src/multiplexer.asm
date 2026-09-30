; Raster interrupt sprite multiplexer
; ===============================================
; WAIT FOR IRQ
; ===============================================

; Wait for IRQ to finish processing sprites
!zone wait_for_irq
wait_for_irq:
.wait_loop:
    lda spr_update_flag
    bne .wait_loop
    rts

; ===============================================
; SPRITE MULTIPLEXER SYSTEM
; ===============================================
; Raster interrupt-based multiplexer

; Initialize the multiplexer
!zone init_multiplexer
init_multiplexer:
    lda #0
    sta sorted_sprites
    sta spr_update_flag

    ; Init order table with 0,1,2,3... order; all virtual sprites hidden
    ldx #MAX_SPRITES-1
.init_order:
    txa
    sta sort_order,x
    lda #$ff
    sta spr_y,x
    dex
    bpl .init_order
    rts

; Initialize raster interrupt system
!zone init_raster
init_raster:
    sei
    lda #<irq1
    sta $0314
    lda #>irq1
    sta $0315
    lda #$7f                ; CIA interrupt off
    sta $dc0d
    lda #$01                ; Raster interrupt on
    sta $d01a
    lda #27                 ; High bit of IRQ position = 0
    sta $d011
    lda #IRQ1_LINE          ; Sorting interrupt line
    sta $d012
    lda $dc0d               ; Acknowledge IRQ
    cli
    rts

; IRQ1: Sorting interrupt (runs at bottom of screen)
!zone irq1
irq1:
    cld                     ; IRQ may hit inside score sed/cld window
    dec $d019               ; Acknowledge raster interrupt

    ; Move all sprites to bottom to prevent glitches
    lda #$ff
    sta $d001
    sta $d003
    sta $d005
    sta $d007
    sta $d009
    sta $d00b
    sta $d00d
    sta $d00f

    ; Check if new sprites need sorting
    lda spr_update_flag
    beq .check_display

    lda #0
    sta spr_update_flag
    ; Sort sprites by Y coordinate (also counts the visible ones)
    jsr sort_sprites

.check_display:
    ; Always display sorted sprites each frame
    ldx sorted_sprites
    beq .no_sprites_at_all   ; If zero sprites, skip display
    cpx #9
    bcc .not_more_than_8
    ldx #8
.not_more_than_8:
    lda d015_table,x
    sta $d015

    ; Set up display interrupt
    lda #0
    sta spr_irq_counter
    lda #<irq2
    sta $0314
    lda #>irq2
    sta $0315
    lda $d011               ; Sorting can outlast the bottom border: if the raster is
    bmi .arm                ; already past the first sprite's line, start right away
    lda $d012
    cmp #IRQ1_LINE
    bcs .arm
    cmp sort_line
    bcc .arm
    jmp irq2_direct
.arm:
    lda sort_line           ; Start the display interrupt at the first sprite
    sta $d012
    jmp $ea81               ; Return from IRQ

.no_sprites_at_all:
    lda #0
    sta $d015               ; Disable all sprites
    jmp $ea81               ; Return from IRQ

; Sort sprites by Y coordinate
; Insertion sort on the order table. It starts from last frame's order, so
; most entries are already in place: sort_prev is the Y of the sorted prefix's
; last entry, and only a smaller Y shifts the larger ones up to make room.
!zone sort_sprites
sort_sprites:
    ldy sort_order
    lda spr_y,y
    sta sort_prev
    ldx #0
.outer:
    ldy sort_order+1,x
    lda spr_y,y
    cmp sort_prev
    bcs .in_place               ; Not smaller: stays (equal Y keeps its order)
    sta sort_ky
    sty sort_key
    stx sort_temp_x
.shift:
    lda sort_order,x
    sta sort_order+1,x
    dex
    bmi .first
    ldy sort_order,x
    lda sort_ky
    cmp spr_y,y
    bcc .shift                  ; Still smaller than the next one down
    lda sort_key
    sta sort_order+1,x
    jmp .placed
.first:
    lda sort_key
    sta sort_order
.placed:
    ldx sort_temp_x
    jmp .next
.in_place:
    sta sort_prev
.next:
    inx
    cpx #MAX_SPRITES-1
    bcc .outer

    ; Build the list of sprites to show: virtual index, Y and the raster line from which
    ; each may be loaded. Sprite i reuses the hardware sprite of i-8, which is drawing
    ; for SPR_LINES lines from its Y: loading earlier than ART_TAIL lines after that Y
    ; would re-skin the rest of it, and a sprite starting before the old one ends
    ; cannot be shown at all (more than 8 in a band): it is left out this frame.
!zone sort_copy
    lda #0
    sta sort_p              ; Position in sort_order
    tax                     ; X = slot in the list of sprites to show
.loop:
    ldy sort_p
    cpy #MAX_SPRITES
    bcs .end
    lda sort_order,y
    inc sort_p
    tay                     ; Y = virtual sprite
    lda spr_y,y
    cmp #$ff                ; Hidden sprites sort last: stop at the first one
    beq .end
    cpx #8
    bcc .far                ; The first 8 have a hardware sprite to themselves
    sec
    sbc sort_spr_y-8,x      ; Lines after the previous user's Y
    cmp #SPR_LINES
    bcs .reuse
    cpy #VS_PLAYER
    beq .far                ; The ship is always shown, even if it cuts up another sprite
    jmp .loop               ; Left out
.reuse:
    cmp #ART_TAIL+IRQ_LEAD
    bcs .far
    lda sort_spr_y-8,x      ; Wait until the previous user's art is drawn
    clc
    adc #ART_TAIL
    jmp .set_line
.far:
    lda spr_y,y             ; Normal case: IRQ_LEAD lines early (not before line 0)
    sec
    sbc #IRQ_LEAD
    bcs .set_line
    lda #0
.set_line:
    sta sort_line,x
    lda spr_y,y
    sta sort_spr_y,x
    tya
    sta sort_vi,x
    inx
    cpx #MAX_SPRITES
    bcs .end
    jmp .loop
.end:
    stx sorted_sprites
    lda #$ff
    sta sort_line,x         ; End marker
    rts

; IRQ2: Display interrupt (runs multiple times per frame)
!zone irq2
irq2:
    cld
    dec $d019               ; Acknowledge raster interrupt

!zone irq2_direct
irq2_direct:
    ldy spr_irq_counter     ; Get sprite index

    ; Continue with the sprite in the code block of its hardware sprite (i mod 8)
!zone irq2_dispatch
irq2_dispatch:
    tya
    and #7
    tax
    lda blk_hi,x
    pha
    lda blk_lo,x
    pha
    rts

; Load the sprite at sorted index Y onto hardware sprite .k, then go on with the next
; one (hardware sprite .k+1) if its line has come. X = virtual sprite.
!macro sprite_block .k {
    lda sort_line,y
    cmp $d012
    bcc .go                 ; Line passed already (IRQ ran late)
    beq .go
    jmp irq2_wait           ; Still ahead, or the end marker
.go:
    ldx sort_vi,y
    lda spr_y,x
    sta $d001+2*.k
    lda spr_x,x
    sta $d000+2*.k
    lda spr_x_msb,x
    beq .msb0
    lda $d010
    ora #1<<.k
    bne .msb_st
.msb0:
    lda $d010
    and #$ff-(1<<.k)
.msb_st:
    sta $d010
    lda spr_f,x
    sta SPRITE_PTR+.k
    cmp #SPR_PLAYER         ; The ship is hires, all others multicolor
    beq .hires
    lda SPRITE_MCOLOR_EN
    ora #1<<.k
    bne .mc_st
.hires:
    lda SPRITE_MCOLOR_EN
    and #$ff-(1<<.k)
.mc_st:
    sta SPRITE_MCOLOR_EN
    lda spr_c,x
    sta SPRITE_COLORS+.k
    iny
}

!zone irq2_blocks
blk0:
    +sprite_block 0
blk1:
    +sprite_block 1
blk2:
    +sprite_block 2
blk3:
    +sprite_block 3
blk4:
    +sprite_block 4
blk5:
    +sprite_block 5
blk6:
    +sprite_block 6
blk7:
    +sprite_block 7
    jmp blk0

blk_lo: !byte <(blk0-1), <(blk1-1), <(blk2-1), <(blk3-1), <(blk4-1), <(blk5-1), <(blk6-1), <(blk7-1)
blk_hi: !byte >(blk0-1), >(blk1-1), >(blk2-1), >(blk3-1), >(blk4-1), >(blk5-1), >(blk6-1), >(blk7-1)

; Next sprite is not due yet: wake up at its line. A = its line ($ff: no more sprites)
!zone irq2_wait
irq2_wait:
    cmp #$ff
    beq irq2_last_sprite
    bit $d011
    bmi irq2_last_sprite    ; Raster wrapped past line 255: too late for the rest
    sty spr_irq_counter
    ldx $d012
    inx
    inx                     ; Margin: raster may move before the write
    stx irq_tmp
    cmp irq_tmp
    bcs .set_line
    jmp irq2_dispatch       ; Less than 2 lines: spin until it is due
.set_line:
    sta $d012
    jmp $ea81

!zone irq2_last_sprite
irq2_last_sprite:
    ; Last sprite displayed, return to sorting IRQ
    lda #<irq1
    sta $0314
    lda #>irq1
    sta $0315
    lda #IRQ1_LINE
    sta $d012
    jmp $ea81
