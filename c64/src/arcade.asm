; The dive scheduler, escorts and bombs of the arcade Galaga, on the C64's layout of 32 aliens.
; This is psp/game.c with -DRULES_ARCADE32 in 6502: keep the names and the order, and check a change with
; tools/compare_6502.py c64. The numbers are in arcade_data.asm (tools/gen_arcade.py).
;
; The arcade runs its scheduler at 60 Hz and the C64 game at 50: update_dives runs 6 arcade frames (arc_frame) for every 5 ticks.
; A diver drops a bomb at every set bit of its bomb flags, one every 20 arcade frames, high on the screen; the flags come from the
; stage and the number of aliens left. Three sortie timers (boss, butterfly, bee) count in steps of 16 arcade frames.

arc_clk:        !byte 0         ; 5ths of an arcade frame
arc_af:         !byte 0         ; arcade frames in this stage
arc_tmr2:       !byte 0         ; counts down from 120 once in 32 frames (the time since the stage began)
arc_hold:       !byte 0         ; no bombs after a boss was shot while it dived (counts down once in 32 frames)
arc_sortie:     !byte 0, 0, 0   ; sortie timers: boss, butterfly, bee
arc_wingm:      !byte 0         ; boss sorties so far (every second one tries to capture)
arc_bflags:     !byte 0         ; bomb flags for the divers that start now
arc_sidx:       !byte 0         ; row of the stage in the tables
arc_nalive:     !byte 0
arc_nfly:       !byte 0
arc_tens:       !byte 0
arc_maxb:       !byte 0
arc_cont:       !byte 0
arc_reload:     !byte 0, 0, 0
arc_idx:        !byte 0
arc_tmp:        !byte 0
st_from:        !byte 0
st_to:          !byte 0
st_cap:         !byte 0
st_peel:        !byte 0
arc_c:          !byte 0
arc_cc:         !byte 0
arc_b:          !byte 0
arc_ixl:        !byte 0
arc_slot:       !byte 0
arc_ne:         !byte 0
arc_nesc:       !byte 0
arc_esc:        !byte 0, 0
q16:            !word 0
r16:            !byte 0
dv8:            !byte 0
sgn:            !byte 0
a_bfl:          !fill MAX_ENEMIES, 0    ; bomb flags of a diver
a_btm:          !fill MAX_ENEMIES, 0    ; arcade frames to its next bomb flag
eb_ax:          !fill EBN, 0            ; the sideways remainder of a bomb, in 16ths of a pixel

boss_for_b:     !byte 0, 1, 3, 2, 0
arc_wingmen:    !byte 10, 9, 8, 7, 6, 5 ; the six butterflies that escort a boss, in the order of the arcade table

; A new stage: the clocks and the sortie timers
!zone arc_reset
arc_reset:
    lda #0
    sta arc_clk
    sta arc_af
    sta arc_wingm
    sta arc_bflags
    sta arc_hold
    lda #120
    sta arc_tmr2
    lda #22
    sta arc_sortie
    lda #2
    sta arc_sortie+1
    sta arc_sortie+2
    lda stage                   ; the arcade repeats stages 23..26 (its tables stop there)
    cmp #27
    bcc .ok
    sbc #23
    and #3
    clc
    adc #23
.ok:
    sec
    sbc #1
    sta arc_sidx
    rts

; Every tick: 6 arcade frames for every 5 ticks
!zone update_dives
update_dives:
!ifdef NODIVE {
    rts                         ; -DNODIVE=1: no sorties (tools/compare_6502.py)
}
    lda arc_clk
    clc
    adc #6
.c:
    cmp #5
    bcc .d
    sbc #5
    sta arc_clk
    jsr arc_frame
    lda arc_clk
    jmp .c
.d:
    sta arc_clk
    rts

; One arcade frame
!zone arc_frame
arc_frame:
    inc arc_af
    lda arc_af
    and #31
    bne .nt
    lda arc_tmr2
    beq .h
    dec arc_tmr2
.h:
    lda arc_hold
    beq .nt
    dec arc_hold
.nt:
    lda ent_start               ; while the aliens fly in nobody dives or bombs: the clocks are all there is to do
    bne .rts
    jsr arc_bombs
    lda arc_af                  ; Sorties: every 16 arcade frames (the parameters are needed only now)
    and #15
    bne .rts
    jsr arc_params
    ldx #0
