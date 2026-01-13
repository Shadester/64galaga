; ===============================================
; C64 GALAGA CLONE - PROFESSIONAL VERSION
; ===============================================
; A Galaga-style shooter with raster interrupt sprite multiplexing
; Based on Cadaver's sprite multiplexer technique
; ===============================================

!cpu 6510

; ===============================================
; MEMORY MAP & HARDWARE REGISTERS
; ===============================================

; VIC-II Registers
SPRITE_ENABLE   = $d015
SPRITE_X        = $d000
SPRITE_Y        = $d001
SPRITE_MCOLOR_EN = $d01c        ; Sprite multicolor enable
SPRITE_MCOLOR1  = $d025         ; Shared multicolor 1
SPRITE_MCOLOR2  = $d026         ; Shared multicolor 2
SPRITE_COLORS   = $d027
SPRITE_PTR      = $07f8
BORDER_COLOR    = $d020
BG_COLOR        = $d021
SCREEN_RAM      = $0400
COLOR_RAM       = $d800

; CIA Registers
CIA1_PRA        = $dc00      ; Joystick port 2

; SID Registers (Sound Interface Device)
SID_V1_FREQ_LO  = $d400      ; Voice 1 frequency low byte
SID_V1_FREQ_HI  = $d401      ; Voice 1 frequency high byte
SID_V1_PW_LO    = $d402      ; Voice 1 pulse width low
SID_V1_PW_HI    = $d403      ; Voice 1 pulse width high
SID_V1_CTRL     = $d404      ; Voice 1 control register
SID_V1_AD       = $d405      ; Voice 1 attack/decay
SID_V1_SR       = $d406      ; Voice 1 sustain/release

SID_V2_FREQ_LO  = $d407      ; Voice 2 frequency low byte
SID_V2_FREQ_HI  = $d408      ; Voice 2 frequency high byte
SID_V2_CTRL     = $d40b      ; Voice 2 control register
SID_V2_AD       = $d40c      ; Voice 2 attack/decay
SID_V2_SR       = $d40d      ; Voice 2 sustain/release

SID_FILTER_FC_LO = $d415     ; Filter cutoff low
SID_FILTER_FC_HI = $d416     ; Filter cutoff high
SID_FILTER_RES   = $d417     ; Filter resonance/routing
SID_FILTER_MODE  = $d418     ; Filter mode/volume

; Game Constants
MAX_ENEMIES     = 24            ; More enemies for epic battles!
MAX_BULLETS     = 1
MAX_SPRITES     = 26            ; Player + Enemies + Bullet
PLAYER_Y        = 230
SCREEN_LEFT     = 24
SCREEN_RIGHT    = 250

; Raster IRQ Constants
IRQ1_LINE       = $fc           ; Sorting interrupt at bottom of screen
IRQ2_LINE       = $2a           ; Display interrupt start (line 42)

; ===============================================
; PROGRAM START
; ===============================================

* = $0801                     ; BASIC start address

; BASIC stub: 10 SYS 2064
!byte $0c,$08,$0a,$00,$9e,$20,$32,$30,$36,$34,$00,$00,$00

* = $0810                     ; Program start

init:
    jsr clear_screen
    jsr setup_colors
    jsr init_sprites
    jsr init_sound
    jsr init_game_state
    jsr init_multiplexer
    jsr init_raster

game_loop:
    jsr wait_frame

    ; Check if game is over
    lda game_over_flag
    bne game_over_loop

    jsr read_joystick
    jsr update_player
    jsr update_bullets
    jsr update_enemies
    jsr check_collisions
    jsr check_level_complete    ; Check if all enemies defeated
    jsr update_sprite_data      ; Update sprites for IRQ multiplexer
    jsr wait_for_irq            ; CRITICAL: Wait for IRQ to finish!
    jsr draw_score
    jmp game_loop

game_over_loop:
    ; Display GAME OVER message
    jsr draw_game_over
    jsr wait_frame
    jsr draw_score

    ; Check for fire button to restart
    jsr read_joystick
    lda joystick_state
    and #$10
    beq .restart_game       ; Fire button pressed (bit is 0)

    jmp game_over_loop

.restart_game:
    ; Clear GAME OVER message
    ldx #0
    lda #$20            ; Space character
.clear_msg:
    sta SCREEN_RAM+11*40+15,x
    inx
    cpx #9              ; "GAME OVER" is 9 characters
    bne .clear_msg

    ; Reset game state and restart
    jsr init_game_state
    jmp game_loop

; ===============================================
; SCREEN & COLOR SETUP
; ===============================================

