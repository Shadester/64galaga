; The arcade rules (40 aliens): a translation of psp/game.c under RULES_ARCADE. Names follow game.c.
; Positions of the aliens are signed 16-bit numbers (ax, ay) in C64 sprite coordinates, as in game.c: paths leave the screen.
; update_sprite_data (sprites.s, arc_sync_aliens) turns them into the sprite tables that view.s draws.
; enemy_state: 0 dead, 1 formation, 2 dive, 3 return, 4 explode, 5 beam, 7 entering (or a challenge stage flight).
; enemy_flag (ent): 0 waiting, 1 on its path, 2 homing on its slot.

; d16 = a - t (16 bits): a = alo/ahi indexed by X, t = a zero page word
.macro diff16 alo, ahi, t
        lda alo,x
        sec
        sbc t
        sta d16
        lda ahi,x
        sbc t+1
        sta d16+1
.endmacro

ax_lo:          .res MAX_ENEMIES
ax_hi:          .res MAX_ENEMIES
ay_lo:          .res MAX_ENEMIES
ay_hi:          .res MAX_ENEMIES
a_dly_lo:       .res MAX_ENEMIES        ; ticks to the launch
a_dly_hi:       .res MAX_ENEMIES
a_ps_lo:        .res MAX_ENEMIES        ; steps made on the path
a_ps_hi:        .res MAX_ENEMIES
a_path:         .res MAX_ENEMIES        ; entry path
s_plo:          .res MAX_ENEMIES        ; the bit stream of the path: next byte, the byte that is being read, bits left, last dx, dy
s_phi:          .res MAX_ENEMIES
s_cur:          .res MAX_ENEMIES
s_cnt:          .res MAX_ENEMIES
s_pdx:          .res MAX_ENEMIES
s_pdy:          .res MAX_ENEMIES

form_pos:       .byte 0                 ; swing position -32..32
form_sdir:      .byte 1                 ; +1 / -1
form_fdx:       .byte 0                 ; the shift of the formation in pixels (signed)
form_breathe:   .byte 0
form_bstep:     .byte 0
form_ff:        .byte 0                 ; frame of the formation clock (arcade frames)
form_clk:       .byte 0                 ; 6 arcade frames for every 5 ticks
chal_t_lo:      .byte 0                 ; ticks of a challenge stage
chal_t_hi:      .byte 0
cur_brx:        .res 10                 ; breathing: the shift of every column and row now
cur_bry:        .res 5
d16:            .res 2
t8:             .byte 0
racc:           .byte 0
rcnt:           .byte 0

a_dpath:        .res MAX_ENEMIES        ; dive path (255: none), bomb flags, frames to the next bomb, 1 = a capture dive
a_bfl:          .res MAX_ENEMIES
a_btm:          .res MAX_ENEMIES
a_cap:          .res MAX_ENEMIES
a_wait_lo:      .res MAX_ENEMIES        ; ticks that a returning alien waits above the screen
a_wait_hi:      .res MAX_ENEMIES
arc_tmr2:       .byte 120               ; counts down from 120 once in 32 arcade frames (time since the stage began)
arc_hold:       .byte 0                 ; no bombs after a diving boss was shot
arc_wingm:      .byte 0
arc_bflags:     .byte 0                 ; the bomb flags of the sorties now
arc_af:         .byte 0                 ; arcade frames of the scheduler
arc_clk:        .byte 0
arc_sortie:     .res 3
arc_reload:     .res 3
arc_nalive:     .byte 0
arc_nfly:       .byte 0
arc_tens:       .byte 0
arc_maxb:       .byte 0
arc_cont:       .byte 0
arc_c:          .byte 0                 ; sortie of a boss: which wingmen are home, the match, the escorts
arc_cc:         .byte 0
arc_b:          .byte 0
arc_ixl:        .byte 0
arc_slot:       .byte 0
arc_ne:         .byte 0
arc_esc:        .res 2
arc_nesc:       .byte 0
q16:            .res 2                  ; division
r16:            .res 2
dv8:            .byte 0
sgn:            .byte 0

; ---------------------------------------------------------------------------------------------
; 16-bit helpers
; ---------------------------------------------------------------------------------------------

; (tl, th) += signed A
add_s8:
        pha
        clc
        adc tgt
        sta tgt
        pla
        bpl @p
        lda tgt+1
        adc #$ff
        sta tgt+1
        rts
@p:     lda tgt+1
        adc #0
        sta tgt+1
        rts

; ax[X] += signed A
move_x:
        sta t8
        clc
        adc ax_lo,x
        sta ax_lo,x
        lda t8
        bpl @p
        lda ax_hi,x
        adc #$ff
        sta ax_hi,x
        rts
@p:     lda ax_hi,x
        adc #0
        sta ax_hi,x
        rts

; ay[X] += signed A
move_y:
        sta t8
        clc
        adc ay_lo,x
        sta ay_lo,x
        lda t8
        bpl @p
        lda ay_hi,x
        adc #$ff
        sta ay_hi,x
        rts
@p:     lda ay_hi,x
        adc #0
        sta ay_hi,x
        rts

; ---------------------------------------------------------------------------------------------
; The flight paths: a bit stream (see tools/gen_arcade.py). rbit: carry = the next bit. Keeps X.
; ---------------------------------------------------------------------------------------------
rbit:
        lda scnt
        bne @have
        ldy #0
        lda (sp),y
        sta scur
        inc sp
        bne @s
        inc sp+1
@s:     lda #8
        sta scnt
@have:  dec scnt
        lsr scur
        rts

; A = the next change of a step: 0, +1, -1, +2, -2 or (the low byte of) a longer one
rv:
        jsr rbit
        bcs @1
        lda #0
        rts
@1:     jsr rbit
        bcs @2
        lda #1
        rts
@2:     jsr rbit
        bcs @3
        lda #$ff
        rts
@3:     jsr rbit
        bcs @4
        lda #2
        rts
@4:     jsr rbit
        bcs @5
        lda #$fe
        rts
@5:     lda #8
        sta rcnt
@e:     jsr rbit
        ror racc
        dec rcnt
        bne @e
        jsr rbit                        ; the 9th bit is not needed: only the low byte of the change counts
        lda racc
        rts

; One step along the path of alien X: dx, dy = the last ones + the changes; ++pstep
arc_step:
        lda s_plo,x
        sta sp
        lda s_phi,x
        sta sp+1
        lda s_cur,x
        sta scur
        lda s_cnt,x
        sta scnt
        jsr rv
        clc
        adc s_pdx,x
        sta s_pdx,x
        jsr move_x
        jsr rv
        clc
        adc s_pdy,x
        sta s_pdy,x
        jsr move_y
        lda sp
        sta s_plo,x
        lda sp+1
        sta s_phi,x
        lda scur
        sta s_cur,x
        lda scnt
        sta s_cnt,x
        inc a_ps_lo,x
        bne @r
        inc a_ps_hi,x
