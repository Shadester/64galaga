; Joystick input, player movement and shooting
; ===============================================
; JOYSTICK INPUT
; ===============================================

!zone read_joystick
read_joystick:
!ifdef AUTOPLAY {
    ; Synthetic input: sweep the screen left/right, fire in bursts
    lda #$ff
    sta joystick_state
!ifdef CAPTURE {
    lda game_state          ; -DCAPTURE=1: pulse fire to leave title / game over,
    cmp #GS_PLAY            ; idle while a boss beams (so it captures us), then
    beq .cap_play           ; chase and shoot the boss once it dives with the captive
    lda frame
    and #$08
    bne .auto_done
    jmp .cap_fire
.cap_play:
    lda cap_state
    cmp #4
    bne .auto_done
    ldx cap_boss
    lda enemy_state,x
    cmp #2
    bne .auto_done
    lda enemy_x,x
    cmp player_x
    bcs .cap_right
    lda joystick_state
    and #$fb
    sta joystick_state
    jmp .cap_fire
.cap_right:
    lda joystick_state
    and #$f7
    sta joystick_state
.cap_fire:
    lda frame
    and #$04                ; Pulse the button so every press is a new shot
    bne .auto_done
    lda joystick_state
    and #$ef
    sta joystick_state
    jmp .auto_done
}
    lda frame
    and #$80                ; 128 frames per direction = 256px sweep
    beq .auto_right
    lda joystick_state
    and #$fb
    sta joystick_state
    jmp .auto_fire
.auto_right:
    lda joystick_state
    and #$f7
    sta joystick_state
.auto_fire:
!ifdef QUITAT {
    lda game_state          ; -DQUITAT: after the quit, stay on the title screen
    bne .q_go
    lda halt_cnt+1
    cmp #>QUITAT
    bcc .q_go
    bne .auto_done
    lda halt_cnt
    cmp #<QUITAT
    bcs .auto_done
.q_go:
}
!ifdef NOFIRE {
    lda game_state          ; -DNOFIRE: only fire to leave title / game over
    cmp #GS_PLAY
    beq .auto_done
}
    lda frame
    and #$08
    bne .auto_done
    lda joystick_state
    and #$ef
    sta joystick_state
.auto_done:
} else {
    lda CIA1_PRA
    sta joystick_state
}
    lda joystick_state
    and #$10
    beq .held
    lda #0
    sta fire_pressed            ; Released: next press counts
.held:
    rts

; P pauses and resumes (during play only). Reads keyboard row 5, column 1.
!zone check_pause
check_pause:
!ifdef PAUSEAT {
    lda halt_cnt+1              ; -DPAUSEAT=n: pretend P is pressed at frame n
    cmp #>PAUSEAT
    bne .real
    lda halt_cnt
    cmp #<PAUSEAT
    bne .real
    jmp .toggle
.real:
}
    lda #%11011111
    sta $dc00
    lda $dc01
    ldx #$ff
    stx $dc00                   ; Back to the joystick
    and #$02
    bne .up                     ; Not pressed
    lda pause_key
    bne .rts                    ; Still held
    lda #1
    sta pause_key
.toggle:
    lda paused
    bne .resume
    lda game_state
    cmp #GS_PLAY
    bne .rts
    lda #1
    sta paused
    lda #0
    sta SID_FILTER_MODE         ; Silence
    +print msg_pause, SCREEN_RAM+20*40+17, 1
    rts
.resume:
    lda #0
    sta paused
    lda #$0f
    sta SID_FILTER_MODE
    jmp clear_stage_row
.up:
    lda #0
    sta pause_key
.rts:
    rts

; RUN/STOP (Esc in VICE) quits the game to the title screen, keeping a new hi-score.
; Reads keyboard row 7, column 7. Not in the title or at game over.
!zone check_quit
check_quit:
    lda game_state
    beq .rts                    ; Title
    cmp #GS_GAMEOVER
    beq .rts
!ifdef QUITAT {
    lda halt_cnt+1              ; -DQUITAT=n (with HALT): pretend RUN/STOP at frame n
    cmp #>QUITAT
    bne .real
    lda halt_cnt
    cmp #<QUITAT
    bne .real
    jmp .quit
.real:
}
    lda #%01111111
    sta $dc00
    lda $dc01
    ldx #$ff
    stx $dc00                   ; Back to the joystick
    and #$80
    bne .rts                    ; Not pressed
.quit:
    lda #0
    sta paused
    sta jin_on                  ; Silence: jingle, swoop, voices, volume back up
    sta swoop_cnt
    jsr init_sound
    jsr update_hiscore
    lda hs_dirty
    beq .no_save
    jsr save_hiscore
.no_save:
    jmp enter_title
.rts:
    rts

; ===============================================
; PLAYER UPDATE
; ===============================================

!zone update_player
update_player:
    ; Check left
    lda joystick_state
    and #$04
    bne .check_right
    lda player_x_msb
    bne .pl_left            ; X >= 256, always above left limit
    lda player_x
    cmp #SCREEN_LEFT+2         ; Stop at SCREEN_LEFT after the 2px step
    bcc .check_right
.pl_left:
    lda player_x
    sec
    sbc #2
    sta player_x
    bcs .check_right
    dec player_x_msb

.check_right:
    lda joystick_state
    and #$08
    bne .check_fire
    lda player_x_msb
    beq .pl_right           ; X < 256, below right limit
    lda player_x
    ldy dual
    beq .lim1
    cmp #<(SCREEN_RIGHT-16)     ; Dual fighter is 16px wider
    jmp .lim2
.lim1:
    cmp #<SCREEN_RIGHT
.lim2:
    bcs .check_fire
.pl_right:
    lda player_x
    clc
    adc #2
    sta player_x
    bcc .check_fire
    inc player_x_msb

.check_fire:
    lda joystick_state
    and #$10
    bne .player_done
    lda fire_pressed
    bne .player_done
    lda #1
    sta fire_pressed
    jmp shoot_bullet
.player_done:
    rts

; ===============================================
; SHOOTING (two shots in flight)
; ===============================================

!zone shoot_bullet
shoot_bullet:
    ldy #0                  ; Ship 0 = left / only ship, 1 = right of a dual pair
.ship:
    tya
    asl
    tax                     ; First of this ship's two bullet slots
    lda pbul_active,x
    beq .use
    inx
    lda pbul_active,x
    bne .next
.use:
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
    bne .counted
    inc shots+1
.counted:
    jsr sound_shoot
.next:
    iny
    cpy dual
    beq .ship
    bcc .ship
    rts

bul_off:        !byte 3, 19

!zone update_bullets
update_bullets:
    ldx #3
.loop:
    lda pbul_active,x
    beq .next
    lda pbul_y,x
    sec
    sbc #4
    sta pbul_y,x
    cmp #20
    bcs .next
    lda #0
    sta pbul_active,x
.next:
    dex
    bpl .loop
    rts