clear_screen:
    ldx #0
    lda #$20
.loop:
    sta SCREEN_RAM,x
    sta SCREEN_RAM+$100,x
    sta SCREEN_RAM+$200,x
    sta SCREEN_RAM+$2e8,x
    inx
    bne .loop
    rts

setup_colors:
    lda #0
    sta BG_COLOR
    sta BORDER_COLOR
    ldx #0
    lda #3
.color_loop:
    sta COLOR_RAM,x
    sta COLOR_RAM+$100,x
    sta COLOR_RAM+$200,x
    sta COLOR_RAM+$2e8,x
    inx
    bne .color_loop
    rts

; ===============================================
; SPRITE INITIALIZATION
; ===============================================

init_sprites:
    ; Copy sprite data to standard sprite memory locations
    ldx #0
.copy_player:
    lda player_sprite,x
    sta $3000,x          ; $3000 = pointer $C0
    inx
    cpx #64
    bne .copy_player

    ldx #0
.copy_enemy:
    lda enemy_sprite,x
    sta $3040,x          ; $3040 = pointer $C1
    inx
    cpx #64
    bne .copy_enemy

    ldx #0
.copy_bullet:
    lda bullet_sprite,x
    sta $3080,x          ; $3080 = pointer $C2
    inx
    cpx #64
    bne .copy_bullet

    ; Set sprite pointers
    lda #$C0
    sta SPRITE_PTR+0    ; Player
    lda #$C1
    sta SPRITE_PTR+1    ; Enemies
    sta SPRITE_PTR+2
    sta SPRITE_PTR+3
    sta SPRITE_PTR+4
    sta SPRITE_PTR+5
    sta SPRITE_PTR+6
    lda #$C2
    sta SPRITE_PTR+7    ; Bullet

    ; Set sprite colors
    lda #1
    sta SPRITE_COLORS+0  ; Player white
    lda #2
    sta SPRITE_COLORS+1  ; Enemies red
    sta SPRITE_COLORS+2
    sta SPRITE_COLORS+3
    sta SPRITE_COLORS+4
    sta SPRITE_COLORS+5
    sta SPRITE_COLORS+6
    lda #14
    sta SPRITE_COLORS+7  ; Bullet light blue

    ; Enable multicolor mode for all sprites
    lda #$ff
    sta SPRITE_MCOLOR_EN ; All sprites in multicolor mode

    ; Set shared multicolor registers
    lda #7               ; Yellow (shared color 1)
    sta SPRITE_MCOLOR1
    lda #3               ; Cyan (shared color 2)
    sta SPRITE_MCOLOR2

    rts

; ===============================================
; GAME STATE INITIALIZATION
; ===============================================

init_game_state:
    ; Player
    lda #160
    sta player_x
    lda #PLAYER_Y
    sta player_y

    ; Enemies
    ldx #0
.init_loop:
    lda enemy_start_x,x
    sta enemy_x,x
    lda #0
    sta enemy_x_msb,x       ; Initialize MSB to 0
    lda enemy_start_y,x
    sta enemy_y,x
    lda #1
    sta enemy_active,x
    inx
    cpx #MAX_ENEMIES
    bne .init_loop

    ; Bullets
    lda #0
    sta bullet_active
    sta score
    sta score+1
    sta fire_pressed
    sta game_over_flag

    ; Lives
    lda #3
    sta lives

    ; Level
    lda #1
    sta level

    ; Direction
    lda #1
    sta enemy_dir
    sta enemy_counter

    rts

; ===============================================
; UPDATE SPRITE DATA FOR MULTIPLEXER
; ===============================================
; Copies game state to virtual sprite tables

update_sprite_data:
    lda #0
    sta num_sprites         ; Count active sprites

    ; Add player sprite (always sprite 0)
    lda player_x
    sta spr_x
    lda #0
    sta spr_x_msb           ; Player always at X < 256
    lda player_y
    sta spr_y
    lda #$C0               ; Player sprite pointer ($3000)
    sta spr_f
    lda #1                 ; Player color (white)
    sta spr_c
    inc num_sprites

    ; Add enemy sprites
    ldx #0
.enemy_loop:
    cpx #MAX_ENEMIES
    beq .add_bullet

    lda enemy_active,x
    beq .next_enemy

    ; Add this enemy
    ldy num_sprites
    lda enemy_x,x
    sta spr_x,y
    lda enemy_x_msb,x
    sta spr_x_msb,y         ; Copy MSB
    lda enemy_y,x
    sta spr_y,y
    lda #$C1               ; Enemy sprite pointer ($3040)
    sta spr_f,y
    lda #2                 ; Enemy color (red)
    sta spr_c,y
    inc num_sprites