@r:     rts

; Alien X starts its entry path a_path[X]
path_launch:
        lda #1
        sta enemy_flag,x
        lda #0
        sta a_ps_lo,x
        sta a_ps_hi,x
        sta s_cnt,x
        sta s_pdx,x
        sta s_pdy,x
        ldy a_path,x
        lda arce_lo,y
        sta s_plo,x
        lda arce_hi,y
        sta s_phi,x
        lda arce_sxlo,y
        sta ax_lo,x
        lda arce_sxhi,y
        sta ax_hi,x
        lda arce_sylo,y
        sta ay_lo,x
        lda arce_syhi,y
        sta ay_hi,x
        rts

; Carry set: the alien has made all the steps of its entry path
path_done:
        ldy a_path,x
        lda a_ps_hi,x
        cmp arce_nhi,y
        bne @r
        lda a_ps_lo,x
        cmp arce_nlo,y
@r:     rts

; ---------------------------------------------------------------------------------------------
; Where a slot is now: the slot, the swing of the formation and the breathing of its columns and rows
; ---------------------------------------------------------------------------------------------
slot_target:                            ; X = alien -> tgt (x), tgy (y), 16 bits
        lda base_x,x
        sta tgt
        lda base_xh,x
        sta tgt+1
        lda form_fdx
        jsr add_s8
        ldy arc_slot_col,x
        lda cur_brx,y
        jsr add_s8
        lda base_y,x
        sta tgy
        lda #0
        sta tgy+1
        ldy arc_slot_row,x
        lda cur_bry,y
        bpl @p
        clc
        adc tgy
        sta tgy
        lda #$ff
        adc tgy+1
        sta tgy+1
        rts
@p:     clc
        adc tgy
        sta tgy
        bcc @r
        inc tgy+1
@r:     rts

; The shifts of the columns and rows for the step form_bstep of the breathing
calc_breath:
        lda form_breathe
        bne @on
        ldx #9
        lda #0
@z:     sta cur_brx,x
        dex
        bpl @z
        ldx #4
        lda #0
@zy:    sta cur_bry,x
        dex
        bpl @zy
        rts
@on:    ldy form_bstep
        lda arc_br0,y
        sta cur_brx+0
        lda arc_br1,y
        sta cur_brx+1
        lda arc_br2,y
        sta cur_brx+2
        lda arc_br3,y
        sta cur_brx+3
        lda arc_br4,y
        sta cur_brx+4
        lda #0                          ; the right half is the mirror of the left half
        sec
        sbc arc_br4,y
        sta cur_brx+5
        lda #0
        sec
        sbc arc_br3,y
        sta cur_brx+6
        lda #0
        sec
        sbc arc_br2,y
        sta cur_brx+7
        lda #0
        sec
        sbc arc_br1,y
        sta cur_brx+8
        lda #0
        sec
        sbc arc_br0,y
        sta cur_brx+9
        lda arc_br5,y
        sta cur_bry+0
        lda arc_br6,y
        sta cur_bry+1
        lda arc_br7,y
        sta cur_bry+2
        lda arc_br8,y
        sta cur_bry+3
        lda arc_br9,y
        sta cur_bry+4
        rts

; ---------------------------------------------------------------------------------------------
; The formation swings left and right while the aliens fly in (one pixel every 4 arcade frames, +-32), and when they are all home
; and the swing is back in the middle it breathes. The clock is the arcade's: 6 frames for every 5 ticks.
; ---------------------------------------------------------------------------------------------
arc_form_frame:
        inc form_ff
        lda form_breathe
        beq @swing
        lda form_ff
        and #3
        bne @rts
        lda form_bstep
        clc
        adc #1
        and #63
        sta form_bstep
        jmp calc_breath
@swing: lda form_ff
        sec
        sbc #1
        and #3
        bne @rts
        lda form_pos
        clc
        adc form_sdir
        sta form_pos
        lda entering
        bne @limits
        lda form_pos
        bne @limits
        lda #1                          ; all home and the swing is at the middle: breathe
        sta form_breathe
        lda #0
        sta form_bstep
        jsr calc_breath
        bra @fdx
@limits:
        lda form_pos
        bmi @neg
        cmp #32
        bcc @fdx
        lda #$ff
        sta form_sdir
        bra @fdx
@neg:   cmp #(256-32)
        beq @tolow
        bcs @fdx
@tolow: lda #1
        sta form_sdir
@fdx:   lda form_pos
        clc
        adc #32
        tay
        lda arc_fdx,y
        sta form_fdx
@rts:   rts

; Count the entering aliens, then run the formation clock
update_formation:
        lda #0
        sta entering
        ldx #MAX_ENEMIES-1
@c:     lda enemy_state,x
        cmp #7
        bne @n
        inc entering
@n:     dex
        bpl @c
        lda in_chal
        bne @rts
        lda form_clk
        clc
        adc #6
@clk:   cmp #5
        bcc @done
        sbc #5
        pha
        jsr arc_form_frame
        pla
        bra @clk
@done:  sta form_clk
@rts:   rts

; ---------------------------------------------------------------------------------------------
; The fly-in: launch the aliens that wait (only while the ship plays), move the ones that fly, home the ones that arrive
; ---------------------------------------------------------------------------------------------
update_entry:
        lda in_chal
        bne @none
        ldx #0
@loop:  lda enemy_state,x
        cmp #7
        bne @next
        jsr entry_one
@next:  inx
        cpx #MAX_ENEMIES
        bne @loop
@none:  rts

entry_one:
        lda enemy_flag,x
        beq @wait
        cmp #1
        beq @fly
        jsr slot_target                 ; homing: 2 pixels a tick towards the slot (which breathes), then in formation
        jsr toward_x
        jsr toward_y
        diff16 ax_lo, ax_hi, tgt
        jsr near3
        bcs @rts
        diff16 ay_lo, ay_hi, tgy
        jsr near3
        bcs @rts
        lda #1
        sta enemy_state,x
        lda tgt
        sta ax_lo,x
        lda tgt+1
        sta ax_hi,x
        lda tgy
        sta ay_lo,x
        lda tgy+1
        sta ay_hi,x
        rts
@wait:  lda game_state
        cmp #GS_PLAY
        bne @rts                        ; the waves wait while the ship is dead or taken
        lda a_dly_lo,x
        bne @d1
        dec a_dly_hi,x
@d1:    dec a_dly_lo,x
        lda a_dly_hi,x                  ; launch when the count is 0 or less
        bmi @go
        ora a_dly_lo,x
        bne @rts
