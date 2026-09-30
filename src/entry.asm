; Fly-in at the start of a normal stage: the aliens enter along curved paths
; in four waves, then home in on their formation slots.
; An entering alien has enemy_state 7. enemy_flag: 0 waiting (enemy_timer
; counts down to its launch), 1 flying its path, 2 homing on its slot.
; The path stepper (chal_step) is shared with the challenge stages.

; Launch delay (frames) and path (id | $80 = mirrored) per formation slot
entry_delay_tbl:
    !byte 60,66,72,78,0,6,12,18
    !byte 84,90,96,102,120,126,132,138
    !byte 144,150,24,30,36,42,156,162
    !byte 180,186,192,198,204,210,216,222
entry_path_tbl:
    !byte $03,$03,$03,$03,$02,$82,$02,$82
    !byte $03,$03,$03,$03,$83,$83,$83,$83
    !byte $83,$83,$02,$82,$02,$82,$83,$83
    !byte $82,$02,$82,$02,$82,$02,$82,$02

entering:       !byte 0                 ; Aliens still entering
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
    sta enemy_idx,x
    lda entry_delay_tbl,x
    sta enemy_timer,x
    lda entry_path_tbl,x
    sta enemy_path,x
    lda #$ff
    sta enemy_y,x               ; Hidden until launched
    inc entering
.next:
    dex
    bpl .loop
    rts

; Per frame: launch waiting aliens, move flying ones, steer homing ones
!zone update_entry
update_entry:
    lda entering
    beq .rts
    lda #0
    sta entering
    ldx #MAX_ENEMIES-1
.loop:
    lda enemy_state,x
    cmp #7
    bne .next
    inc entering
    lda enemy_flag,x
    beq .wait
    cmp #1
    bne .home
    jsr chal_step
    jmp .next
.home:
    jsr home_step
    jmp .next
.wait:
    lda enemy_timer,x
    beq .launch
    dec enemy_timer,x
    jmp .next
.launch:
    lda #1
    sta enemy_flag,x
    jsr place_start
.next:
    dex
    bpl .loop
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
    lda #1                      ; Arrived
    sta enemy_state,x
    lda #0
    sta enemy_flag,x
    sta enemy_timer,x
    jmp set_slot_pos
.rts:
    rts
