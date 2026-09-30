; ===============================================
; C64 GALAGA CLONE
; ===============================================
; A Galaga-style shooter with raster interrupt sprite multiplexing
; Based on Cadaver's sprite multiplexer technique
;
; Build:  make          (acme)
; Debug:  acme -DAUTOPLAY=1 ...   synthetic joystick input, for headless tests
;         add -DNOFIRE=1 to stop shooting during play (tests player death)
;         -DDUAL=1 dual fighter at start, -DCAPTURE=1 scripted capture, -DFEW=1 three bees per stage,
;         -DBOSSDIVE=1 boss 1 always dives (escort test), -DSTAGE=n start at stage n,
;         -DFORCEPERFECT=1 challenge stages count as perfect,
;         -DHALT=n freeze after n frames, -DHALTOVER=1 freeze at game over (tests/run.sh)
; ===============================================

!cpu 6510

!src "src/constants.asm"

; ===============================================
; PROGRAM START
; ===============================================

* = $0801                     ; BASIC start address

; BASIC stub: 10 SYS 2064
!byte $0c,$08,$0a,$00,$9e,$20,$32,$30,$36,$34,$00,$00,$00

* = $0810                     ; Program start

!zone init
init:
    jsr setup_colors
    jsr init_sprites
    jsr init_sound
    jsr init_multiplexer
    lda #$a5
    sta rnd
    jsr init_stars
    jsr init_raster
    jsr enter_title

!zone game_loop
game_loop:
!ifdef HALT {
    inc halt_cnt                ; -DHALT=n: freeze after n frames (screenshot tests)
    bne .h_lo
    inc halt_cnt+1
.h_lo:
    lda halt_cnt
    cmp #<HALT
    bne .h_go
    lda halt_cnt+1
    cmp #>HALT
    bne .h_go
.h_stop:
    jmp .h_stop                 ; The raster IRQ keeps showing the last frame
.h_go:
}
    inc frame
    lda frame
    lsr
    lsr
    lsr
    lsr
    and #1
    cmp anim
    beq .same_anim
    sta anim                    ; Wing flap toggles every 16 frames
    jsr refresh_anim
.same_anim:
    jsr read_joystick
    jsr update_stars
    jsr snd_tick
    jsr run_state
    jsr update_sprite_data      ; Update sprites for IRQ multiplexer
    jsr wait_for_irq            ; CRITICAL: Wait for IRQ to finish! Paces the loop to 1 frame
    lda game_state
    beq game_loop               ; Title screen has no HUD
    lda frame
    and #3
    bne game_loop               ; HUD digits refresh every 4th frame
    jsr draw_hud
    jmp game_loop

!zone run_state
run_state:
    ldx game_state
    beq .title
    dex
    beq .intro
    dex
    beq .play
    dex
    beq .dying
    dex
    beq .over
    dex
    beq .capt
    jmp st_result
.capt:
    jmp st_captured
.over:
    jmp st_gameover
.title:
    jmp st_title
.intro:
    jmp st_intro
.play:
    jmp st_play
.dying:
    jmp st_dying

; ===============================================
; MODULES (in memory order, sprite art last)
; ===============================================

!src "src/states.asm"
!src "src/screen.asm"
!src "src/sprites.asm"
!src "src/player.asm"
!src "src/enemies.asm"
!src "src/combat.asm"
!src "src/capture.asm"
!src "src/challenge.asm"
!src "src/progress.asm"
!src "src/sound.asm"
!src "src/multiplexer.asm"
!src "src/data.asm"
!src "src/art.asm"