@go:    jmp path_launch
@fly:   jsr path_done
        bcs @arrived
        jmp arc_step
@arrived:
        lda #2
        sta enemy_flag,x
@rts:   rts

; ax[X] moves 2 pixels towards tgt (if it is not there), ay[X] towards tgy
toward_x:
        diff16 ax_lo, ax_hi, tgt
        lda d16
        ora d16+1
        beq @done
        lda d16+1
        bmi @inc
        lda ax_lo,x
        sec
        sbc #2
        sta ax_lo,x
        lda ax_hi,x
        sbc #0
        sta ax_hi,x
        rts
@inc:   lda ax_lo,x
        clc
        adc #2
        sta ax_lo,x
        lda ax_hi,x
        adc #0
        sta ax_hi,x
@done:  rts

toward_y:
        diff16 ay_lo, ay_hi, tgy
        lda d16
        ora d16+1
        beq @done
        lda d16+1
        bmi @inc
        lda ay_lo,x
        sec
        sbc #2
        sta ay_lo,x
        lda ay_hi,x
        sbc #0
        sta ay_hi,x
        rts
@inc:   lda ay_lo,x
        clc
        adc #2
        sta ay_lo,x
        lda ay_hi,x
        adc #0
        sta ay_hi,x
@done:  rts

; Carry set: |d16| > 3 (far); carry clear: near
near3:
        lda d16+1
        beq @p
        cmp #$ff
        bne @far
        lda d16
        cmp #$fd
        bcs @near                       ; -3..-1
@far:   sec
        rts
@p:     lda d16
        cmp #4
        rts                             ; carry set when >= 4
@near:  clc
        rts

; ---------------------------------------------------------------------------------------------
; The aliens: in formation they stand in their slots, a diver follows its path, a returning alien comes back from the top,
; an exploding one counts down
; ---------------------------------------------------------------------------------------------
to_slot:                                ; alien X goes to its slot (x, y)
        jsr slot_target
        lda tgt
        sta ax_lo,x
        lda tgt+1
        sta ax_hi,x
        lda tgy
        sta ay_lo,x
        lda tgy+1
        sta ay_hi,x
        rts

update_enemies:
        ldx #0
@loop:  lda enemy_state,x
        beq @next
        cmp #1
        beq @form
        cmp #2
        beq @dive
        cmp #3
        beq @ret
        cmp #4
        beq @expl
        bra @next
@form:  jsr to_slot
        lda enemy_timer,x               ; just home: it turns round before it can dive again
        beq @next
        dec enemy_timer,x
        bra @next
@dive:  jsr dive_step
        bra @next
@ret:   jsr return_step
        bra @next
@expl:  dec enemy_timer,x
        bpl @next
        lda #0
        sta enemy_state,x
@next:  inx
        cpx #MAX_ENEMIES
        bne @loop
        rts

; A returning alien: above the screen it waits, then it comes down to its slot (2 pixels a tick) and has to settle
return_step:
        jsr slot_target
        lda tgt
        sta ax_lo,x
        lda tgt+1
        sta ax_hi,x
        lda a_wait_lo,x
        ora a_wait_hi,x
        beq @move
        lda a_wait_lo,x
        bne @d
        dec a_wait_hi,x
@d:     dec a_wait_lo,x
        rts
@move:  lda ay_lo,x
        clc
        adc #2
        sta ay_lo,x
        bcc @c
        inc ay_hi,x
@c:     lda ay_hi,x                     ; home when y >= the slot's y
        cmp tgy+1
        bne @cmp
        lda ay_lo,x
        cmp tgy
@cmp:   bcc @rts
        lda tgy
        sta ay_lo,x
        lda tgy+1
        sta ay_hi,x
        lda #1
        sta enemy_state,x
        lda #0
        sta enemy_esc,x
        lda enemy_type_tbl,x            ; the arcade takes 54 frames (a bee: 3) to settle a boss or a butterfly: 45 ticks
        cmp #2
        beq @bee
        lda #45
        bra @st
@bee:   lda #3
@st:    sta enemy_timer,x
@rts:   rts

; One tick of a dive
dive_step:
        lda a_cap,x
        beq @arc
        jmp dive_step_cap
@arc:   lda enemy_timer,x               ; an escort waits in its slot for its boss
        beq @go
        dec enemy_timer,x
        jmp to_slot
@go:    lda a_dpath,x
        cmp #255
        beq @free
        tay
        lda a_ps_hi,x                   ; on the path while pstep < n
        cmp arcd_nhi,y
        bne @cmp
        lda a_ps_lo,x
        cmp arcd_nlo,y
@cmp:   bcs @free
        jsr arc_step
        bra @after
@free:  lda #3                          ; the end of the path of a butterfly: it aims at the ship
        jsr move_y
        lda frame
        and #1
        beq @inc
        lda player_x
        sta tgt
        lda player_x_msb
        sta tgt+1
        diff16 ax_lo, ax_hi, tgt
        lda d16
        ora d16+1
        beq @inc
        lda d16+1
        bmi @right
        lda #$ff
        bra @mv
@right: lda #1
@mv:    jsr move_x
@inc:   inc a_ps_lo,x
        bne @after
        inc a_ps_hi,x
@after: lda ay_hi,x                     ; y >= 244: gone below the screen
        bmi @rts
        bne @gone
        lda ay_lo,x
        cmp #244
        bcc @rts
@gone:  lda #3                          ; it comes back from the top when the arcade dive would end
        sta enemy_state,x
        lda #0
        sta ay_lo,x
        sta ay_hi,x
        jsr slot_target                 ; wait = total - pstep - slot y / 2 (at least 0)
        lda tgy+1
        lsr
        lda tgy
        ror
        sta t8
        ldy a_dpath,x
        cpy #255
        beq @t220
        lda arcd_totlo,y
        sta d16
        lda arcd_tothi,y
        sta d16+1
        bra @sub
@t220:  lda #220
        sta d16
        lda #0
        sta d16+1
@sub:   lda d16
        sec
        sbc a_ps_lo,x
        sta d16
        lda d16+1
        sbc a_ps_hi,x
        sta d16+1
        lda d16
        sec
        sbc t8
        sta d16
        lda d16+1
        sbc #0
        sta d16+1
        bpl @pos
        lda #0
        sta d16
        sta d16+1
@pos:   lda d16
        sta a_wait_lo,x
        lda d16+1
        sta a_wait_hi,x
@rts:   rts

; The dive of a boss that tries to capture the ship (not on a path): it peels off, comes down steering towards the ship, and at y 196
; it starts the beam
dive_step_cap:
        lda enemy_timer,x
        beq @go
        dec enemy_timer,x
        lda enemy_dir,x
        beq @l
        lda #2
        bra @mx