.next_enemy:
    inx
    jmp .enemy_loop

.add_bullet:
    lda bullet_active
    beq .done

    ; Add bullet
    ldy num_sprites
    lda bullet_x
    sta spr_x,y
    lda bullet_x_msb
    sta spr_x_msb,y         ; Copy bullet MSB
    lda bullet_y
    sta spr_y,y
    lda #$C2               ; Bullet sprite pointer ($3080)
    sta spr_f,y
    lda #14                ; Bullet color (light blue)
    sta spr_c,y
    inc num_sprites

.done:
    lda #1
    sta spr_update_flag    ; Signal IRQ to sort and display
    rts

; ===============================================
; JOYSTICK INPUT
; ===============================================

read_joystick:
    lda CIA1_PRA
    sta joystick_state
    rts

; ===============================================
; PLAYER UPDATE
; ===============================================

update_player:
    ; Check left
    lda joystick_state
    and #$04
    bne .check_right
    lda player_x
    cmp #SCREEN_LEFT
    bcc .check_right
    dec player_x
    dec player_x

.check_right:
    lda joystick_state
    and #$08
    bne .check_fire
    lda player_x
    cmp #SCREEN_RIGHT
    bcs .check_fire
    inc player_x
    inc player_x

.check_fire:
    lda joystick_state
    and #$10
    bne .fire_released

    lda fire_pressed
    bne .player_done

    jsr shoot_bullet
    lda #1
    sta fire_pressed
    jmp .player_done

.fire_released:
    lda #0
    sta fire_pressed

.player_done:
    rts

; ===============================================
; SHOOTING
; ===============================================

shoot_bullet:
    lda bullet_active
    bne .shoot_done

    lda #1
    sta bullet_active
    lda player_x
    clc
    adc #12
    sta bullet_x
    ; Check for overflow - if carry set, bullet X wrapped past 255
    lda #0
    adc #0              ; Add carry to accumulator (0 + carry)
    sta bullet_x_msb    ; Store MSB (0 or 1)

    lda #PLAYER_Y
    sec
    sbc #16
    sta bullet_y

    jsr sound_shoot         ; Play shoot sound

.shoot_done:
    rts

; ===============================================
; BULLET UPDATE
; ===============================================

update_bullets:
    lda bullet_active
    beq .bullet_done

    lda bullet_y
    sec
    sbc #3
    sta bullet_y

    cmp #20
    bcs .bullet_done

    lda #0
    sta bullet_active

.bullet_done:
    rts

; ===============================================
; ENEMY UPDATE
; ===============================================

update_enemies:
    inc enemy_counter
    lda enemy_counter

    ; Calculate speed threshold based on level: 10 - level (minimum 3)
    ; Save counter for comparison
    sta temp+1

    lda level
    cmp #8              ; Cap at level 8 for max speed
    bcc .calc_speed
    lda #8
.calc_speed:
    sta temp
    lda #10
    sec
    sbc temp            ; A = 10 - level (speed threshold)

    ; Compare threshold with counter
    ; We want to update when counter >= threshold
    cmp temp+1
    bcc .do_update      ; If threshold < counter, do update
    beq .do_update      ; If threshold = counter, do update
    rts                  ; Otherwise threshold > counter, don't update

.do_update:
    lda #0
    sta enemy_counter

.continue_update:
    ; First pass: check if any enemy needs to turn
    lda #0
    sta temp            ; temp = need_turn flag
    ldx #0
.check_loop:
    cpx #MAX_ENEMIES
    beq .done_checking

    lda enemy_active,x
    beq .skip_check

    lda enemy_dir
    bne .check_right_edge

.check_left_edge:
    ; Check if X < 80: MSB must be 0 AND LSB < 80
    lda enemy_x_msb,x
    bne .skip_check     ; If MSB >= 1, then X >= 256 > 80
    lda enemy_x,x
    cmp #80
    bcs .skip_check
    lda #1              ; X < 80, turn right
    sta temp
    jmp .done_checking

.check_right_edge:
    ; Check if X >= 290: MSB must be 1 AND LSB >= 34
    lda enemy_x_msb,x
    beq .skip_check     ; If MSB = 0, then X < 256 < 290
    lda enemy_x,x
    cmp #34             ; 290 - 256 = 34
    bcc .skip_check
    lda #2              ; X >= 290, turn left
    sta temp
    jmp .done_checking

.skip_check:
    inx
    jmp .check_loop

