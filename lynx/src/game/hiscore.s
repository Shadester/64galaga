; Hi-score in the cartridge EEPROM (93C46, 64 words), through cc65's 93C46 routines in lynx.lib. Two words:
; cell 0 = low and middle BCD pairs, cell 1 = high pair and a marker ($a5), so that an empty EEPROM
; ($ffff) or other data is ignored. Without EEPROM (or when the emulator has none) the hi-score lasts for the session.
EE_MARK         = $a5

hs_dirty:       .byte 0
ee_cell:        .byte 0

; Read cell A (cc65: unsigned lynx_eeread_93c46(unsigned cell), fastcall: cell in A/X, result in A/X)
ee_read:
        ldx #0
        jmp _lynx_eeread_93c46

; Write the word X:A to cell ee_cell (cc65: lynx_eewrite_93c46(cell, val): it pops the cell with popax, our stub below)
ee_write:
        jmp _lynx_eewrite_93c46

load_hiscore:
        lda #1
        jsr ee_read
        cpx #EE_MARK
        bne @none
        sta hiscore+2
        lda #0
        jsr ee_read
        sta hiscore
        stx hiscore+1
@none:  rts

save_hiscore:
        lda #0
        sta ee_cell
        lda hiscore
        ldx hiscore+1
        jsr ee_write
        lda #1
        sta ee_cell
        lda hiscore+2
        ldx #EE_MARK
        jsr ee_write
        stz hs_dirty
        rts

; cc65 runtime stub for eeprom46.o (ptr1 is its scratch word)
popax:  lda ee_cell
        ldx #0
        rts
