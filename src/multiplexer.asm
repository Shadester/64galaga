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
    lda $d011               ; Sorting can outlast the bottom border: if the raster
    bmi .arm                ; already passed IRQ2_LINE, start displaying right away
    lda $d012
    cmp #IRQ2_LINE-4
    bcc .arm
    cmp #IRQ1_LINE
    bcs .arm
    jmp irq2_direct
.arm:
    lda #IRQ2_LINE          ; Start display interrupt
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

    ; Copy sorted data, and precompute per sorted sprite the running $d010
    ; value. $d01c is $ff except in the 8 entries from the player ship on
    ; (the only hires sprite: its hardware sprite keeps the bit clear until
    ; another sprite reuses it).
!zone sort_copy
    lda #0
    sta pk_n
    sta sh_msb
    sta sort_p
    tax
.loop:
    ldy sort_p              ; X = sorted slot, sort_p = position in sort_order
    lda sort_order,y
    tay
    inc sort_p
    lda spr_y,y
    cmp #$ff                ; Hidden sprites sort last: stop at the first one
    beq .done_copy
    cpx #8
    bcc .keep
    sec                     ; Sprite X reuses the hardware sprite of X-8: if that one
    sbc sort_spr_y-8,x      ; is still being drawn, loading this one would cut it up.
    cmp #DROP_GAP           ; Draw one sprite too few instead
    bcs .reload
    lda spr_f,y
    cmp #SPR_PLAYER
    bne .drop               ; (the ship always stays)
.reload:
    lda spr_y,y
.keep:
    sta sort_spr_y,x
    lda #$ff
    sta sort_d01c,x
    lda spr_x,y
    sta sort_spr_x,x
    lda spr_c,y
    sta sort_spr_c,x
    lda spr_f,y
    sta sort_spr_f,x
    cmp #SPR_PLAYER
    bne .not_player
    txa                     ; Remember where the hires ships sit in the sorted list
    ldy pk_n
    sta pk_list,y
    inc pk_n
    ldy sort_p
    lda sort_order-1,y
    tay
.not_player:
    lda spr_x_msb,y         ; Running $d010: set or clear this sprite's bit
    beq .msb0
    lda sh_msb
    ora bit_tbl,x
    jmp .msb_st
.msb0:
    lda bit_tbl,x
    eor #$ff
    and sh_msb
.msb_st:
    sta sh_msb
    sta sort_d010,x
    inx
    cpx #MAX_SPRITES
    bcc .loop
    bcs .done_copy
.drop:
    lda sort_p
    cmp #MAX_SPRITES
    bcc .loop
.done_copy:
    stx sorted_sprites
    lda #$ff
    sta sort_spr_y,x        ; End marker
    ldy #8                  ; The hires windows can reach 8 entries past the last
.fill:
    sta sort_d01c,x
    inx
    dey
    bne .fill
.done:
    ldy pk_n                ; Each hires ship clears its hardware sprite's $d01c bit
.next_pk:                   ; from itself until that sprite is reused (8 entries)
    dey
    bmi .end
    ldx pk_list,y
    lda bit_tbl,x
    eor #$ff
    sta sh_mask
    lda #8
    sta sh_val
.window:
    lda sort_d01c,x
    and sh_mask
    sta sort_d01c,x
    inx
    dec sh_val
    bne .window
    beq .next_pk
.end:
    rts

; IRQ2: Display interrupt (runs multiple times per frame)
!zone irq2
irq2:
    cld
    dec $d019               ; Acknowledge raster interrupt

!zone irq2_direct
irq2_direct:
    ldy spr_irq_counter     ; Get sprite index
    lda sort_spr_y,y        ; Get Y of first sprite to display
    clc
    adc #$10                ; 16 lines down is endpoint
    bcc irq2_not_over
    lda #$ff                ; Cap at $ff
!zone irq2_not_over
irq2_not_over:
    sta temp_var

    ; Display sprites until we reach endpoint
!zone irq2_sprite_loop
irq2_sprite_loop:
    lda sort_spr_y,y
    cmp temp_var
    bcc .load
    jmp irq2_end_sprites
.load:
    lda sort_spr_y,y
    cmp $d012                   ; Y line already passed (IRQ ran late)?
    bcs .on_time
    lda sort_spr_y,y
    cmp #56
    lda #$ff                    ; Late and mostly in the top border: hide it
    bcc .on_time
    lda $d012                   ; Late: draw a few lines low instead of skipping the sprite
    clc
    adc #2
.on_time:
    ldx phys_spr_tbl_2,y        ; Physical sprite * 2
    sta $d001,x                 ; Y
    lda sort_spr_x,y
    sta $d000,x                 ; X low
    lda sort_d010,y             ; X high bits and multicolor bits are
    sta $d010                   ; precomputed per sprite by sort_sprites
    lda sort_d01c,y
    sta SPRITE_MCOLOR_EN
    ldx phys_spr_tbl_1,y        ; Physical sprite * 1
    lda sort_spr_f,y
    sta SPRITE_PTR,x
    lda sort_spr_c,y
    sta SPRITE_COLORS,x
    iny
    jmp irq2_sprite_loop        ; Ends via the sorted list's $ff marker

!zone irq2_end_sprites
irq2_end_sprites:
    cmp #$ff                ; Was it the end marker?
    beq irq2_last_sprite

    ; More sprites to come, set up next interrupt
    sty spr_irq_counter
    sec
    sbc #IRQ_LEAD           ; Start early: the loop waits for sprites to free up
    bcc .go_direct          ; Underflow: too close to the top
    ldx $d012
    inx
    inx                     ; Margin: raster may move before the write
    stx sort_temp_x
    cmp sort_temp_x
    bcs .set_line
.go_direct:
    jmp irq2_direct         ; Already late? Go direct
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