.done_checking:
    ; If need to turn, change direction and move all down
    lda temp
    beq .move_all
    cmp #1
    beq .turn_all_right
    jmp .turn_all_left

.turn_all_right:
    lda #1
    sta enemy_dir
    ldx #0
.move_down_right:
    cpx #MAX_ENEMIES
    beq .move_all
    lda enemy_active,x
    beq .skip_down_right
    lda enemy_y,x
    clc
    adc #10
    sta enemy_y,x
.skip_down_right:
    inx
    jmp .move_down_right

.turn_all_left:
    lda #0
    sta enemy_dir
    ldx #0
.move_down_left:
    cpx #MAX_ENEMIES
    beq .move_all
    lda enemy_active,x
    beq .skip_down_left
    lda enemy_y,x
    clc
    adc #10
    sta enemy_y,x
.skip_down_left:
    inx
    jmp .move_down_left

.move_all:
    ; Move all enemies in current direction
    ldx #0
.move_loop:
    cpx #MAX_ENEMIES
    beq .update_done

    lda enemy_active,x
    beq .skip_move

    lda enemy_dir
    bne .move_right

.move_left:
    lda enemy_x,x
    sec
    sbc #3
    sta enemy_x,x
    bcs .skip_move      ; No underflow
    ; Underflow: decrement MSB
    lda enemy_x_msb,x
    beq .skip_move      ; Already 0, can't go lower
    dec enemy_x_msb,x
    jmp .skip_move

.move_right:
    lda enemy_x,x
    clc
    adc #3
    sta enemy_x,x
    bcc .skip_move      ; No overflow
    ; Overflow: increment MSB
    inc enemy_x_msb,x

.skip_move:
    inx
    jmp .move_loop

.update_done:
    rts

; ===============================================
; COLLISION DETECTION
; ===============================================

check_collisions:
    ; Check bullet-enemy collisions
    lda bullet_active
    beq .check_player_enemy

    ldx #0
.bullet_enemy_loop:
    lda enemy_active,x
    beq .next_bullet_collision

    ; Check X overlap
    lda bullet_x
    sec
    sbc enemy_x,x
    clc
    adc #12
    cmp #24
    bcs .next_bullet_collision

    ; Check Y overlap
    lda bullet_y
    sec
    sbc enemy_y,x
    clc
    adc #12
    cmp #24
    bcs .next_bullet_collision

    ; Hit!
    lda #0
    sta bullet_active
    sta enemy_active,x

    jsr sound_explosion     ; Play explosion sound

    ; Increment score in BCD (0-99)
    sed                 ; Set decimal mode
    lda score
    clc
    adc #1
    sta score
    cld                 ; Clear decimal mode
    jmp .check_player_enemy

.next_bullet_collision:
    inx
    cpx #MAX_ENEMIES
    bne .bullet_enemy_loop

.check_player_enemy:
    ; Check player-enemy collisions
    ldx #0
.player_enemy_loop:
    lda enemy_active,x
    beq .next_player_collision

    ; Check X overlap
    lda player_x
    sec
    sbc enemy_x,x
    clc
    adc #12
    cmp #24
    bcs .next_player_collision

    ; Check Y overlap
    lda player_y
    sec
    sbc enemy_y,x
    clc
    adc #12
    cmp #24
    bcs .next_player_collision

    ; Player hit! Lose a life
    lda #0
    sta enemy_active,x

    lda lives
    beq .collision_done     ; Already dead, don't decrement further
    dec lives

    jsr sound_player_hit    ; Play player hit sound

    lda lives               ; Check if lives is now 0
    bne .collision_done     ; If not 0, continue game

    ; Lives reached 0 - game over
    lda #1
    sta game_over_flag

.next_player_collision:
    inx
    cpx #MAX_ENEMIES
    bne .player_enemy_loop

.collision_done:
    rts

; ===============================================
; LEVEL PROGRESSION
; ===============================================

; Check if all enemies are defeated
check_level_complete:
    ldx #0
.clc_loop:
    lda enemy_active,x
    bne .clc_enemies_remain     ; If any enemy is active, level not complete
    inx
    cpx #MAX_ENEMIES
    bne .clc_loop

    ; All enemies defeated! Start next level
    jsr next_level
    rts

.clc_enemies_remain:
    rts

; Start next level
next_level:
    ; Increment level
    inc level

    ; Reset all enemies to starting positions
    ldx #0
