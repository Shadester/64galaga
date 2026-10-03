#!/usr/bin/env python3
"""Runs the release binary in a pseudo-terminal and checks what a terminal sees: the game starts and draws, Q leaves from the title screen
and gives the terminal back, a small window gets a message, a resize draws again, the kitty keyboard protocol is switched on and off.
Usage: python3 tests/test_terminal.py   (stdlib only; builds the program first)"""
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = os.path.join(HERE, '..', 'target', 'release', 'galaga-tui')
subprocess.run(['cargo', 'build', '--release', '-q'], cwd=os.path.join(HERE, '..'), check=True)


class Pty:
    def __init__(self, rows, cols, *args, kitty=False):
        self.kitty, self.buf = kitty, b''
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.environ.update(TERM='xterm-256color', COLORTERM='truecolor')
            os.execv(EXE, [EXE, '--no-save', *args])
        self.resize(rows, cols)

    def resize(self, rows, cols):
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
        os.kill(self.pid, signal.SIGWINCH)

    def pump(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.05)
            if r:
                try:
                    d = os.read(self.fd, 65536)
                except OSError:
                    return
                if b'\x1b[c' in d:        # the program asks which keyboard protocol we have
                    os.write(self.fd, (b'\x1b[?0u' if self.kitty else b'') + b'\x1b[?62;c')
                self.buf += d

    def send(self, data, wait=0.3):
        os.write(self.fd, data)
        self.pump(wait)

    def exited(self):
        try:
            p, st = os.waitpid(self.pid, os.WNOHANG)
        except ChildProcessError:
            return True
        return bool(p) and os.WEXITSTATUS(st) == 0

    def close(self):
        try:
            os.kill(self.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        os.close(self.fd)
        try:
            os.waitpid(self.pid, 0)
        except ChildProcessError:
            pass


bad = 0


def check(name, ok):
    global bad
    print(('PASS ' if ok else 'FAIL ') + name)
    bad += not ok


p = Pty(30, 90)
p.pump(1.0)
check('draws the title screen (half blocks, 24-bit colour)', '▀'.encode() in p.buf and b'\x1b[38;2;' in p.buf)
check('uses the alternate screen and hides the cursor', b'\x1b[?1049h' in p.buf and b'\x1b[?25l' in p.buf)
p.send(b'q', 1.0)
check('Q on the title screen leaves and gives the terminal back', p.exited() and b'\x1b[?1049l' in p.buf and b'\x1b[?25h' in p.buf)
p.close()

for key, name in ((b'\x03', 'Ctrl-C'), (b'\x1b', 'Esc')):
    p = Pty(30, 90)
    p.pump(1.0)
    p.send(key, 1.0)
    check(name + ' leaves', p.exited() and b'\x1b[?1049l' in p.buf)
    p.close()

p = Pty(30, 90, '--autoplay')
p.pump(1.5)
p.buf = b''
p.resize(20, 70)
p.pump(1.0)
check('a small window gets a message', b'Please make the window' in p.buf)
p.buf = b''
p.resize(56, 170)
p.pump(1.0)
check('a big window is drawn again', len(p.buf) > 20000)
p.close()

p = Pty(30, 90, kitty=True)
p.pump(1.0)
check('the kitty keyboard flags are pushed', b'\x1b[>' in p.buf)
p.send(b'\x1b[32u')
p.send(b'\x1b[32;1:3u')       # space down and up: starts the game
p.send(b'\x1b[97u', 0.5)
p.send(b'\x1b[97;1:3u')       # A down and up
p.send(b'\x1b[113u')
p.send(b'\x1b[113;1:3u')      # Q: back to the title
p.send(b'\x1b[113u', 0.5)     # Q: leave
check('with key releases: plays, leaves, pops the flags', p.exited() and b'\x1b[<1u' in p.buf)
p.close()

sys.exit(1 if bad else 0)
