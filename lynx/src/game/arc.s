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
        ldx #0
@loop:  lda enemy_state,x
        cmp #7
        bne @next
        jsr entry_one
@next:  inx
        cpx #MAX_ENEMIES
        bne @loop
        rts

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
; The aliens: in formation they stand in their slots, an exploding one counts down
; ---------------------------------------------------------------------------------------------
update_enemies:
        ldx #0
@loop:  lda enemy_state,x
        cmp #1
        beq @form
        cmp #4
        beq @expl
        bra @next
@form:  jsr slot_target
        lda tgt
        sta ax_lo,x
        lda tgt+1
        sta ax_hi,x
        lda tgy
        sta ay_lo,x
        lda tgy+1
        sta ay_hi,x
        bra @next
@expl:  dec enemy_timer,x
        bpl @next
        lda #0
        sta enemy_state,x
@next:  inx
        cpx #MAX_ENEMIES
        bne @loop
        rts

; Milestone A: the aliens do not dive and do not shoot yet
update_dives:
update_ebullets:
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
        sta eb_active
        sta eb_active+1
        sta eb_active+2
        sta pbul_active
        sta pbul_active+1
        sta pbul_active+2
        sta pbul_active+3
        sta cap_state
        sta beam_len
        lda #1
        sta form_sdir
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
        rts

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