.nl_reset_loop:
    lda enemy_start_x,x
    sta enemy_x,x
    lda #0
    sta enemy_x_msb,x       ; Reset MSB to 0
    lda enemy_start_y,x
    sta enemy_y,x
    lda #1
    sta enemy_active,x
    inx
    cpx #MAX_ENEMIES
    bne .nl_reset_loop

    ; Reset enemy direction and counter
    lda #1
    sta enemy_dir
    lda #0
    sta enemy_counter

    ; Clear any active bullet
    sta bullet_active

    rts

; ===============================================
; SCORE DISPLAY
; ===============================================

draw_score:
    ; Draw "SCORE:"
    ldx #0
.text:
    lda score_text,x
    beq .numbers
    sta SCREEN_RAM,x
    inx
    jmp .text

.numbers:
    lda score
    and #$f0
    lsr
    lsr
    lsr
    lsr
    clc
    adc #48
    sta SCREEN_RAM+7

    lda score
    and #$0f
    clc
    adc #48
    sta SCREEN_RAM+8

    ; Draw "LIVES:"
    ldx #0
.lives_text:
    lda lives_text,x
    beq .lives_num
    sta SCREEN_RAM+40,x
    inx
    jmp .lives_text

.lives_num:
    lda lives
    clc
    adc #48
    sta SCREEN_RAM+40+7

    ; Draw "LEVEL:"
    ldx #0
.level_text:
    lda level_text,x
    beq .level_num
    sta SCREEN_RAM+80,x
    inx
    jmp .level_text

.level_num:
    lda level
    clc
    adc #48
    sta SCREEN_RAM+80+7

    rts

; Draw GAME OVER message
draw_game_over:
    ; Hide all sprites so they don't cover the text
    lda #0
    sta SPRITE_ENABLE       ; Disable all sprites

    ; Display "GAME OVER" in center of screen
    ldx #0
.dgo_text:
    lda game_over_text,x
    beq .dgo_done
    sta SCREEN_RAM+11*40+15,x   ; Row 11, column 15
    inx
    jmp .dgo_text
.dgo_done:
    rts

; ===============================================
; SOUND EFFECTS
; ===============================================

; Initialize SID chip
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

    ; Initialize Voice 1 and 2 with basic settings
    lda #$00
    sta SID_V1_AD
    sta SID_V1_SR
    sta SID_V2_AD
    sta SID_V2_SR

    rts

; Shoot sound effect - quick high beep
sound_shoot:
    ; Set frequency - higher for shoot sound
    lda #$50
    sta SID_V1_FREQ_HI
    lda #$00
    sta SID_V1_FREQ_LO

    ; Set envelope - instant attack, quick decay
    lda #$07                ; Attack=0, Decay=7
    sta SID_V1_AD
    lda #$00                ; Sustain=0, Release=0
    sta SID_V1_SR

    ; Trigger: close gate then open with triangle wave
    lda #$10                ; Triangle wave, gate off
    sta SID_V1_CTRL
    lda #$11                ; Triangle wave, gate on
    sta SID_V1_CTRL
    rts

; Explosion sound effect - noise burst
sound_explosion:
    ; Set frequency - mid-range for explosion
    lda #$20
    sta SID_V2_FREQ_HI
    lda #$00
    sta SID_V2_FREQ_LO

    ; Set envelope - instant attack, longer decay
    lda #$0A                ; Attack=0, Decay=A
    sta SID_V2_AD
    lda #$00                ; Sustain=0, Release=0
    sta SID_V2_SR

    ; Trigger: close gate then open with noise wave
    lda #$80                ; Noise wave, gate off
    sta SID_V2_CTRL
    lda #$81                ; Noise wave, gate on
    sta SID_V2_CTRL
    rts

; Player hit sound effect - lower descending tone
sound_player_hit:
    ; Set frequency - lower for damage
    lda #$18
    sta SID_V1_FREQ_HI
    lda #$00
    sta SID_V1_FREQ_LO

    ; Set envelope - instant attack, medium decay
    lda #$09                ; Attack=0, Decay=9
    sta SID_V1_AD
    lda #$00                ; Sustain=0, Release=0
    sta SID_V1_SR

    ; Trigger: close gate then open with sawtooth wave
    lda #$20                ; Sawtooth wave, gate off
    sta SID_V1_CTRL
    lda #$21                ; Sawtooth wave, gate on
    sta SID_V1_CTRL

    ; Wait for sound to play
    ldx #$30
.delay_hit:
    dex
    bne .delay_hit

    ; Turn off the gate
    lda #$20
    sta SID_V1_CTRL
    rts

; ===============================================
; WAIT FOR FRAME
; ===============================================

wait_frame:
    lda $d012
.wait1:
    cmp $d012
    beq .wait1
    rts

