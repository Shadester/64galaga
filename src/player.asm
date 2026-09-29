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
