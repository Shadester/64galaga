; Boot entry: the boot loader jumps to $0200, the first byte of the STARTUP segment.
        .import main

        .segment "STARTUP"
start:  sei
        cld
        ldx #$ff
        txs
        jmp main

        .segment "LOWCODE"      ; empty: defdir.s (lynx.lib) sizes them
        .segment "ONCE"