.tm:
    dec arc_sortie,x
    beq .due
    inx
    cpx #3
    bne .tm
.rts:
    rts
.due:
    lda arc_nfly
    cmp arc_maxb
    bcc .go
    inc arc_sortie,x            ; too many are flying: try again in a moment
    rts
.go:
    lda arc_reload,x
    sta arc_sortie,x
    cpx #2
    beq .bee
    cpx #1
    beq .red
    jmp arc_sortie_boss
.bee:
    lda #18                     ; the bees are the slots 18..31
    ldy #32
    bne .sb
.red:
    lda #4                      ; the butterflies 4..17
    ldy #18
.sb:
    sty st_to
    sta st_from
    jsr arc_standby
    bmi .rts
    tax
    lda #0
    ldy #20
    jmp start_dive

; The aliens that are alive and that fly, the parameters of this frame: bomb flags, most divers, sortie reloads
!zone arc_params
arc_params:
    lda #0
    sta arc_nalive
    sta arc_nfly
    ldx #MAX_ENEMIES-1
.cnt:
    lda enemy_state,x
    beq .cn
    cmp #4
    beq .cn
    inc arc_nalive
    cmp #2
    beq .fl
    cmp #3
    beq .fl
    cmp #5
    bne .cn
.fl:
    inc arc_nfly
.cn:
    dex
    bpl .cnt
    lda #0                      ; tens = alive / 10
    sta arc_tens
    lda arc_nalive
.ten:
    cmp #10
    bcc .tens
    sbc #10
    inc arc_tens
    bne .ten
.tens:
    ldy arc_sidx
    lda arc_p4,y                ; the most divers p4; p5 when the stage is older than 60 counts of tmr2
    sta arc_maxb
    lda arc_tmr2
    cmp #60
    bcs .mb
    lda arc_p5,y
    sta arc_maxb
.mb:
    lda arc_p0,y                ; bomb flags: row p0 of the table, by the tens of aliens
    asl
    asl
    clc
    adc arc_tens
    tax
    lda arc_bomb_tab,x
    sta arc_bflags
    lda arc_nalive              ; bombs without a pause when few are left: alive < p7
    cmp arc_p7,y
    lda #0
    rol                         ; 1 = alive >= p7
    eor #1
    sta arc_cont
    lda #0                      ; idx = (tmr2 < 40) + (tmr2 == 0)
    sta arc_idx
    lda arc_tmr2
    cmp #40
    bcs .i1
    inc arc_idx
.i1:
    lda arc_tmr2
    bne .i2
    inc arc_idx
.i2:
    lda arc_cont
    beq .reloads
    lda #2
    sta arc_reload
    sta arc_reload+1
    sta arc_reload+2
    rts
.reloads:
    lda arc_p1,y                ; boss: bomb_tab[32 + 4 * p1 + tens]
    asl
    asl
    clc
    adc arc_tens
    tax
    lda arc_bomb_tab+32,x
    sta arc_reload
    lda arc_p2,y                ; butterfly: red[3 * p2 + idx]
    sta arc_tmp
    asl
    clc
    adc arc_tmp
    clc
    adc arc_idx
    tax
    lda arc_red_reload,x
    sta arc_reload+1
    lda arc_p3,y                ; bee: bee[3 * p3 + idx]
    sta arc_tmp
    asl
    clc
    adc arc_tmp
    clc
    adc arc_idx
    tax
    lda arc_bee_reload,x
    sta arc_reload+2
    rts

; The divers drop their bombs: at every set bit of the flags, every 20 arcade frames, not low on the screen, not while hold
!zone arc_bombs
arc_bombs:
    ldx #0
.bl:
    lda enemy_state,x
    cmp #2
    bne .bn
    cpx cap_boss                ; a capture dive drops nothing
    bne .bt
    lda cap_state
    cmp #1
    beq .bn
.bt:
    dec a_btm,x
    bne .bn
    lda #20
    sta a_btm,x
    lda a_bfl,x
    and #1
    beq .shift
    lda arc_hold
    bne .shift
    lda enemy_y,x               ; y <= 163
    cmp #164
    bcs .shift
    jsr spawn_ebullet
.shift:
    lsr a_bfl,x
.bn:
    inx
    cpx #MAX_ENEMIES
    bne .bl
    rts

; The first alien from st_from to st_to-1 that is home and has settled: A (N flag set: none)
!zone arc_standby
arc_standby:
    ldx st_from
