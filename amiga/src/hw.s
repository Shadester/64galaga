| Start-up, vertical blank interrupt. The game is linked at 0x1000 (link.ld); the bootblock jumps here with the OS off.
        .section .text.start
        .global _start
_start: move.w  #0x2700,sr
        lea     0x7fff0,sp              | top of 512 KB chip RAM
        lea     _bss_start,a0           | clear the bss
        lea     _bss_end,a1
1:      cmp.l   a1,a0
        bcc.s   2f
        clr.l   (a0)+
        bra.s   1b
2:      lea     vbl(pc),a0              | level 3 autovector: the vertical blank
        move.l  a0,0x6c
        lea     idle(pc),a0             | the other vectors do nothing
        lea     0x64,a1
        move.l  a0,(a1)+                | level 1
        lea     kbd(pc),a2
        move.l  a2,(a1)+                | level 2: the keyboard (CIA-A serial port)
        addq.l  #4,a1
        move.l  a0,(a1)+                | level 4
        move.l  a0,(a1)+                | level 5
        move.l  a0,(a1)+                | level 6
        move.b  #0x7f,0xbfed01          | CIA-A: all interrupts off, then only the serial port (keyboard) on
        move.b  #0x88,0xbfed01
        move.w  #0xc028,0xdff09a        | INTENA: enable, vertical blank (level 3), ports (level 2)
        move.w  #0x2000,sr              | interrupts on
        jsr     main
3:      bra.s   3b

vbl:    move.w  #0x0020,0xdff09c        | INTREQ: clear the vertical blank request
        addq.l  #1,vbl_count
        rte
idle:   rte

| Keyboard: a key code arrives in the serial data register of CIA-A: bit 7 of the decoded code is 1 for a key release.
| The key must be acknowledged by a pulse (about 85 microseconds) on the handshake line (bit 6 of CRA).
kbd:    movem.l d0-d1/a0,-(sp)
        move.w  #0x0008,0xdff09c        | INTREQ: clear the ports request
        move.b  0xbfed01,d0             | CIA-A interrupt control: reading it clears it
        btst    #3,d0                   | the serial port?
        beq.s   9f
        move.b  0xbfec01,d0
        not.b   d0
        ror.b   #1,d0                   | the key code, 0..127, and bit 7 = release
        move.b  d0,d1
        and.w   #0x7f,d1
        lea     keys,a0                 | (a0 is free: it is saved below)
        tst.b   d0
        smi     d0
        not.b   d0                      | 0xff if the key is down
        and.b   #1,d0
        move.b  d0,0(a0,d1.w)
        or.b    #0x40,0xbfee01          | the handshake: output mode
        moveq   #60,d1
8:      dbra    d1,8b
        and.b   #0xbf,0xbfee01
9:      movem.l (sp)+,d0-d1/a0
        rte

        .bss
        .global vbl_count, keys
vbl_count: .long 0
keys:   .space 128                      | 1 for a key that is down, by key code
