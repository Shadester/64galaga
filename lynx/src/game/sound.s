; Sound on the Mikey voices. The C64 uses the three SID voices; here: voice 0 shoot / ship hit (square),
; voice 1 explosions (noise), voice 2 jingles, the dive swoop and the beam hum (square). Effects fade
; out by themselves: snd_tick lowers the volume every frame (each time by a part of it: a quick bang, a long tail) and
; slides the pitch down (the timer reload grows), so a shot is a "pew" and an explosion a noise that falls.
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
snd_dec:        .res 2          ; each frame: volume = volume - (volume >> snd_dec) - 1
snd_rl:         .res 2          ; the timer reload now
snd_rs:         .res 2          ; added to it each frame (0: no slide)
snd_t:          .res 1

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
        phx                     ; the callers keep X and Y (shoot_bullet loops on Y)
        phy
        ldx #V_SHOOT
        lda #14                 ; 2.8 kHz, sliding down
        ldy #SQUARE
        jsr snd_start
        lda #14
        ldx #3
        ldy #3
        bra snd_set0

; Lower descending tone
sound_player_hit:
        phx                     ; the callers keep X and Y (shoot_bullet loops on Y)
        phy
        ldx #V_SHOOT
        lda #70                 ; 590 Hz, sliding down
        ldy #SQUARE
        jsr snd_start
        lda #70
        ldx #4
        ldy #9
snd_set0:                       ; A = reload now, X = decay shift, Y = slide
        sta snd_rl
        stx snd_dec
        sty snd_rs
        lda #$60
        sta snd_vol
        sta AUD_VOL + V_SHOOT
        ply
        plx
        rts

; Noise burst
sound_explosion:
        phx                     ; the callers keep X and Y (shoot_bullet loops on Y)
        phy
        ldx #V_EXPL
        lda #5                  ; hiss, falling quickly
        ldy #NOISE
        jsr snd_start
        lda #5
        ldx #2
        ldy #3
        bra snd_set1

; The ship explodes: long low noise rumble
sound_player_die:
        phx                     ; the callers keep X and Y (shoot_bullet loops on Y)
        phy
        ldx #V_EXPL
        lda #18
        ldy #NOISE
        jsr snd_start
        lda #18
        ldx #4
        ldy #2
snd_set1:                       ; A = reload now, X = decay shift, Y = slide
        sta snd_rl+1
        stx snd_dec+1
        sty snd_rs+1
        lda #$7f
        sta snd_vol+1
        sta AUD_VOL + V_EXPL
        ply
        plx
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
        txa
        asl
        asl
        asl
        tay                     ; the voice's offset
        lda snd_rl,x            ; slide the pitch down
        clc
        adc snd_rs,x
        bcc @rl
        lda #255
@rl:    sta snd_rl,x
        sta AUD_BKUP,y
        lda snd_vol,x           ; volume = volume - (volume >> shift) - 1
        sta snd_t
        phx
        lda snd_dec,x
        tax
@sh:    dex
        bmi @shd
        lsr snd_t
        bra @sh
@shd:   plx
        lda snd_vol,x
        sec
        sbc snd_t
        beq @off
        bcc @off
        dec
        beq @off
        sta snd_vol,x
        sta AUD_VOL,y
        bra @next
@off:   lda #0
        sta snd_vol,x
        sta AUD_VOL,y
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