@l:     lda #$fe
@mx:    jsr move_x
        lda #1
        jmp move_y
@go:    lda diff
        cmp #5
        bcs @three
        lda #2
        bra @dy
@three: lda #3
@dy:    jsr move_y
        lda player_x
        sta tgt
        lda player_x_msb
        sta tgt+1
        diff16 ax_lo, ax_hi, tgt
        lda d16
        ora d16+1
        beq @steered
        lda d16+1
        bmi @r
        lda #$ff
        bra @st
@r:     lda #1
@st:    jsr move_x
@steered:
        lda ay_hi,x
        bne @beam
        lda ay_lo,x
        cmp #196
        bcc @rts
@beam:  lda #5                          ; the beam
        sta enemy_state,x
        lda #2
        sta cap_state
        lda #0
        sta beam_len
        sta arc_beamacc
        sta arc_beamph
        lda #180
        sta beam_timer
        stx t8                          ; one beam step = p6 * 10 * 5 / 6 / 4 ticks (p6 = 12, 9 or 6 by stage)
        ldy arc_sidx
        lda arc_st7,y
        sta tgt
        lda #0
        sta q16
        sta q16+1
@m:     lda tgt
        beq @md
        lda q16
        clc
        adc #50
        sta q16
        bcc @m1
        inc q16+1
@m1:    dec tgt
        bra @m
@md:    lda #6
        sta dv8
        jsr div16_8
        lsr q16
        lsr q16
        lda q16
        sta arc_beamstep
        ldx t8
        rts
@rts:   rts

; ---------------------------------------------------------------------------------------------
; The dive scheduler of the arcade (game.c arc_frame): timers of 16 arcade frames for a boss, a butterfly and a bee, the stage table,
; the number of divers allowed. update_dives runs the arcade clock: 6 arcade frames for every 5 ticks.
; ---------------------------------------------------------------------------------------------
update_dives:
.ifdef NODIVE
        rts                             ; -DNODIVE=1: no sorties (tools/compare_6502.py)
.endif
        lda arc_clk
        clc
        adc #6
@c:     cmp #5
        bcc @d
        sbc #5
        sta arc_clk
        jsr arc_frame
        lda arc_clk
        bra @c
@d:     sta arc_clk
        rts

; Is something flying? (a diver, a returning alien, a beam, an alien that flies in; none in a challenge stage) A = 0: no
arc_flying:
        lda in_chal
        bne @no
        ldx #MAX_ENEMIES-1
@l:     lda enemy_state,x
        cmp #2
        beq @yes
        cmp #3
        beq @yes
        cmp #5
        beq @yes
        cmp #7
        bne @n
        lda enemy_flag,x
        bne @yes
@n:     dex
        bpl @l
@no:    lda #0
        rts
@yes:   lda #1
        rts

arc_frame:
        inc arc_af
        lda arc_af
        and #31
        bne @nt
        lda arc_tmr2
        beq @h
        dec arc_tmr2
@h:     lda arc_hold
        beq @nt
        dec arc_hold
@nt:    lda #0                          ; the aliens that are alive, the ones that fly
        sta arc_nalive
        sta arc_nfly
        ldx #MAX_ENEMIES-1
@cnt:   lda enemy_state,x
        beq @cn
        cmp #4
        beq @cn
        inc arc_nalive
        cmp #2
        beq @fl
        cmp #3
        beq @fl
        cmp #5
        bne @cn
@fl:    inc arc_nfly
@cn:    dex
        bpl @cnt
        lda #0                          ; tens = alive / 10
        sta arc_tens
        lda arc_nalive
@ten:   cmp #10
        bcc @tens
        sbc #10
        inc arc_tens
        bra @ten
@tens:  ldy arc_sidx
        lda arc_st5,y                   ; max divers p4; p5 when the stage is older than 60 counts of the timer
        sta arc_maxb
        lda arc_tmr2
        cmp #60
        bcs @mb
        lda arc_st6,y
        sta arc_maxb
@mb:    lda arc_st1,y                   ; bomb flags: p0 row, by the number of aliens
        asl
        asl
        clc
        adc arc_tens
        tax
        lda arc_bomb_tab,x
        sta arc_bflags
        lda arc_nalive                  ; continuous bombing when few are left: p7
        cmp arc_st8,y
        lda #0
        rol                             ; carry = alive < p7 (cmp sets carry when alive >= p7)
        eor #1
        sta arc_cont
        ; idx = (tmr2 < 40) + (tmr2 == 0)
        lda #0
        sta t8
        lda arc_tmr2
        cmp #40
        bcs @i1
        inc t8
@i1:    lda arc_tmr2
        bne @i2
        inc t8
@i2:    lda arc_cont
        beq @reloads
        lda #2
        sta arc_reload
        sta arc_reload+1
        sta arc_reload+2
        bra @bombs
@reloads:
        lda arc_st2,y                   ; boss: bomb_tab[32 + 4 * p1 + tens]
        asl
        asl
        clc
        adc arc_tens
        tax
        lda arc_bomb_tab+32,x
        sta arc_reload
        lda arc_st3,y                   ; butterfly: red[3 * p2 + idx]
        sta tgt
        asl
        clc
        adc tgt
        clc
        adc t8
        tax
        lda arc_red_reload,x
        sta arc_reload+1
        lda arc_st4,y                   ; bee: bee[3 * p3 + idx]
        sta tgt
        asl
        clc
        adc tgt
        clc
        adc t8
        tax
        lda arc_bee_reload,x
        sta arc_reload+2
@bombs: ldx #0                          ; a diver or a flyer drops a bomb at every set bit of its flags, every hdr0 frames
@bl:    lda enemy_state,x
        cmp #2
        beq @dv
        cmp #7
        bne @bn
        lda enemy_flag,x
        cmp #1
        bne @bn
        bra @bt
@dv:    lda a_cap,x
        bne @bn
@bt:    dec a_btm,x
        bne @bn
        ldy arc_row
        lda arc_row_hdr0,y
        sta a_btm,x
        lda a_bfl,x
        and #1
        beq @shift
        lda arc_hold
        bne @shift
        lda ay_hi,x                     ; y <= 163 (negative: yes)
        bmi @drop
        bne @shift
        lda ay_lo,x
        cmp #164
        bcs @shift
@drop:  jsr spawn_ebullet
@shift: lsr a_bfl,x
@bn:    inx
        cpx #MAX_ENEMIES
        bne @bl
        lda entering                    ; sorties: only when everyone is home, and every 16 arcade frames
        bne @rts
        lda arc_af
        and #15
        bne @rts
        ldx #0
@tm:    dec arc_sortie,x
        beq @due
        inx
        cpx #3
        bne @tm
@rts:   rts
@due:   lda arc_nfly
        cmp arc_maxb
        bcc @go
        inc arc_sortie,x                ; too many are flying: try again in a moment
        rts
