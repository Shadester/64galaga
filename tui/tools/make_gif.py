#!/usr/bin/env python3
"""Record docs/gameplay.gif: the program runs in a pseudo-terminal (--autoplay), the screen is read with pyte and drawn cell by cell.
Needs Pillow and pyte (pip install pillow pyte). Usage: python3 tools/make_gif.py [cols rows seconds]"""
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

import pyte
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = os.path.join(HERE, '..', 'target', 'release', 'galaga-tui')
COLS, ROWS, SECONDS = (int(v) for v in (sys.argv[1:4] + ['80', '27', '30'][len(sys.argv) - 1:]))
CW, CH, FPS = 6, 12, 10


def font():
    for p in ('/System/Library/Fonts/Menlo.ttc', '/System/Library/Fonts/Monaco.ttf', '/Library/Fonts/Arial Unicode.ttf'):
        if os.path.exists(p):
            return ImageFont.truetype(p, 10)
    return ImageFont.load_default()


def color(h, default):
    if not h or h == 'default':
        return default
    try:
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return default


def picture(screen, fnt):
    img = Image.new('RGB', (COLS * CW, ROWS * CH))
    d = ImageDraw.Draw(img)
    for y in range(ROWS):
        for x in range(COLS):
            c = screen.buffer[y][x]
            fg, bg = color(c.fg, (255, 255, 255)), color(c.bg, (0, 0, 0))
            if c.data == '▀':
                d.rectangle([x * CW, y * CH, x * CW + CW - 1, y * CH + CH // 2 - 1], fill=fg)
                d.rectangle([x * CW, y * CH + CH // 2, x * CW + CW - 1, y * CH + CH - 1], fill=bg)
            else:
                d.rectangle([x * CW, y * CH, x * CW + CW - 1, y * CH + CH - 1], fill=bg)
                if c.data.strip():
                    d.text((x * CW, y * CH - 1), c.data, fill=fg, font=fnt)
    return img


pid, fd = pty.fork()
if pid == 0:
    os.environ.update(TERM='xterm-256color', COLORTERM='truecolor')
    os.execv(EXE, [EXE, '--no-save', '--autoplay'])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', ROWS, COLS, 0, 0))
screen = pyte.Screen(COLS, ROWS)
stream = pyte.ByteStream(screen)
fnt = font()
frames, t0, n = [], time.time(), 0
while n < SECONDS * FPS:
    end = t0 + n / FPS
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.01)
        if r:
            d = os.read(fd, 65536)
            if b'\x1b[c' in d:
                os.write(fd, b'\x1b[?62;c')
            stream.feed(d)
    if n >= 5:                                   # the first half second is the start-up
        frames.append(picture(screen, fnt))
    n += 1
os.close(fd)
os.kill(pid, signal.SIGKILL)
os.waitpid(pid, 0)
out = os.path.join(HERE, '..', 'docs', 'gameplay.gif')
os.makedirs(os.path.dirname(out), exist_ok=True)
frames[0].save(out, save_all=True, append_images=frames[1:], duration=1000 // FPS, loop=0, optimize=True)
print(len(frames), 'frames,', os.path.getsize(out) // 1024, 'KB')
