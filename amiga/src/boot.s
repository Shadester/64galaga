| Bootblock: the Kickstart loads these 1024 bytes and calls them with a6 = ExecBase, a1 = the trackdisk request.
| It reads the game (LOADSIZE bytes from byte 1024 of the disk, filled in by tools/make_adf.py) into chip RAM, turns the
| operating system off and starts the game at 0x1000 (src/hw.s, _start).
        .text
        .ascii  "DOS"
        .byte   0
        .long   0                       | checksum: tools/make_adf.py
        .long   880                     | root block
        bra.s   start
        .word   0
loadsize:
        .long   0                       | patched by tools/make_adf.py (offset 16)
start:  move.l  a1,a2                   | the request
        move.l  loadsize(pc),d0
        move.l  #2,d1                   | MEMF_CHIP
        jsr     -198(a6)                | AllocMem
        move.l  d0,a3
        beq.s   fail
        move.l  a3,40(a2)               | IO_DATA
        move.l  loadsize(pc),36(a2)     | IO_LENGTH
        move.l  #1024,44(a2)            | IO_OFFSET
        move.w  #2,28(a2)               | CMD_READ
        move.l  a2,a1
        jsr     -456(a6)                | DoIO
        move.l  #0,36(a2)               | TD_MOTOR with length 0: motor off
        move.w  #9,28(a2)
        move.l  a2,a1
        jsr     -456(a6)
        jsr     -150(a6)                | SuperState: the game needs the supervisor mode (it sets the sr)
        lea     0xdff000,a6
        move.w  #0x7fff,0x9a(a6)        | INTENA off
        move.w  #0x7fff,0x9c(a6)        | INTREQ clear
        move.w  #0x7fff,0x96(a6)        | DMACON off
        move.l  a3,a0
        lea     0x1000,a1
        move.l  loadsize(pc),d0
        lsr.l   #2,d0
1:      move.l  (a0)+,(a1)+
        subq.l  #1,d0
        bne.s   1b
        jmp     0x1000
fail:   move.w  #0x0f00,0xdff180        | no memory: a red screen
        bra.s   fail