@go:    lda arc_reload,x
        sta arc_sortie,x
        cpx #2
        beq @bee
        cpx #1
        beq @red
        jmp arc_sortie_boss
@bee:   lda #20
        ldy #40
        bra @sb
@red:   lda #4
        ldy #20
@sb:    sty st_to
        tax
        stx st_from
        jsr arc_standby
        cmp #255
        bne @started
        rts
@started:
        tax
        lda #0
        ldy #0
        jmp start_dive

st_from:        .byte 0
st_to:          .byte 0
st_cap:         .byte 0
st_peel:        .byte 0

; The first alien from st_from to st_to-1 that is home and has settled, or 255
arc_standby:
        ldx st_from
@l:     lda enemy_state,x
        cmp #1
        bne @n
        lda enemy_timer,x
        bne @n
        txa
        rts
@n:     inx
        cpx st_to
        bne @l
        lda #255
        rts

boss_for_b:     .byte 0, 1, 3, 2, 0

; Is alien X home and settled? Z clear: yes
is_standby:
        lda enemy_state,x
        cmp #1
        bne @no
        lda enemy_timer,x
        bne @no
        lda #1
        rts
@no:    lda #0
        rts

; A sortie of a boss: a capture attempt every second time, else a boss with the escorts the wingman table gives (game.c arc_sortie_boss)
arc_sortie_boss:
        lda cap_state
        bne @wing
        inc arc_wingm
        lda arc_wingm
        and #1
        bne @wing
        lda dual
        bne @wing
        lda #0                          ; a capture attempt
        sta st_from
        lda #4
        sta st_to
        jsr arc_standby
        cmp #255
        bne @cap
        rts
@cap:   tax
        lda #1
        ldy #20
        jmp start_dive
@wing:  lda #0                          ; which of the six wingmen are home
        sta arc_c
        ldy #0
@bits:  ldx arc_wingmen,y
        phy
        jsr is_standby
        ply
        sta t8
        lda arc_c
        asl
        ora t8
        sta arc_c
        iny
        cpy #6
        bne @bits
        lda #255
        sta arc_slot
        lda #0
        sta arc_ixl
@ixl:   lda arc_c
        sta arc_cc
        lda #4
        sta arc_b
@bb:    lda arc_cc
        and #7
        sta t8
        lda arc_ixl
        bne @one
        lda t8                          ; two wingmen: the pattern 011, 111 or 110 (not 100, nothing under 3)
        cmp #4
        beq @no
        cmp #3
        bcc @no
        bra @ok
@one:   lda t8
        beq @no
@ok:    ldy arc_b
        ldx boss_for_b,y
        jsr is_standby
        beq @no
        stx arc_slot
        lda #2
        sec
        sbc arc_ixl
        sta arc_ne
        jmp @matched
@no:    lsr arc_cc
        dec arc_b
        bne @bb
        inc arc_ixl
        lda arc_ixl
        cmp #2
        bne @ixl
        lda #0                          ; a boss alone
        sta st_from
        lda #4
        sta st_to
        jsr arc_standby
        cmp #255
        beq @rts
        tax
        lda #0
        ldy #0
        jmp start_dive
@rts:   rts
@matched:
        lda arc_b                       ; b = B + 1
        clc
        adc #1
        sta arc_b
        lda #0
        sta arc_nesc
        ldy arc_ne
        sty arc_ixl                     ; (k counts down from n)
@ek:    lda arc_cc                      ; rotate right: cy = the bit that falls out
        lsr
        php
        bcc @r0
        ora #$80
@r0:    sta arc_cc
        plp
        bcs @have
        dec arc_b
        lda arc_cc
        lsr
        php
        bcc @r1
        ora #$80
@r1:    sta arc_cc
        plp
        bcs @have
        dec arc_b
@have:  lda arc_b
        bmi @skip
        cmp #6
        bcs @skip
        tay
        lda arc_wingmen,y
        ldy arc_nesc
        sta arc_esc,y
        inc arc_nesc
@skip:  dec arc_b
        dec arc_ixl
        bne @ek
        ldy #0                          ; the escorts belong to the boss (before the dives start: the dive path depends on it)
@se:    cpy arc_nesc
        beq @sd
        ldx arc_esc,y
        lda arc_slot
        clc
        adc #1
        sta enemy_esc,x
        iny
        bra @se
@sd:    ldx arc_slot
        lda #0
        ldy #0
        jsr start_dive
        ldy #0
@sk:    cpy arc_nesc
        beq @rts
        sty arc_ixl
        ldx arc_esc,y
        lda #0
        iny
        jsr start_dive                  ; the peel: 1 for the first escort, 2 for the second (y = k + 1)
        ldy arc_ixl
        iny
        bra @sk

; Alien X starts a dive: A = 1 for a capture dive, Y = ticks to wait in the slot. A dive path is chosen by the kind of alien (arc_dive_map).
start_dive:
        sta st_cap
        sty st_peel
        lda #2
        sta enemy_state,x
        lda st_peel
        sta enemy_timer,x
        lda st_cap
        sta a_cap,x
        lda #24                         ; swoop sound
        sta swoop_cnt
        lda st_cap
        beq @notcap
        lda #1                          ; the capture boss: it is on its way to the beam
        sta cap_state
        stx cap_boss
        lda ax_lo,x                     ; peels off towards the ship: dir 1 (right) when x < px
        sec
        sbc player_x
        lda ax_hi,x
        sbc player_x_msb
        lda #0
        rol                             ; carry set: x >= px
        eor #1
        sta enemy_dir,x
        bra @init
@notcap:
        lda ax_hi,x                     ; x >= 184: peel off to the right
        bne @right
        lda ax_lo,x
        cmp #184
        bcs @right
        lda #0
        bra @sd
@right: lda #1
@sd:    sta enemy_dir,x
@init:  lda #0
        sta a_ps_lo,x
        sta a_ps_hi,x
        lda arc_bflags
        sta a_bfl,x
        lda #30
        sta a_btm,x
        lda st_cap
        beq @path
        lda #255
        sta a_dpath,x
        rts
@path:  lda enemy_esc,x                 ; label: 2 an escort or a boss, 1 a butterfly, 0 a bee
        bne @l2
        lda enemy_type_tbl,x
        beq @l2
        cmp #1
        beq @l1
        lda #0
        bra @lab
@l1:    lda #1
        bra @lab
@l2:    lda #2
@lab:   sta t8                          ; index = (label * 5 + row) * 2 + side
        asl
        asl
        clc
        adc t8
        clc
        adc arc_slot_row,x
        asl
        clc
        adc arc_slot_side,x
        tay
        lda arc_dive_map,y
        sta a_dpath,x
        cmp #255
        beq @rts
        tay
        lda arcd_lo,y
        sta s_plo,x
        lda arcd_hi,y
        sta s_phi,x
        lda #0
        sta s_cnt,x
        sta s_pdx,x
        sta s_pdy,x
