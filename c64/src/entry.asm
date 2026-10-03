; Fly-in at the start of a normal stage: the aliens enter along the arcade's paths
; in five groups, then home in on their formation slots.
; An entering alien has enemy_state 7. enemy_flag: 0 waiting for its launch (wave_launch,
; challenge.asm), 1 flying its path, 2 homing on its slot.
; The path stepper (chal_step) is shared with the challenge stages.
; `entering` counts the aliens in state 7: setup_entry sets it, an alien that is home
; (home_step) or shot (set_explode) takes itself off. ent_start is its value at the
; start of the game loop's formation update: what the dive scheduler may look at.

entering:       !byte 0                 ; Aliens still entering
ent_start:      !byte 0
tgt_x:          !byte 0
tgt_xh:         !byte 0
d_lo:           !byte 0
moved:          !byte 0

; Turn the aliens of a freshly reset formation into waiting entrants
!zone setup_entry
setup_entry:
    lda #0
    sta entering
    ldx #MAX_ENEMIES-1
.loop:
    lda enemy_state,x
    cmp #1
    bne .next                   ; Not there at all (FEW)
    lda #7
    sta enemy_state,x
    lda #0
    sta enemy_flag,x
    lda #$ff
    sta enemy_y,x               ; Hidden until launched
    inc entering
.next:
    dex
    bpl .loop
    jmp wave_reset

; Per tick: move flying aliens, steer homing ones, then launch the ones whose time has come. The waiting
; ones wait while the ship is not in play (only the ones in the air go on).
!zone update_entry
update_entry:
    lda entering
    beq .rts
    ldx #MAX_ENEMIES-1
.loop:
    lda enemy_state,x
    cmp #7
    bne .next
    lda enemy_flag,x
    beq .next
    cmp #1
    bne .home
    jsr chal_step
    jmp .next
.home:
    jsr home_step
.next:
    dex
    bpl .loop
    lda game_state
    cmp #GS_PLAY
    bne .rts
    jmp wave_launch
.rts:
    rts

; Move alien X 2px per axis towards its formation slot (the slot keeps swaying);
; within 3px on both axes it snaps in and becomes a normal formation alien.
!zone home_step
home_step:
    lda enemy_x,x
    pha
    lda enemy_x_msb,x
    pha
    jsr set_slot_x              ; enemy_x / msb = slot column ...
    lda enemy_x,x
    sta tgt_x
    lda enemy_x_msb,x
    sta tgt_xh
    pla                         ; ... and back to where the alien is
    sta enemy_x_msb,x
    pla
    sta enemy_x,x
    lda #0
    sta moved
    lda tgt_x
    sec
    sbc enemy_x,x
    sta d_lo
    lda tgt_xh
    sbc enemy_x_msb,x           ; Signed 16-bit distance: d_lo / A
    bmi .left
    bne .r2                     ; 256 or more away
    lda d_lo
    cmp #4
    bcc .y                      ; Within 3px: close enough
.r2:
    lda #2
    sta moved
    clc
    adc enemy_x,x
    sta enemy_x,x
    bcc .y
    inc enemy_x_msb,x
    jmp .y
.left:
    cmp #$ff
    bne .l2
    lda d_lo
    cmp #$fd
    bcs .y                      ; Within 3px
.l2:
    lda #2
    sta moved
    lda enemy_x,x
    sec
    sbc moved
    sta enemy_x,x
    bcs .y
    dec enemy_x_msb,x
.y:
    lda base_y,x
    sec
    sbc enemy_y,x
    bcc .up
    cmp #4
    bcc .end                    ; Within 3px
    lda enemy_y,x
    clc
    adc #2
    jmp .y_set
.up:
    cmp #$fd
    bcs .end                    ; Within 3px
    lda enemy_y,x
    sec
    sbc #2
.y_set:
    sta enemy_y,x
    lda #2
    sta moved
.end:
    lda moved
    bne .rts
    dec entering
    lda #1                      ; Arrived
    sta enemy_state,x
    lda #0
    sta enemy_flag,x
    sta enemy_timer,x
    jmp set_slot_pos
.rts:
    rts
