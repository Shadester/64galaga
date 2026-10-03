; Joystick input, player movement and shooting
; ===============================================
; JOYSTICK INPUT
; ===============================================


read_joystick:
.ifdef AUTOPLAY
    ; Synthetic input: sweep the screen left/right, fire in bursts
    lda #$ff
    sta joystick_state
.ifdef CAPTURE
.ifdef ARCADE
    ; -DCAPTURE=1 with the arcade rules: the script of FORCECAPTURE in psp/game.c (tools/compare_6502.py has the same one in C): the ship
    ; sweeps, but walks under the capture boss while it dives, beams or carries the captive; it only fires to leave the title screen
    ; and game over (pulses), and at the carrier
    lda frame
    and #$80
    beq @a_right
    lda joystick_state
    and #$fb
    sta joystick_state
    bra @a_swept
@a_right:
    lda joystick_state
    and #$f7
    sta joystick_state
@a_swept:
    lda frame                   ; the button: pulses in the title / game over / intro..., never in play and on the result screen
    and #$08
    bne @a_nofire
    lda game_state
    cmp #GS_PLAY
    beq @a_nofire
    cmp #GS_RESULT
    beq @a_nofire
    lda joystick_state
    and #$ef
    sta joystick_state
@a_nofire:
    lda cap_state               ; on the way to the beam, in the beam, or carrying the captive: walk under the boss
    cmp #1
    beq @a_chase
    cmp #2
    beq @a_chase
    cmp #4
    bne @a_done
@a_chase:
    ldx cap_boss
    lda player_x                ; left when px > bx + 2, right when px < bx - 2
    sec
    sbc ax_lo,x
    sta d16
    lda player_x_msb
    sbc ax_hi,x
    sta d16+1
    lda joystick_state
    ora #$0c                    ; neither
    sta joystick_state
    lda d16+1
    bmi @a_neg
    bne @a_left
    lda d16
    cmp #3
    bcc @a_carry
@a_left:
    lda joystick_state
    and #$fb
    sta joystick_state
    bra @a_carry
@a_neg: lda d16+1
    cmp #$ff
    bne @a_rightgo
    lda d16
    cmp #$fe                    ; d >= -2: neither
    bcs @a_carry
@a_rightgo:
    lda joystick_state
    and #$f7
    sta joystick_state
@a_carry:
    lda cap_state
    cmp #4
    bne @a_done
    lda joystick_state          ; carrying: fire while (frame & 3) < 2
    ora #$10
    sta joystick_state
    lda frame
    and #$02
    bne @a_done
    lda joystick_state
    and #$ef
    sta joystick_state
@a_done:
    jmp @auto_done
.else
    lda game_state          ; -DCAPTURE=1: pulse fire to leave title / game over,
    cmp #GS_PLAY            ; idle while a boss beams (so it captures us), then
    beq @cap_play           ; chase and shoot the boss once it dives with the captive
    lda frame
    and #$08
    bne @auto_done
    jmp @cap_fire
@cap_play:
    lda cap_state
    cmp #4
    bne @auto_done
    ldx cap_boss
    lda enemy_state,x
    cmp #2
    bne @auto_done
    lda enemy_x,x
    cmp player_x
    bcs @cap_right
    lda joystick_state
    and #$fb
    sta joystick_state
    jmp @cap_fire
@cap_right:
    lda joystick_state
    and #$f7
    sta joystick_state
@cap_fire:
    lda frame
    and #$04                ; Pulse the button so every press is a new shot
    bne @auto_done
    lda joystick_state
    and #$ef
    sta joystick_state
    jmp @auto_done
.endif
.endif
    lda frame
    and #$80                ; 128 frames per direction = 256px sweep
    beq @auto_right
    lda joystick_state
    and #$fb
    sta joystick_state
    jmp @auto_fire
@auto_right:
    lda joystick_state
    and #$f7
    sta joystick_state
@auto_fire:
.ifdef QUITAT
    lda game_state          ; -DQUITAT: after the quit, stay on the title screen
    bne @q_go
    lda halt_cnt+1
    cmp #>QUITAT
    bcc @q_go
    bne @auto_done
    lda halt_cnt
    cmp #<QUITAT
    bcs @auto_done
@q_go:
.endif
.ifdef NOFIRE
    lda game_state          ; -DNOFIRE: only fire to leave title / game over
    cmp #GS_PLAY
    beq @auto_done
.endif
    lda frame
    and #$08
    bne @auto_done
    lda joystick_state
    and #$ef
    sta joystick_state
@auto_done:
.else
    ldx #$ff                    ; The pad as the C64 joystick: active low left / right / fire
    lda JOYSTICK
    bit #$20                    ; Left
    beq @pad_r
    pha
    txa
    and #.lobyte(~JS_LEFT)
    tax
    pla
@pad_r:
    bit #$10                    ; Right
    beq @pad_f
    pha
    txa
    and #.lobyte(~JS_RIGHT)
    tax
    pla