@rts:   rts

; ---------------------------------------------------------------------------------------------
; Bombs (up to 8): aimed at the ship when they are dropped, the sideways speed at most 0.6 of the fall speed
; ---------------------------------------------------------------------------------------------
; q16 = q16 / dv8 (16 bits by 8 bits)
div16_8:
        lda #0
        sta r16
        ldy #16
@l:     asl q16
        rol q16+1
        rol r16
        lda r16
        cmp dv8
        bcc @n
        sbc dv8
        sta r16
        inc q16
@n:     dey
        bne @l
        rts

; Alien X drops a bomb (nothing when all 8 are on the screen). Keeps X.
spawn_ebullet:
        ldy #0
@f:     lda eb_active,y
        beq @got
        iny
        cpy #EBN
        bne @f
        rts
@got:   lda #1
        sta eb_active,y
        lda ax_lo,x
        sta eb_x,y
        lda ax_hi,x
        sta eb_msb,y
        lda ay_lo,x
        clc
        adc #8
        sta eb_y,y
        lda #0
        sta eb_ax,y
        phy                             ; the divisions use Y
        lda player_y                    ; den = (py - y) * 2 / 5 + 1
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
        lda player_x                    ; d = px - x; |d| * 16 / den, then the sign
        sec
        sbc ax_lo,x
        sta q16
        lda player_x_msb
        sbc ax_hi,x
        sta q16+1
        sta sgn
        bpl @pos
        lda #0
        sec
        sbc q16
        sta q16
        lda #0
        sbc q16+1
        sta q16+1
@pos:   .repeat 4
        asl q16
        rol q16+1
        .endrepeat
        jsr div16_8
        ply
        lda q16+1
        bne @max
        lda q16
        cmp #24
        bcc @ok
@max:   lda #24
        sta q16
@ok:    lda sgn
        bpl @store
        lda #0
        sec
        sbc q16
        sta q16
@store: lda q16
        sta eb_dx,y
        rts

; The bombs fall (2 or 3 pixels a tick) and drift
update_ebullets:
        ldx #EBN-1
@l:     lda eb_active,x
        beq @n
        lda frame
        and #1
        clc
        adc #2
        clc
        adc eb_y,x
        sta eb_y,x
        cmp #250
        bcc @move
        lda #0
        sta eb_active,x
        bra @n
@move:  lda eb_ax,x                     ; ax += dx; x += ax >> 4 (rounded down); ax &= 15
        clc
        adc eb_dx,x
        sta t8
        and #15
        sta eb_ax,x
        lda t8
        cmp #$80                        ; arithmetic shift right by 4: -3..2
        ror
        cmp #$80
        ror
        cmp #$80
        ror
        cmp #$80
        ror
        bpl @pos
        clc
        adc eb_x,x
        sta eb_x,x
        lda eb_msb,x
        adc #$ff
        sta eb_msb,x
        bra @n
@pos:   clc
        adc eb_x,x
        sta eb_x,x
        lda eb_msb,x
        adc #0
        sta eb_msb,x
@n:     dex
        bpl @l
        rts

; ---------------------------------------------------------------------------------------------
; A challenge stage: the aliens launch by the clock and fly their path; at its end they are gone
; ---------------------------------------------------------------------------------------------
update_challenge:
        inc chal_t_lo
        bne @t
        inc chal_t_hi
@t:     ldx #0
@loop:  lda enemy_state,x
        cmp #4
        beq @expl
        cmp #7
        bne @next
        lda enemy_flag,x
        bne @fly
        lda chal_t_hi                   ; launch when the clock has reached its time: chalTimer >= dly
        cmp a_dly_hi,x
        bne @cmp
        lda chal_t_lo
        cmp a_dly_lo,x
@cmp:   bcc @next
        jsr path_launch
        bra @next
@fly:   jsr path_done
        bcs @gone
        jsr arc_step
        bra @next
@gone:  lda #0
        sta enemy_state,x
        bra @next
@expl:  dec enemy_timer,x               ; (game.c: update_aliens runs in a challenge stage too)
        bpl @next
        lda #0
        sta enemy_state,x
@next:  inx
        cpx #MAX_ENEMIES
        bne @loop
        rts

; ---------------------------------------------------------------------------------------------
; A stage: the row of waves of the stage, every alien waits for its launch
; ---------------------------------------------------------------------------------------------
begin_stage:
        lda stage                       ; the arcade's tables stop at stage 26: later stages repeat 23..26
        cmp #27
        bcc @idx
        sec
        sbc #23
        and #3
        clc
        adc #23
@idx:   tay
        dey
        sty arc_sidx
        ldy arc_sidx
        lda arc_st0,y
        sta arc_row
        tay
        lda arc_row_chal,y
        sta in_chal
        beq @std
        lda #1                          ; 100 points for each hit
        sta chal_mid
@std:   lda #0
        sta ch_hits
        sta form_pos
        sta form_fdx
        sta form_breathe
        sta form_bstep
        sta form_ff
        sta form_clk
        sta chal_t_lo
        sta chal_t_hi
        sta arc_af
        sta arc_clk
        sta arc_hold
        sta arc_wingm
        sta arc_bflags
        ldx #EBN-1
@eb:    sta eb_active,x
        dex
        bpl @eb
        sta pbul_active
        sta pbul_active+1
        sta pbul_active+2
        sta pbul_active+3
        sta cap_state
        sta beam_len
        lda #1
        sta form_sdir
        lda #120                        ; the scheduler: the time since the stage began, the first sortie timers
        sta arc_tmr2
        lda #22
        sta arc_sortie
        lda #2
        sta arc_sortie+1
        sta arc_sortie+2
        jsr calc_breath
        ldx #MAX_ENEMIES-1
@al:    lda #7                          ; entering, waiting
        sta enemy_state,x
        lda #0
        sta enemy_flag,x
        sta enemy_timer,x
        sta enemy_esc,x
        sta a_dly_lo,x
        sta a_dly_hi,x
        sta a_path,x
        sta a_cap,x
        sta a_wait_lo,x
        sta a_wait_hi,x
        sta a_bfl,x
        lda #255
        sta a_dpath,x
        lda #0
        ldy enemy_type_tbl,x
        lda type_hp,y
        sta enemy_hp,x
        lda in_chal                     ; a boss takes two hits, but not in a challenge stage
        beq @hp
        lda #1
        sta enemy_hp,x
