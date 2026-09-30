; Hi-score on disk: the file "HISCORE" (3 BCD bytes) is read at start-up and
; rewritten after a game that set a new record. Without a drive or disk the
; KERNAL just reports an error, which is ignored.

KERNAL_SETLFS   = $ffba
KERNAL_SETNAM   = $ffbd
KERNAL_OPEN     = $ffc0
KERNAL_CLOSE    = $ffc3
KERNAL_LOAD     = $ffd5
KERNAL_SAVE     = $ffd8

hs_name:        !text "HISCORE"
hs_name_end:
hs_reset:       !text "I0"
hs_reset_end:
hs_scratch:     !text "S0:HISCORE"
hs_scratch_end:
hs_buf:         !byte 0, 0, 0
hs_dirty:       !byte 0                 ; 1 = hiscore changed since it was read / saved

; X = device of the last disk access, but at least 8
!zone hs_device
hs_device:
    ldx $ba
    cpx #8
    bcs .rts
    ldx #8
.rts:
    rts

; Start-up, while the KERNAL still runs its own interrupt
!zone load_hiscore
load_hiscore:
    jsr hs_load
    jmp hs_clear_error          ; A missing file leaves an error in the drive: its LED would blink

!zone hs_load
hs_load:
    lda #0
    sta $9d                     ; No SEARCHING / LOADING messages
    lda #hs_name_end-hs_name
    ldx #<hs_name
    ldy #>hs_name
    jsr KERNAL_SETNAM
    jsr hs_device
    lda #1
    ldy #0                      ; Load to the address given to LOAD
    jsr KERNAL_SETLFS
    lda #0
    ldx #<hs_buf
    ldy #>hs_buf
    jsr KERNAL_LOAD
    bcs .rts                    ; No drive, disk or file
    ldx #2
.check:
    lda hs_buf,x                ; Two valid BCD digits in every byte?
    and #$0f
    cmp #10
    bcs .rts
    lda hs_buf,x
    lsr
    lsr
    lsr
    lsr
    cmp #10
    bcs .rts
    dex
    bpl .check
    ldx #2
.copy:
    lda hs_buf,x
    sta hiscore,x
    dex
    bpl .copy
.rts:
    rts

; Clear the drive's error state: a LOAD of a missing file (or a failed SAVE) leaves an error that
; makes the LED of a real 1541 blink until the next command succeeds. "I0" (initialize) is quick
; and answers "00, OK". (A reset, "UJ", would stall the bus for seconds.) Without a drive OPEN
; just fails; without a disk the drive reports "74, DRIVE NOT READY" anyway.
!zone hs_clear_error
hs_clear_error:
    lda #hs_reset_end-hs_reset
    ldx #<hs_reset
    ldy #>hs_reset
    jsr KERNAL_SETNAM
    jsr hs_device
    lda #15
    ldy #15
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    lda #15
    jmp KERNAL_CLOSE

; Write the hi-score. The game's raster interrupt and the sprites must be off
; while the serial bus is busy, and the KERNAL interrupt is needed for its timing.
!zone save_hiscore
save_hiscore:
    sei
    lda #0
    sta $d015                   ; Sprites off
    sta $d01a                   ; Raster interrupt off
    lda #1
    sta $d019                   ; Acknowledge a pending raster interrupt
    sta $cc                     ; No blinking cursor
    lda #<$ea31
    sta $0314
    lda #>$ea31
    sta $0315
    lda #$81
    sta $dc0d                   ; CIA interrupt back on
    lda $dc0d
    cli
    lda #0
    sta $9d                     ; No SAVING message
    lda #hs_scratch_end-hs_scratch
    ldx #<hs_scratch
    ldy #>hs_scratch
    jsr KERNAL_SETNAM           ; Delete the old file through the command channel
    jsr hs_device
    lda #15
    ldy #15
    jsr KERNAL_SETLFS
    jsr KERNAL_OPEN
    lda #15
    jsr KERNAL_CLOSE
    lda #hs_name_end-hs_name
    ldx #<hs_name
    ldy #>hs_name
    jsr KERNAL_SETNAM
    jsr hs_device
    lda #1
    ldy #1
    jsr KERNAL_SETLFS
    lda #<hiscore
    sta $fb
    lda #>hiscore
    sta $fc
    lda #$fb
    ldx #<(hiscore+3)
    ldy #>(hiscore+3)
    jsr KERNAL_SAVE             ; Carry set = failed, nothing to do about it
    lda #0
    sta hs_dirty
    jsr hs_clear_error
    jmp init_raster             ; Our raster interrupt again (ends with cli)