; Wait for IRQ to finish processing sprites
wait_for_irq:
.wait_loop:
    lda spr_update_flag
    bne .wait_loop
    rts

; ===============================================
; SPRITE MULTIPLEXER SYSTEM
; ===============================================
; Professional raster interrupt-based multiplexer

; Initialize the multiplexer
init_multiplexer:
    lda #0
    sta sorted_sprites
    sta spr_update_flag

    ; Init order table with 0,1,2,3... order
    ldx #MAX_SPRITES-1
.init_order:
    txa
    sta sort_order,x
    dex
    bpl .init_order
    rts

; Initialize raster interrupt system
init_raster:
    sei
    lda #<irq1
    sta $0314
    lda #>irq1
    sta $0315
    lda #$7f                ; CIA interrupt off
    sta $dc0d
    lda #$01                ; Raster interrupt on
    sta $d01a
    lda #27                 ; High bit of IRQ position = 0
    sta $d011
    lda #IRQ1_LINE          ; Sorting interrupt line
    sta $d012
    lda $dc0d               ; Acknowledge IRQ
    cli
    rts

; IRQ1: Sorting interrupt (runs at bottom of screen)
irq1:
    dec $d019               ; Acknowledge raster interrupt

    ; Move all sprites to bottom to prevent glitches
    lda #$ff
    sta $d001
    sta $d003
    sta $d005
    sta $d007
    sta $d009
    sta $d00b
    sta $d00d
    sta $d00f

    ; Check if new sprites need sorting
    lda spr_update_flag
    beq .check_display

    lda #0
    sta spr_update_flag
    lda num_sprites
    sta sorted_sprites
    beq .check_display      ; If zero, check if we have sprites to display

    ; Sort sprites by Y coordinate
    jsr sort_sprites

.check_display:
    ; Check if game is over - if so, don't enable sprites
    lda game_over_flag
    bne .no_sprites_at_all

    ; Always display sorted sprites each frame
    ldx sorted_sprites
    beq .no_sprites_at_all   ; If zero sprites, skip display
    cpx #9
    bcc .not_more_than_8
    ldx #8
.not_more_than_8:
    lda d015_table,x
    sta $d015

    ; Set up display interrupt
    lda #0
    sta spr_irq_counter
    lda #<irq2
    sta $0314
    lda #>irq2
    sta $0315
    lda #IRQ2_LINE          ; Start display interrupt
    sta $d012
    jmp $ea81               ; Return from IRQ

.no_sprites_at_all:
    lda #0
    sta $d015               ; Disable all sprites
    jmp $ea81               ; Return from IRQ

; Sort sprites by Y coordinate
sort_sprites:
    ; Clear unused sprite Y positions
    ldx #MAX_SPRITES
    dex
    cpx sorted_sprites
    bcc sort_clear_done
    lda #$ff
sort_clear_loop:
    sta spr_y,x
    dex
    cpx sorted_sprites
    bcs sort_clear_loop

sort_clear_done:
    ; Insertion sort on order table
    ldx #0
sort_main_loop:
    ldy sort_order+1,x
    lda spr_y,y
    ldy sort_order,x
    cmp spr_y,y
    bcs sort_skip_swap

    ; Swap needed - store X for later reload
    stx sort_temp_x
sort_swap_loop:
    lda sort_order+1,x
    pha
    lda sort_order,x
    sta sort_order+1,x
    pla
    sta sort_order,x
    cpx #0
    beq sort_reload_x
    dex
    ldy sort_order+1,x
    lda spr_y,y
    ldy sort_order,x
    cmp spr_y,y
    bcc sort_swap_loop

sort_reload_x:
    ldx sort_temp_x
sort_skip_swap:
    inx
    cpx #MAX_SPRITES-1
    bcc sort_main_loop

    ; Copy sorted data
    ldx sorted_sprites
    lda #$ff
    sta sort_spr_y,x        ; End marker

    ldx #0
sort_copy_loop:
    ldy sort_order,x
    lda spr_y,y
    sta sort_spr_y,x
    lda spr_x,y
    sta sort_spr_x,x
    lda spr_x_msb,y
    sta sort_spr_x_msb,x    ; Copy MSB
    lda spr_f,y
    sta sort_spr_f,x
    lda spr_c,y
    sta sort_spr_c,x
    inx
    cpx sorted_sprites
    bcc sort_copy_loop
    rts

; IRQ2: Display interrupt (runs multiple times per frame)
irq2:
    dec $d019               ; Acknowledge raster interrupt

irq2_direct:
    ldy spr_irq_counter     ; Get sprite index
    lda sort_spr_y,y        ; Get Y of first sprite to display
    clc
    adc #$10                ; 16 lines down is endpoint
    bcc irq2_not_over
    lda #$ff                ; Cap at $ff