@hp:    lda enemy_ptr_tbl,x
        sta enemy_ptr,x
        clc
        adc anim
        sta spr_f,x
        lda #0
        sta ax_lo,x
        sta ax_hi,x
        lda #255
        sta ay_lo,x
        lda #0
        sta ay_hi,x
        dex
        bpl @al
        ldy arc_row                     ; the launch list: ticks since the last launch, slot, path
        lda arc_row_lo,y
        sta sp
        lda arc_row_hi,y
        sta sp+1
        lda arc_row_n,y
        sta arc_n
        lda #0
        sta arc_t
        sta arc_t+1
@lst:   lda arc_n
        beq @done
        ldy #0
        lda (sp),y                      ; delay lo
        clc
        adc arc_t
        sta arc_t
        iny
        lda (sp),y
        adc arc_t+1
        sta arc_t+1
        iny
        lda (sp),y                      ; slot
        tax
        iny
        lda (sp),y                      ; path
        cpx #255
        beq @skip
        sta a_path,x
        lda arc_t
        sta a_dly_lo,x
        lda arc_t+1
        sta a_dly_hi,x
@skip:  lda sp
        clc
        adc #4
        sta sp
        bcc @nc
        inc sp+1
@nc:    dec arc_n
        bra @lst
@done:  rts

arc_sidx:       .byte 0
arc_row:        .byte 0
arc_n:          .byte 0
arc_t:          .word 0

; ---------------------------------------------------------------------------------------------
; The shots against the aliens, as in game.c: every shot against every alien, every tick
; ---------------------------------------------------------------------------------------------
check_collisions:
        ldy #0
@shot:  lda pbul_active,y
        beq @next_shot
        ldx #0
@al:    lda enemy_state,x
        beq @skip
        cmp #4
        beq @skip
        cmp #7
        bne @chk
        lda enemy_flag,x
        beq @skip                       ; still waiting to fly in
@chk:   lda ay_hi,x                     ; the shot's y - 8 <= the alien's y < the shot's y + 8
        bne @skip
        lda ay_lo,x
        sec
        sbc pbul_y,y
        clc
        adc #8
        cmp #16
        bcs @skip
        lda pbul_x,y                    ; the alien's x - 6 <= the shot's x < the alien's x + 12
        sec
        sbc ax_lo,x
        sta d16
        lda pbul_msb,y
        sbc ax_hi,x
        sta d16+1
        lda d16
        clc
        adc #6
        sta d16
        bcc @x1
        inc d16+1
@x1:    lda d16+1
        bne @skip
        lda d16
        cmp #18
        bcs @skip
        lda #0                          ; hit
        sta pbul_active,y
        inc hits
        bne @counted
        inc hits+1
@counted:
        tya
        pha
        jsr hit_enemy
        pla
        tay
        jmp @next_shot
@skip:  inx
        cpx #MAX_ENEMIES
        bne @al
@next_shot:
        iny
        cpy #4
        bne @shot
        jmp ship_hits

; ---------------------------------------------------------------------------------------------
; The aliens as sprites: x, y as 9 / 8 bit numbers for view.s (an alien out of the screen is hidden)
; ---------------------------------------------------------------------------------------------
arc_sync_aliens:
        ldx #MAX_ENEMIES-1
@loop:  lda enemy_state,x
        beq @hide
        cmp #7
        bne @show
        lda enemy_flag,x
        beq @hide                       ; waiting to fly in
@show:  lda ay_hi,x                     ; y in 0..254
        bne @hide
        lda ay_lo,x
        cmp #255
        beq @hide
        sta spr_y,x
        lda ax_hi,x                     ; x in -24 .. 343: the high byte is $ff, 0 or 1
        beq @xok
        cmp #1
        beq @x1
        cmp #$ff
        bne @hide
        lda ax_lo,x
        cmp #(256-24)
        bcc @hide
        lda #$ff
        bra @xs
@x1:    lda ax_lo,x
        cmp #(344-256)
        bcs @hide
        lda #1
        bra @xs
@xok:   lda #0
@xs:    sta spr_x_msb,x
        lda ax_lo,x
        sta spr_x,x
        lda enemy_state,x               ; an exploding alien shows its explosion frames
        cmp #4
        bne @next
        lda enemy_timer,x
        lsr
        lsr
        sta temp
        lda #SPR_EXPL1+2
        sec
        sbc temp
        bcs @ef
        lda #SPR_EXPL1
@ef:    sta spr_f,x
        bra @next
@hide:  lda #$ff
        sta spr_y,x
@next:  dex
        bpl @loop
        rts

; ---------------------------------------------------------------------------------------------
; The ship(s) against the bombs and against divers and fliers that ram (game.c update_collisions)
; ---------------------------------------------------------------------------------------------
ship_x:         ; sx of ship cur_ship (0: player_x, 1: player_x + 16) -> tgt
        lda #0
        ldy cur_ship
        beq @o
        lda #16
@o:     clc
        adc player_x
        sta tgt
        lda player_x_msb
        adc #0
        sta tgt+1
        rts

ship_hits:
        lda game_state
        cmp #GS_PLAY
        bne @done
        lda invuln
        bne @done
        jsr ship_bombs
        jmp ship_rams
@done:  rts

ship_bombs:
        ldy #0                          ; the bombs
@bomb:  cpy #EBN
        beq @rams
        lda game_state
        cmp #GS_PLAY
        bne @done
        lda eb_active,y
        beq @bn
        lda eb_y,y                      ; y 227..240
        cmp #227
        bcc @bn
        cmp #241
        bcs @bn
        lda #0
        sta cur_ship
@bs:    sty hit_idx
        jsr ship_x                      ; the bomb's x - the ship's x + 6 in 0..13
        ldy hit_idx
        lda eb_x,y
        sec
        sbc tgt
        sta d16
        lda eb_msb,y
        sbc tgt+1
        sta d16+1
        lda d16
        clc
        adc #6
        sta d16
        bcc @b1
        inc d16+1
@b1:    lda d16+1
        bne @bsn
        lda d16
        cmp #14
        bcs @bsn
        lda #0                          ; hit
        sta eb_active,y
        lda cur_ship
        jsr arc_player_hit
        ldy hit_idx
        bra @bn
@bsn:   inc cur_ship
        lda cur_ship
        cmp dual
        beq @bs
        bcc @bs
        ldy hit_idx
@bn:    iny
        bra @bomb
@rams:
@done:  rts