@pad_f:
    bit #$03                    ; A or B
    beq @pad_done
    txa
    and #.lobyte(~JS_FIRE)
    tax
@pad_done:
    stx joystick_state
.endif
    lda joystick_state
    and #$10
    beq @held
    lda #0
    sta fire_pressed            ; Released: next press counts
@held:
    rts

; P pauses and resumes (during play only). Reads keyboard row 5, column 1.

check_pause:
.ifdef PAUSEAT
    lda halt_cnt+1              ; -DPAUSEAT=n: pretend P is pressed at frame n
    cmp #>PAUSEAT
    bne @real
    lda halt_cnt
    cmp #<PAUSEAT
    bne @real
    jmp @toggle
@real:
.endif
    lda SWITCHES
    and #$01
    beq @up                     ; Pause button not pressed
    lda pause_key
    bne @rts                    ; Still held
    lda #1
    sta pause_key
@toggle:
    lda paused
    bne @resume
    lda game_state
    cmp #GS_PLAY
    bne @rts
    lda #1
    sta paused
    lda #0
    jsr sound_mute              ; Silence
    print msg_pause, SCREEN_RAM+20*40+17, 1
    rts
@resume:
    lda #0
    sta paused
    jsr sound_unmute
    jmp clear_stage_row
@up:
    lda #0
    sta pause_key
@rts:
    rts

; RUN/STOP (Esc in VICE) quits the game to the title screen, keeping a new hi-score.
; Reads keyboard row 7, column 7. Not in the title or at game over.

check_quit:
    lda game_state
    beq @rts                    ; Title
    cmp #GS_GAMEOVER
    beq @rts
.ifdef QUITAT
    lda halt_cnt+1              ; -DQUITAT=n (with HALT): pretend RUN/STOP at frame n
    cmp #>QUITAT
    bne @real
    lda halt_cnt
    cmp #<QUITAT
    bne @real
    jmp @quit
@real:
.endif
    lda JOYSTICK
    and #$08
    beq @rts                    ; Option 1 not pressed
@quit:
    lda #0
    sta paused
    sta jin_on                  ; Silence: jingle, swoop, voices, volume back up
    sta swoop_cnt
    jsr init_sound
    jsr update_hiscore
    lda hs_dirty
    beq @no_save
    jsr save_hiscore
@no_save:
    jmp enter_title
@rts:
    rts

; ===============================================
; PLAYER UPDATE
; ===============================================


update_player:
    ; Check left
    lda joystick_state
    and #$04
    bne @check_right
    lda player_x_msb
    bne @pl_left            ; X >= 256, always above left limit
    lda player_x
    cmp #SCREEN_LEFT+2         ; Stop at SCREEN_LEFT after the 2px step
    bcc @check_right
@pl_left:
    lda player_x
    sec
    sbc #2
    sta player_x
    bcs @check_right
    dec player_x_msb

@check_right:
    lda joystick_state
    and #$08
    bne @check_fire
    lda player_x_msb
    beq @pl_right           ; X < 256, below right limit
    lda player_x
    ldy dual
    beq @lim1
    cmp #<(SCREEN_RIGHT-16)     ; Dual fighter is 16px wider
    jmp @lim2
@lim1:
    cmp #<SCREEN_RIGHT
@lim2:
    bcs @check_fire
@pl_right:
    lda player_x
    clc
    adc #2
    sta player_x
    bcc @check_fire
    inc player_x_msb

@check_fire:
    lda joystick_state
    and #$10
    bne @player_done
    lda fire_pressed
    bne @player_done
    lda #1
    sta fire_pressed
    jmp shoot_bullet
@player_done:
    rts

; ===============================================
; SHOOTING (two shots in flight)
; ===============================================


shoot_bullet:
    ldy #0                  ; Ship 0 = left / only ship, 1 = right of a dual pair
@ship:
    tya
    asl
    tax                     ; First of this ship's two bullet slots
    lda pbul_active,x
    beq @use
    inx
    lda pbul_active,x
    bne @next
@use:
    lda #1
    sta pbul_active,x
    lda player_x
    clc
    adc bul_off,y           ; Bullet art sits 3px left of the ship nose
    sta pbul_x,x
    lda player_x_msb
    adc #0
    sta pbul_msb,x
    lda #PLAYER_Y-16
    sta pbul_y,x
    inc shots
    bne @counted
    inc shots+1
@counted:
    jsr sound_shoot
@next:
    iny
    cpy dual
    beq @ship
    bcc @ship
    rts

bul_off:        .byte 3, 19


update_bullets:
    ldx #3
@loop:
    lda pbul_active,x
    beq @next
    lda pbul_y,x
    sec
    sbc #4
    sta pbul_y,x
    cmp #20
    bcs @next
    lda #0
    sta pbul_active,x
@next:
    dex
    bpl @loop
    rts