irq2_not_over:
    sta temp_var

    ; Display sprites until we reach endpoint
irq2_sprite_loop:
    lda sort_spr_y,y
    cmp temp_var
    bcs irq2_end_sprites

    ; Set sprite position
    ldx phys_spr_tbl_2,y    ; Physical sprite * 2
    sta $d001,x             ; Set Y
    lda sort_spr_x,y
    sta $d000,x             ; Set X LSB

    ; Handle X MSB for this sprite
    lda sort_spr_x_msb,y
    beq .msb_clear
    ; Set MSB bit for this sprite
    ldx phys_spr_tbl_1,y    ; Physical sprite number
    lda d015_msb_tbl,x      ; Get bit mask for this sprite
    ora $d010               ; Set the bit
    sta $d010
    jmp .msb_done
.msb_clear:
    ; Clear MSB bit for this sprite
    ldx phys_spr_tbl_1,y
    lda d015_msb_tbl,x
    eor #$ff                ; Invert mask
    and $d010               ; Clear the bit
    sta $d010
.msb_done:

    ; Set sprite pointer and color
    ldx phys_spr_tbl_1,y    ; Physical sprite * 1
    lda sort_spr_f,y
    sta SPRITE_PTR,x
    lda sort_spr_c,y
    sta SPRITE_COLORS,x

    iny
    bne irq2_sprite_loop

irq2_end_sprites:
    cmp #$ff                ; Was it the end marker?
    beq irq2_last_sprite

    ; More sprites to come, set up next interrupt
    sty spr_irq_counter
    sec
    sbc #$10
    cmp $d012
    bcc irq2_direct         ; Already late? Go direct
    sta $d012
    jmp $ea81

irq2_last_sprite:
    ; Last sprite displayed, return to sorting IRQ
    lda #<irq1
    sta $0314
    lda #>irq1
    sta $0315
    lda #IRQ1_LINE
    sta $d012
    jmp $ea81


; ===============================================
; DATA SECTION
; ===============================================

player_x:              !byte 0
player_y:              !byte 0
joystick_state:        !byte 0
fire_pressed:          !byte 0
sprite_cycle:          !byte 0
temp:                  !byte 0
enemy_display_offset:  !byte 0

enemy_x:        !fill MAX_ENEMIES, 0
enemy_x_msb:    !fill MAX_ENEMIES, 0    ; 9th bit for X coordinates (0 or 1)
enemy_y:        !fill MAX_ENEMIES, 0
enemy_active:   !fill MAX_ENEMIES, 0
enemy_dir:      !byte 1
enemy_counter:  !byte 0

bullet_x:       !byte 0
bullet_x_msb:   !byte 0
bullet_y:       !byte 0
bullet_active:  !byte 0

score:          !byte 0, 0
lives:          !byte 3
game_over_flag: !byte 0
level:          !byte 1

; 24 enemies in 4 rows of 6 - 26 pixel spacing horizontal, 30 pixel spacing vertical
; All enemies in same row at exact same Y coordinate
; Vertical spacing ensures no overlap between rows (sprites are 21 pixels tall)
; Properly centered at X=184: formation spans 119-249, moves 80-290
enemy_start_x:  !byte 119, 145, 171, 197, 223, 249, 119, 145, 171, 197, 223, 249
                !byte 119, 145, 171, 197, 223, 249, 119, 145, 171, 197, 223, 249
enemy_start_y:  !byte 50, 50, 50, 50, 50, 50, 80, 80, 80, 80, 80, 80
                !byte 110, 110, 110, 110, 110, 110, 140, 140, 140, 140, 140, 140

score_text:     !scr "score:", 0
lives_text:     !scr "lives:", 0
level_text:     !scr "level:", 0
game_over_text: !scr "game over", 0

; ===============================================
; MULTIPLEXER DATA TABLES
; ===============================================

; Multiplexer control variables
num_sprites:        !byte 0
spr_update_flag:    !byte 0
sorted_sprites:     !byte 0
spr_irq_counter:    !byte 0
temp_var:           !byte 0
sort_temp_x:        !byte 0

; Virtual sprite tables (unsorted)
spr_x:              !fill MAX_SPRITES, 0
spr_x_msb:          !fill MAX_SPRITES, 0    ; MSB for X coordinates
spr_y:              !fill MAX_SPRITES, 0
spr_f:              !fill MAX_SPRITES, 0    ; Frame/pointer
spr_c:              !fill MAX_SPRITES, 0    ; Color