.l:
    lda enemy_state,x
    cmp #1
    bne .n
    lda enemy_timer,x
    bne .n
    txa
    rts
.n:
    inx
    cpx st_to
    bne .l
    lda #255
    rts

; Is alien X home and settled? Z clear: yes
!zone is_standby
is_standby:
    lda enemy_state,x
    cmp #1
    bne .no
    lda enemy_timer,x
    bne .no
    lda #1
    rts
.no:
    lda #0
    rts

; A sortie of a boss: a capture attempt every second time, else a boss with the escorts the wingman table gives (game.c arc_sortie_boss)
!zone arc_sortie_boss
arc_sortie_boss:
    lda cap_state
    bne .wing
    inc arc_wingm
    lda arc_wingm
    and #1
    bne .wing
    lda dual
    bne .wing
    lda #0                      ; a capture attempt
    sta st_from
    lda #4
    sta st_to
    jsr arc_standby
    bpl .cap
    rts
.cap:
    tax
    lda #1
    ldy #20
    jmp start_dive
.wing:
    lda #0                      ; which of the six wingmen are home
    sta arc_c
    ldy #0
.bits:
    ldx arc_wingmen,y
    jsr is_standby
    sta arc_tmp
    lda arc_c
    asl
    ora arc_tmp
    sta arc_c
    iny
    cpy #6
    bne .bits
    lda #255
    sta arc_slot
    lda #0
    sta arc_ixl
.ixl:
    lda arc_c
    sta arc_cc
    lda #4
    sta arc_b
.bb:
    lda arc_cc
    and #7
    sta arc_tmp
    lda arc_ixl
    bne .one
    lda arc_tmp                 ; two wingmen: the pattern 011, 111 or 110 (not 100, nothing under 3)
    cmp #4
    beq .no
    cmp #3
    bcs .ok
    bcc .no
.one:
    lda arc_tmp
    beq .no
.ok:
    ldy arc_b
    ldx boss_for_b,y
    jsr is_standby
    beq .no
    stx arc_slot
    lda #2
    sec
    sbc arc_ixl
    sta arc_ne
    jmp .matched
.no:
    lsr arc_cc
    dec arc_b
    bne .bb
    inc arc_ixl
    lda arc_ixl
    cmp #2
    bne .ixl
    lda #0                      ; a boss alone
    sta st_from
    lda #4
    sta st_to
    jsr arc_standby
    bpl .alone
.rts:
    rts
.alone:
    tax
    lda #0
    ldy #20
    jmp start_dive
.matched:
    lda arc_b                   ; b = B + 1
    clc
    adc #1
    sta arc_b
    lda #0
    sta arc_nesc
    ldy arc_ne
    sty arc_ixl                 ; (k counts down from n)
.ek:
    lda arc_cc                  ; rotate right: cy = the bit that falls out
    lsr
    php
    bcc .r0
    ora #$80
.r0:
    sta arc_cc
    plp
    bcs .have
    dec arc_b
    lda arc_cc
    lsr
    php
    bcc .r1
    ora #$80
.r1:
    sta arc_cc
    plp
    bcs .have
    dec arc_b
.have:
    lda arc_b
    bmi .skip
    cmp #6
    bcs .skip
    tay
    lda arc_wingmen,y
    ldy arc_nesc
    sta arc_esc,y
    inc arc_nesc
.skip:
    dec arc_b
    dec arc_ixl
    bne .ek
    ldy #0                      ; the escorts belong to the boss
.se:
    cpy arc_nesc
    beq .sd
    ldx arc_esc,y
    lda arc_slot
    clc
    adc #1
    sta enemy_esc,x
    iny
    bne .se
.sd:
    ldx arc_slot
    lda #0
    ldy #20
    jsr start_dive
    ldy #0
.sk:
    cpy arc_nesc
    bne .sk1
    rts
.sk1:
    sty arc_ixl
    ldx arc_esc,y
    tya                         ; the peel: 26 ticks for the first escort, 32 for the second
    asl
    sta arc_tmp
    asl
    clc
    adc arc_tmp
    clc
    adc #26
    tay
    lda #0
    jsr start_dive
    ldy arc_ixl
    iny
    bne .sk

