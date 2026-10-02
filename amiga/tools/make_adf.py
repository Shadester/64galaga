#!/usr/bin/env python3
"""Make an ADF (an 880 KB Amiga floppy image) with a bootblock and, after it, the game code.
Usage: make_adf.py BOOT.bin [GAME.bin] OUT.adf
BOOT.bin is the bootblock (at most 1024 bytes). The checksum is the one the Kickstart checks: the sum of the 256 longs
with the carry added back is 0xFFFFFFFF."""
import struct
import sys

ADF_SIZE = 80 * 2 * 11 * 512


def bootblock(code):
    assert len(code) <= 1024, 'the bootblock is 1024 bytes'
    b = bytearray(code.ljust(1024, b'\0'))
    b[4:8] = b'\0\0\0\0'
    s = 0
    for (v,) in struct.iter_unpack('>I', bytes(b)):
        s += v
        if s > 0xffffffff:
            s = (s & 0xffffffff) + 1
    b[4:8] = struct.pack('>I', ~s & 0xffffffff)
    return bytes(b)


if __name__ == '__main__':
    boot, out = sys.argv[1], sys.argv[-1]
    game = open(sys.argv[2], 'rb').read() if len(sys.argv) == 4 else b''
    code = bytearray(open(boot, 'rb').read())
    size = (len(game) + 511) // 512 * 512      # the bootblock reads whole sectors; its LOADSIZE is at byte 16
    code[16:20] = struct.pack('>I', size)
    img = bootblock(bytes(code)) + game
    assert len(img) <= ADF_SIZE, 'the game does not fit on the disk'
    open(out, 'wb').write(img.ljust(ADF_SIZE, b'\0'))
    print(out, len(img), 'bytes used')
