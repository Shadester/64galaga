; Atari Lynx Galaga: the game rules, a port of the C64 source in ../c64/src (one translation unit).
; Rendering is in render.s; the sprite art and the font are generated (tools/gen_art.py).
        .include "lynx.inc"
        .include "constants.inc"
        .import pal_game, pal_title, title_pic, render_init, frame_begin, add_sprite, add_sprite_id, frame_end, flip, rand
        .importzp dr_d, dr_x, dr_y, rnd
        .import font_w, font_r
        .import _lynx_eeread_93c46, _lynx_eewrite_93c46
        .export popax
        .exportzp ptr1
        .export ax_lo, ax_hi, ay_lo, ay_hi, enemy_flag, form_pos, form_fdx, form_breathe, form_bstep, a_dly_lo, a_dly_hi
        .export player_x_msb, enemy_state, enemy_timer, enemy_hp, enemy_dir, enemy_esc, spr_x, spr_x_msb, spr_y, score, level, eb_x, eb_msb, eb_y, eb_dx, eb_active, eb_ax, pbul_x, pbul_msb, pbul_y
        .export main, frame, game_state, msg_n, anim, paused, player_x, lives, cap_state, beam_len, go_timer, pbul_active, shots, in_chal, msg_y, msg_x, msg_lo, msg_hi

        .zeropage
zp_src:         .res 2                  ; string source
zp_dst:         .res 2                  ; destination (print_num / draw_bcd buffer); message position x, y
fnt:            .res 2                  ; font of draw_text
ptr1:           .res 2                  ; scratch of cc65's eeprom.o
sp:             .res 2                  ; the arcade rules: the bit stream of a flight path
scur:           .res 1
scnt:           .res 1
tgt:            .res 2                  ; a slot: x, y
tgy:            .res 2

        .code
; Message macros: the C64 text positions (SCREEN_RAM + row * 40 + column) become pixel positions.
.macro print msg, addr, col
        lda #<msg
        sta zp_src
        lda #>msg
        sta zp_src+1
        lda #(((addr) .mod 40) * 4 - MSG_DX)
        sta zp_dst
        lda #(((addr) / 40) * 4 + MSG_DY)
        sta zp_dst+1
        lda #col
        sta txt_col
        jsr msg_add
.endmacro

.macro print_xy msg, xx, yy, col
        lda #<msg
        sta zp_src
        lda #>msg
        sta zp_src+1
        lda #xx
        sta zp_dst
        lda #yy
        sta zp_dst+1
        lda #col
        sta txt_col
        jsr msg_add
.endmacro

.macro setnum buf
        lda #<buf
        sta zp_dst
        lda #>buf
        sta zp_dst+1
.endmacro

        .include "game/data.s"
        .include "game/hud.s"
        .include "game/view.s"
        .include "game/sound.s"
        .include "game/hiscore.s"
        .include "game/player.s"
        .include "game/sprites.s"
        .include "game/progress.s"
        .include "game/challenge.s"
        .include "game/capture.s"
        .include "game/states.s"
        .include "game/arc.s"

main:   jsr render_init
        jsr load_hiscore
        jsr init_sound
        jsr init_stars
        jsr enter_title

game_loop:
.ifdef HALT
        inc halt_cnt                ; -DHALT=n: freeze after n frames (screenshot tests)
        bne @h_lo
        inc halt_cnt+1
@h_lo:  lda halt_cnt
        cmp #<HALT
        bne @h_go
        lda halt_cnt+1
        cmp #>HALT
        bne @h_go
        lda #1
        sta paused                  ; the stars hold still
@h_stop:
        jsr show_frame              ; keep showing the last frame
        bra @h_stop
@h_go:
.endif
        inc frame
        lda frame
        lsr
        lsr
        lsr
        lsr
        and #1
        cmp anim
        beq @same_anim
        sta anim                    ; Wing flap toggles every 16 frames
        jsr refresh_anim
@same_anim:
        jsr read_joystick
        jsr check_pause
        jsr check_quit
        lda paused
        bne @idle                   ; Paused: only keep the screen (and the frame pacing) going
        jsr snd_tick
        jsr run_state
        lda joystick_state          ; game.c keeps the state of the button in every state: a button that is held when the play starts
        and #$10                    ; (the intro, the READY) is not a press
        bne @fire_up
        lda #1
        sta fire_pressed
@fire_up:
@idle:  jsr update_sprite_data
        jsr show_frame
        jmp game_loop

; Build, draw and show one frame (the flip waits for the vertical blank: this paces the loop to 50 Hz)
show_frame:
        jsr frame_begin
        lda game_state
        bne @game
        lda #<title_pic             ; Title: the picture (no stars, no sprites)
        sta dr_d
        lda #>title_pic
        sta dr_d+1
        lda #TITLE_X
        sta dr_x
        stz dr_x+1
        stz dr_y
        stz dr_y+1
        jsr add_sprite
        bra @no_stars
@game:  jsr draw_stars
        jsr draw_beam
        jsr draw_sprites
        jsr draw_hud
@no_stars:
        jsr draw_msgs
        jsr frame_end
        jmp flip

run_state:
        ldx game_state
        beq @title
        dex
        beq @intro
        dex
        beq @play
        dex
        beq @dying
        dex
        beq @over
        dex
        beq @capt
        dex
        beq @result
        jmp st_ready
@result: jmp st_result
@capt:  jmp st_captured
@over:  jmp st_gameover
@title: jmp st_title
@intro: jmp st_intro
@play:  jmp st_play
@dying: jmp st_dying
