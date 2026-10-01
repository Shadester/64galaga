; Sound on the Mikey voices. The C64 uses the three SID voices; here: voice 0 shoot / ship hit (square),
; voice 1 explosions (noise), voice 2 jingles, the dive swoop and the beam hum (square). Effects fade
; out by themselves: snd_tick lowers the volume every frame.
;
; A Mikey voice makes a square wave with FEED = $80 (a 12-bit shift register with one tap: 24 timer steps
; a cycle) and noise with several taps. Timer: 1 MHz / (reload + 1). Hz = 41667 / (reload + 1).
AUD_VOL         = $fd20         ; + 8 * voice: volume, feedback, output, shift, reload, control, counter, control B
AUD_FEED        = $fd21
AUD_SHIFT       = $fd23
AUD_BKUP        = $fd24
AUD_CTLA        = $fd25
AUD_CTLB        = $fd27

SQUARE          = $80
NOISE           = $11
V_SHOOT         = 0             ; voice offsets
V_EXPL          = 8
V_JINGLE        = 16

snd_vol:        .res 2          ; fading voices 0 and 1
snd_dec:        .res 2

init_sound:
        stz MSTEREO             ; all voices on, both ears
        stz snd_vol
        stz snd_vol+1
        ldx #V_JINGLE
@clr:   stz AUD_VOL,x
        stz AUD_CTLA,x
        stz AUD_SHIFT,x
        stz AUD_CTLB,x
        txa
        sec
        sbc #8
        tax
        bpl @clr
        rts

; Start voice X (offset): A = reload, Y = feedback; the volume is set by the caller
snd_start:
        stz AUD_CTLA,x          ; stop, load, run (1 MHz, reload on)
        sta AUD_BKUP,x
        tya
        sta AUD_FEED,x
        stz AUD_SHIFT,x
        stz AUD_CTLB,x
        lda #$18
        sta AUD_CTLA,x
        rts

; Quick high beep
sound_shoot:
        ldx #V_SHOOT
        lda #33                 ; 1.2 kHz
        ldy #SQUARE
        jsr snd_start
        lda #$50
        ldx #6
        bra snd_fade0

; Lower descending tone
sound_player_hit:
        ldx #V_SHOOT
        lda #112                ; 370 Hz
        ldy #SQUARE
        jsr snd_start
        lda #$60
        ldx #3
snd_fade0:
        sta snd_vol
        sta AUD_VOL + V_SHOOT
        stx snd_dec
        rts

; Noise burst
sound_explosion:
        ldx #V_EXPL
        lda #12
        ldy #NOISE
        jsr snd_start
        lda #$60
        ldx #3
        bra snd_fade1

; The ship explodes: long low noise rumble
sound_player_die:
        ldx #V_EXPL
        lda #40
        ldy #NOISE
        jsr snd_start
        lda #$70
        ldx #1
snd_fade1:
        sta snd_vol+1
        sta AUD_VOL + V_EXPL
        stx snd_dec+1
        rts

; Pause: silence everything. Unpausing needs nothing: the next effect starts its voice again.
sound_mute:
        jsr init_sound
        stz jin_on
        stz swoop_cnt
        rts

sound_unmute:
        rts

; Start the jingle at offset A into jin_data
play_jingle:
        sta jin_pos
        lda #1
        sta jin_on
        lda #0
        sta jin_dur
        rts

; Every frame: fade voices 0 and 1, then voice 2: the jingle player, or the dive swoop when silent
snd_tick:
        ldx #1
@fade:  lda snd_vol,x
        beq @next
        sec
        sbc snd_dec,x
        bcs @set
        lda #0
@set:   sta snd_vol,x
        pha
        txa
        asl
        asl
        asl
        tay
        pla
        sta AUD_VOL,y
        bne @next
        lda #0
        sta AUD_CTLA,y          ; faded out: stop the voice
@next:  dex
        bpl @fade

        lda jin_on
        bne @jingle
        lda swoop_cnt
        beq @rts
        dec swoop_cnt
        beq @swoop_end
        tax
        lda swoop_tbl,x         ; Falling pitch
        ldx #V_JINGLE
        ldy #SQUARE
        jsr snd_start
        lda #$30
        sta AUD_VOL + V_JINGLE
@rts:   rts
@swoop_end:
        stz AUD_VOL + V_JINGLE
        stz AUD_CTLA + V_JINGLE
        rts
@jingle:
        lda jin_dur
        beq @next_note
        dec jin_dur
        lda AUD_VOL + V_JINGLE  ; the note decays a little (SID: decay to the sustain level)
        cmp #$38
        bcc @rts
        sec
        sbc #2
        sta AUD_VOL + V_JINGLE
        rts
@next_note:
        ldx jin_pos
        lda jin_data+2,x        ; Duration, 0 ends the tune
        beq @jin_end
        sta jin_dur
        lda jin_data,x          ; Timer reload
        pha
        inx
        inx
        inx
        stx jin_pos
        pla
        ldx #V_JINGLE
        ldy #SQUARE
        jsr snd_start
        lda #$60
        sta AUD_VOL + V_JINGLE
        rts
@jin_end:
        stz jin_on
        stz AUD_VOL + V_JINGLE
        stz AUD_CTLA + V_JINGLE
        rts

; Timer reload for the swoop: C64 SID frequency (swoop_cnt * 2 + 8) * 256 -> 15 Hz per step -> Hz = (2n + 8) * 15.03
swoop_tbl:
        .byte 0
        .repeat 24, n
        .byte .min(255, 41667 / (((n + 1) * 2 + 8) * 15) - 1)
        .endrepeat
