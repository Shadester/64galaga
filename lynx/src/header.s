; The .lnx header (64 bytes, EXEHDR segment): the one of lynx.lib's exehdr.s plus the EEPROM type, so that the
; emulator (and a real cartridge with a 93C46) saves the hi-score.
        .import __BANK0BLOCKSIZE__, __BANK1BLOCKSIZE__
        .export __EXEHDR__: absolute = 1

        .segment "EXEHDR"
        .byte "LYNX"
        .word __BANK0BLOCKSIZE__
        .word __BANK1BLOCKSIZE__
        .word 1                         ; version
        .byte "Galaga"                  ; cart name (32 bytes)
        .res 32 - 6, 0
        .byte "Shadester"               ; manufacturer (16 bytes)
        .res 16 - 9, 0
        .byte 0                         ; rotation: none
        .byte 0                         ; audin
        .byte 1                         ; EEPROM: 93C46
        .byte 0, 0, 0