ship_rams:
        lda in_chal                     ; (a challenge stage's aliens never ram)
        bne @done
        ldx #0
@rl:    lda game_state
        cmp #GS_PLAY
        bne @done
        lda invuln
        bne @done
        jsr ram_one
        inx
        cpx #MAX_ENEMIES
        bne @rl
@done:  rts

; Does alien X ram the ship (or one of the two)?
ram_one:
        lda enemy_state,x
        cmp #2
        beq @rchk
        cmp #7
        bne @x
        lda enemy_flag,x
        beq @x
@rchk:  lda ay_hi,x                     ; the alien's y in the ship's y - 7 .. + 8
        bne @x
        lda ay_lo,x
        sec
        sbc player_y
        clc
        adc #7
        cmp #16
        bcs @x
        lda #0
        sta cur_ship
        bra @rs
@x:     rts
@rs:    jsr ship_x                      ; the alien's x - the ship's x + 8 in 1..16
        lda ax_lo,x
        sec
        sbc tgt
        sta d16
        lda ax_hi,x
        sbc tgt+1
        sta d16+1
        lda d16
        clc
        adc #8
        sta d16
        bcc @r1
        inc d16+1
@r1:    lda d16+1
        bne @rsn
        lda d16
        beq @rsn
        cmp #17
        bcs @rsn
        lda a_cap,x                     ; a boss that rams the ship drops its captive
        beq @nocap
        lda cap_state
        beq @nocap
        cmp #5
        beq @nocap
        cpx cap_boss
        bne @nocap
        lda #0
        sta cap_state
@nocap: lda enemy_type_tbl,x
        bne @nocarry
        lda cap_state
        cmp #4
        bne @nocarry
        cpx cap_boss
        bne @nocarry
        lda #0
        sta cap_state
@nocarry:
        jsr set_explode
        jsr sound_explosion
        lda cur_ship
        jmp arc_player_hit
@rsn:   inc cur_ship
        lda cur_ship
        cmp dual
        beq @rs
        bcc @rs
@rts:   rts

; The ship is hit: A = 0 the (left) ship, 1 the right ship of the dual fighter. A dual fighter loses one ship, else a life.
arc_player_hit:
        ldy dual
        beq @life
        pha
        lda #0
        sta dual
        pla
        bne @keep
        lda player_x
        clc
        adc #16
        sta player_x
        bcc @keep
        inc player_x_msb
@keep:  lda #90
        sta invuln
        jmp sound_player_hit
@life:  dec lives
        lda #GS_DYING
        sta game_state
        lda #106                        ; (st_dying runs one tick more than the count: 107 ticks)
        sta dying_timer
        lda #0
        sta dying_quiet
        ldx #EBN-1
@c:     sta eb_active,x
        dex
        bpl @c
        sta pbul_active
        sta pbul_active+1
        sta pbul_active+2
        sta pbul_active+3
        jsr sound_player_hit
        jmp sound_player_die

; the debug flag DIEAT: the ship is hit
player_hit:
        lda #0
        jmp arc_player_hit

; ---------------------------------------------------------------------------------------------
; The beam, the capture and the rescue (game.c update_capture, update_captured, alien_hit)
; ---------------------------------------------------------------------------------------------
arc_beamacc:    .byte 0
arc_beamph:     .byte 0                 ; 0 the beam grows, 1 it holds (the ship is taken), 2 it shrinks
arc_beamstep:   .byte 0

update_capture:
        lda cap_state
        cmp #5
        bne @n5
        jmp rescue_step
@n5:    cmp #2
        beq @beam
        rts
@beam:  lda frame
        and #31
        bne @nosnd
        lda #24
        sta swoop_cnt                   ; beam hum
@nosnd: ldx cap_boss
        lda arc_beamph
        beq @grow
        cmp #2
        bne @hold
        jmp @shrink
@hold:  lda game_state                  ; holding: the ship under the beam is taken
        cmp #GS_PLAY
        bne @timer
        lda invuln
        bne @timer
        lda player_x                    ; the ship's x >= the boss's x - 20 and <= the boss's x + 19: x - bx + 20 in 0..39
        sec
        sbc ax_lo,x
        sta d16
        lda player_x_msb
        sbc ax_hi,x
        sta d16+1
        lda d16
        clc
        adc #20
        sta d16
        bcc @c1
        inc d16+1
@c1:    lda d16+1
        bne @timer
        lda d16
        cmp #40
        bcs @timer
        lda #GS_CAPTURED                ; caught
        sta game_state
        lda #3
        sta cap_state
        lda #0
        sta dual
        sta pbul_active
        sta pbul_active+1
        sta pbul_active+2
        sta pbul_active+3
        lda #jin_capt-jin_data
        jmp play_jingle
@timer: dec beam_timer
        bne @rts
        lda #2
        sta arc_beamph
        lda #0
        sta arc_beamacc
@rts:   rts
@grow:  inc arc_beamacc
        lda arc_beamacc
        cmp arc_beamstep
        bcc @rts
        lda #0
        sta arc_beamacc
        inc beam_len
        lda beam_len
        cmp #4
        bcc @rts
        lda #1
        sta arc_beamph
        lda #53
        sta beam_timer
        rts
@shrink:
        inc arc_beamacc
        lda arc_beamacc
        cmp arc_beamstep
        bcc @rts
        lda #0
        sta arc_beamacc
        dec beam_len
        bne @rts
        sta cap_state                   ; the beam is gone: the boss flies home
        lda #3
        sta enemy_state,x
        lda #0
        sta ay_lo,x
        sta ay_hi,x
        rts

; The capture boss was shot. In: X = boss.
boss_killed:
        lda cap_state
        cmp #4
        bne @clear
        lda enemy_state,x               ; the captive is freed when the boss is shot while it dives or returns
        cmp #2
        beq @free
        cmp #3
        bne @clear
@free:  lda ax_lo,x
        sta cap_x
        lda ax_hi,x
        sta cap_msb
        lda ay_lo,x
        sec
        sbc #16
        sta cap_y
        lda #5
        sta cap_state
        lda #$00                        ; +1000
        ldx #$10
        jsr add_score
        lda #jin_resc-jin_data
        jmp play_jingle
@clear: lda #0
        sta cap_state
        rts

; The ship is pulled up towards the boss; caught: the boss carries it away (game.c update_captured)
arc_captured:
        lda player_y
        sec
        sbc #2
        sta player_y
        ldx cap_boss
        sec
        sbc ay_lo,x
        cmp #22
        bcs @rts                        ; not there yet
        lda #PLAYER_Y
        sta player_y
        lda #4                          ; the boss flies back to its slot with the captive
        sta cap_state
        lda #3
        sta enemy_state,x
        lda #0
        sta ay_lo,x
        sta ay_hi,x
        sta a_cap,x
        lda #1
        sta dying_quiet                 ; no explosion for a captured ship
        dec lives
        beq @last
        lda #GS_DYING
        sta game_state
        lda #99                         ; (st_dying runs one tick more than the count: 100 ticks)
        sta dying_timer
        print msg_capt, SCREEN_RAM+20*40+12, 2
@rts:   rts
@last:  jmp enter_gameover
