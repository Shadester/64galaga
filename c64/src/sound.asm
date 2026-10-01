; SID sound effects and the jingle player
; ===============================================
; SOUND EFFECTS
; ===============================================

; Initialize SID chip
!zone init_sound
init_sound:
    ; Clear all SID registers first
    ldx #$18
    lda #0
.clear_loop:
    sta $d400,x
    dex
    bpl .clear_loop

    ; Set master volume to max (15) in lower nibble
    lda #$0f
    sta SID_FILTER_MODE

    ; Voice 3: pulse wave for jingles
    lda #$08
    sta SID_V3_PW_HI
    lda #$08                ; Attack=0, Decay=8
    sta SID_V3_AD
    lda #$a5                ; Sustain=10, Release=5
    sta SID_V3_SR
    rts

; Shoot sound effect - quick high beep
!zone sound_shoot
sound_shoot:
    lda #$50
    sta SID_V1_FREQ_HI
    lda #$00
    sta SID_V1_FREQ_LO
    lda #$07                ; Attack=0, Decay=7
    sta SID_V1_AD
    lda #$00                ; Sustain=0, Release=0
    sta SID_V1_SR
    lda #$10                ; Triangle wave, gate off
    sta SID_V1_CTRL
    lda #$11                ; Triangle wave, gate on
    sta SID_V1_CTRL
    rts

; Explosion sound effect - noise burst
!zone sound_explosion
sound_explosion:
    lda #$20
    sta SID_V2_FREQ_HI
    lda #$00
    sta SID_V2_FREQ_LO
    lda #$0A                ; Attack=0, Decay=A
    sta SID_V2_AD
    lda #$00                ; Sustain=0, Release=0
    sta SID_V2_SR
    lda #$80                ; Noise wave, gate off
    sta SID_V2_CTRL
    lda #$81                ; Noise wave, gate on
    sta SID_V2_CTRL
    rts

; Player hit sound effect - lower descending tone
!zone sound_player_hit
sound_player_hit:
    lda #$18
    sta SID_V1_FREQ_HI
    lda #$00
    sta SID_V1_FREQ_LO
    lda #$09                ; Attack=0, Decay=9
    sta SID_V1_AD
    lda #$00                ; Sustain=0, Release=0
    sta SID_V1_SR
    lda #$20                ; Sawtooth wave, gate off
    sta SID_V1_CTRL
    lda #$21                ; Sawtooth wave, gate on
    sta SID_V1_CTRL
    rts

; Player explosion - long low noise rumble
!zone sound_player_die
sound_player_die:
    lda #$0c
    sta SID_V2_FREQ_HI
    lda #$00
    sta SID_V2_FREQ_LO
    lda #$0B                ; Attack=0, Decay=B
    sta SID_V2_AD
    lda #$80
    sta SID_V2_CTRL
    lda #$81
    sta SID_V2_CTRL
    rts

; Start jingle at offset A into jin_data
!zone play_jingle
play_jingle:
    sta jin_pos
    lda #1
    sta jin_on
    lda #0
    sta jin_dur
    rts

; Per-frame voice 3: jingle player, or the dive swoop when silent
!zone snd_tick
snd_tick:
    lda jin_on
    bne .jingle
    lda swoop_cnt
    beq .rts
    dec swoop_cnt
    beq .swoop_end
    asl
    clc
    adc #8
    sta SID_V3_FREQ_HI      ; Falling pitch
    lda #0
    sta SID_V3_FREQ_LO
    lda #$21                ; Sawtooth, gate on
    sta SID_V3_CTRL
.rts:
    rts
.swoop_end:
    lda #$20
    sta SID_V3_CTRL
    rts
.jingle:
    lda jin_dur
    beq .next_note
    dec jin_dur
    rts
.next_note:
    ldx jin_pos
    lda jin_data+2,x        ; Duration, 0 ends the tune
    beq .jin_end
    sta jin_dur
    lda jin_data,x
    sta SID_V3_FREQ_LO
    lda jin_data+1,x
    sta SID_V3_FREQ_HI
    inx
    inx
    inx
    stx jin_pos
    lda #$40                ; Pulse wave, gate off
    sta SID_V3_CTRL
    lda #$41                ; Pulse wave, gate on
    sta SID_V3_CTRL
    rts
.jin_end:
    lda #0
    sta jin_on
    lda #$40
    sta SID_V3_CTRL
    rts