; Alien X starts a dive: A = 1 for a capture dive, Y = ticks to wait in the slot
!zone start_dive
start_dive:
    sta st_cap
    sty st_peel
    lda #2
    sta enemy_state,x
    lda st_peel
    sta enemy_timer,x
    lda #24                     ; swoop sound
    sta swoop_cnt
    lda st_cap
    beq .notcap
    lda #1                      ; the capture boss: it is on its way to the beam
    sta cap_state
    stx cap_boss
    lda enemy_x,x               ; it peels off towards the ship: dir 1 (right) when x < px
    cmp player_x
    lda enemy_x_msb,x
    sbc player_x_msb
    lda #0
    rol                         ; carry set: x >= px
    eor #1
    sta enemy_dir,x
    jmp .init
.notcap:
    lda enemy_x_msb,x           ; x >= 184: peel off to the right
    bne .right
    lda enemy_x,x
    cmp #184
    bcs .right
    lda #0
    beq .dir
.right:
    lda #1
.dir:
    sta enemy_dir,x
.init:
    lda arc_bflags
    sta a_bfl,x
    lda #30
    sta a_btm,x
    rts

; ===============================================
; ENEMY BOMBS
; ===============================================
; Aimed at the ship when they are dropped: the sideways speed is dx / 16 pixels a tick, at most 0.6 of the fall speed.

; q16 = q16 / dv8 (16 bits by 8 bits)
!zone div16_8
div16_8:
    lda #0
    sta r16
    ldy #16
.l:
    asl q16
    rol q16+1
    rol r16
    lda r16
    cmp dv8
    bcc .n
    sbc dv8
    sta r16
    inc q16
.n:
    dey
    bne .l
    rts

; Alien X drops a bomb (nothing when all are on the screen). Keeps X.
!zone spawn_ebullet
spawn_ebullet:
    ldy #0
.f:
    lda eb_active,y
    beq .got
    iny
    cpy #EBN
    bne .f
    rts
.got:
    lda #1
    sta eb_active,y
    lda enemy_x,x
    sta eb_x,y
    lda enemy_x_msb,x
    sta eb_msb,y
    lda enemy_y,x
    clc
    adc #8
    sta eb_y,y
    lda #0
    sta eb_ax,y
    tya                         ; the divisions use Y
    pha
    lda player_y                ; den = (py - y) * 2 / 5 + 1
    sec
    sbc eb_y,y
    asl
    sta q16
    lda #0
    rol
    sta q16+1
    lda #5
    sta dv8
    jsr div16_8
    lda q16
    clc
    adc #1
    sta dv8
    lda player_x                ; d = px - x; |d| * 16 / den, then the sign
    sec
    sbc enemy_x,x
    sta q16
    lda player_x_msb
    sbc enemy_x_msb,x
    sta q16+1
    sta sgn
    bpl .pos
    lda #0
    sec
    sbc q16
    sta q16
    lda #0
    sbc q16+1
    sta q16+1
.pos:
    asl q16
    rol q16+1
    asl q16
    rol q16+1
    asl q16
    rol q16+1
    asl q16
    rol q16+1
    jsr div16_8
    pla
    tay
    lda q16+1
    bne .max
    lda q16
    cmp #24
    bcc .ok
.max:
    lda #24
    sta q16
.ok:
    lda sgn
    bpl .store
    lda #0
    sec
    sbc q16
    sta q16
.store:
    lda q16
    sta eb_dx,y
    rts

; The bombs fall (2 or 3 pixels a tick) and drift
!zone update_ebullets
update_ebullets:
    ldx #EBN-1
.l:
    lda eb_active,x
    beq .n
    lda frame
    and #1
    clc
    adc #2
    clc
    adc eb_y,x
    sta eb_y,x
    cmp #250
    bcc .move
    lda #0
    sta eb_active,x
    jmp .n
.move:
    lda eb_ax,x                 ; ax += dx; x += ax >> 4 (rounded down); ax &= 15
    clc
    adc eb_dx,x
    sta arc_tmp
    and #15
    sta eb_ax,x
    lda arc_tmp
    cmp #$80                    ; arithmetic shift right by 4: -3..2
    ror
    cmp #$80
    ror
    cmp #$80
    ror
    cmp #$80
    ror
    bpl .posx
    clc
    adc eb_x,x
    sta eb_x,x
    lda eb_msb,x
    adc #$ff
    sta eb_msb,x
    jmp .n
.posx:
    clc
    adc eb_x,x
    sta eb_x,x
    lda eb_msb,x
    adc #0
    sta eb_msb,x
.n:
    dex
    bpl .l
    rts

!src "src/arcade_data.asm"