; Sort order table
sort_order:         !fill MAX_SPRITES, 0

; Sorted sprite tables
sort_spr_x:         !fill MAX_SPRITES, 0
sort_spr_x_msb:     !fill MAX_SPRITES, 0    ; MSB for sorted X
sort_spr_y:         !fill MAX_SPRITES+1, 0  ; +1 for $ff end marker
sort_spr_f:         !fill MAX_SPRITES, 0
sort_spr_c:         !fill MAX_SPRITES, 0

; Sprite enable table for $d015
d015_table:         !byte %00000000
                    !byte %00000001
                    !byte %00000011
                    !byte %00000111
                    !byte %00001111
                    !byte %00011111
                    !byte %00111111
                    !byte %01111111
                    !byte %11111111

; MSB bit masks for $d010 (one bit per sprite)
d015_msb_tbl:       !byte %00000001  ; Sprite 0
                    !byte %00000010  ; Sprite 1
                    !byte %00000100  ; Sprite 2
                    !byte %00001000  ; Sprite 3
                    !byte %00010000  ; Sprite 4
                    !byte %00100000  ; Sprite 5
                    !byte %01000000  ; Sprite 6
                    !byte %10000000  ; Sprite 7

; Physical sprite mapping tables
phys_spr_tbl_1:     !byte 0,1,2,3,4,5,6,7
                    !byte 0,1,2,3,4,5,6,7
                    !byte 0,1,2,3,4,5,6,7
                    !byte 0,1,2,3,4,5,6,7

phys_spr_tbl_2:     !byte 0,2,4,6,8,10,12,14
                    !byte 0,2,4,6,8,10,12,14
                    !byte 0,2,4,6,8,10,12,14
                    !byte 0,2,4,6,8,10,12,14

; ===============================================
; SPRITE DATA
; ===============================================

player_sprite:
    ; Multicolor player ship - simple symmetrical triangle design
    ; 00=transparent, 01=yellow, 10=white, 11=cyan
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00100000, %00000000   ; T T T T T T W T T T T T
    !byte %00000000, %10101000, %00000000   ; T T T T W W W W T T T T
    !byte %00000000, %10101000, %00000000   ; T T T T W W W W T T T T
    !byte %00001010, %10101010, %10000000   ; T T W W W W W W W W T T
    !byte %00001010, %10101010, %10000000   ; T T W W W W W W W W T T
    !byte %00101010, %10101010, %10100000   ; T W W W W W W W W W W T
    !byte %10101010, %10101010, %10101000   ; W W W W W W W W W W W W
    !byte %10100000, %00000000, %00101000   ; W W T T T T T T T T W W
    !byte %00100000, %00000000, %00100000   ; T W T T T T T T T T W T
    !byte %00000001, %00000001, %00000000   ; T T T Y T T T Y T T T T
    !byte %00000001, %00000001, %00000000   ; T T T Y T T T Y T T T T
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000                         ; Padding byte to make 64 bytes

enemy_sprite:
    ; Multicolor enemy - classic Galaga-style alien
    ; 00=transparent, 01=yellow, 10=red, 11=cyan
    !byte %00000000, %00000000, %00000000
    !byte %00000001, %01010000, %00000000   ; Antennae (yellow)
    !byte %00000010, %10101000, %00000000   ; Head
    !byte %00001010, %10101010, %00000000
    !byte %00001001, %01001010, %00000000   ; Eyes (yellow)
    !byte %00001010, %10101010, %00000000
    !byte %00101010, %10101010, %10000000   ; Body
    !byte %00101010, %10101010, %10000000
    !byte %10101111, %11111110, %10100000   ; Wing band (cyan)
    !byte %10101010, %10101010, %10100000
    !byte %00101010, %10101010, %10000000
    !byte %00001010, %10101010, %00000000
    !byte %00000010, %10101000, %00000000   ; Lower body
    !byte %00000001, %01010000, %00000000   ; Legs (yellow)
    !byte %00000001, %01010000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000                         ; Padding byte to make 64 bytes

bullet_sprite:
    ; Multicolor bullet - simple energy projectile
    ; 00=transparent, 01=yellow, 10=light blue, 11=cyan
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %10000000, %00000000   ; Tip
    !byte %00000000, %10000000, %00000000
    !byte %00000000, %11000000, %00000000   ; Bright center (cyan)
    !byte %00000000, %11000000, %00000000
    !byte %00000000, %10000000, %00000000
    !byte %00000000, %10000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000, %00000000, %00000000
    !byte %00000000                         ; Padding byte to make 64 bytes
