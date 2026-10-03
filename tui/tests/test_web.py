#!/usr/bin/env python3
"""The browser version (../docs/tui) in headless Chromium: the page runs, draws, takes keys, saves the hi-score, and the WebAssembly module plays
the same game as the native build. Needs playwright (pip install playwright; playwright install chromium); builds the module first.
Usage: python3 tests/test_web.py"""
import functools
import http.server
import os
import subprocess
import sys
import threading

from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
TUI = os.path.join(HERE, '..')
DOCS = os.path.join(TUI, '..', 'docs')
subprocess.run([os.path.join(TUI, 'tools', 'build_web.sh')], check=True, stdout=subprocess.DEVNULL)
native = int(subprocess.run(['cargo', 'run', '--release', '-q', '--example', 'checksum', '--', '4000'], cwd=TUI, check=True, capture_output=True, text=True).stdout)

class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


handler = functools.partial(Quiet, directory=DOCS)
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()
URL = 'http://127.0.0.1:%d/tui/index.html' % srv.server_address[1]
bad = 0


def check(name, ok, extra=''):
    global bad
    print(('PASS ' if ok else 'FAIL ') + name + (' ' + str(extra) if extra and not ok else ''))
    bad += not ok


def pixels(page):
    """How many canvas pixels are not black."""
    return page.evaluate("""() => { const c = document.getElementById('c'); const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
        let n = 0; for (let i = 0; i < d.length; i += 4) if (d[i] || d[i + 1] || d[i + 2]) n++; return n; }""")


with sync_playwright() as p:
    b = p.chromium.launch()
    errors = []

    def new(width, height, query=''):
        pg = b.new_context(viewport={'width': width, 'height': height}).new_page()
        pg.on('pageerror', lambda e: errors.append(str(e)))
        pg.on('console', lambda m: errors.append(m.text) if m.type == 'error' else None)
        pg.goto(URL + query)
        pg.wait_for_function('window.__galaga && window.__galaga.ticks > 5')
        return pg

    pg = new(1100, 760, '?autoplay&god')
    pg.wait_for_timeout(4000)
    check('the page draws the game', pixels(pg) > 5000, pixels(pg))
    check('the game runs at about 50 ticks a second', 150 < pg.evaluate('window.__galaga.ticks') < 330)
    pg.screenshot(path='/tmp/tui_web_big.png')
    check('the module plays the same game as the native build (checksum after 4000 ticks)',
          pg.evaluate("() => { const x = window.__galaga.x; x.web_init(0, 0, 1, 1, 137, 40); for (let i = 0; i < 4000; i++) x.web_tick(0); return x.web_checksum(); }") == native, native)
    pg.keyboard.press('q')
    pg.wait_for_timeout(200)
    check('the hi-score is saved in localStorage', int(pg.evaluate("localStorage.getItem('galaga-tui-hi') || '0'")) > 0)
    pg.set_viewport_size({'width': 500, 'height': 300})
    pg.wait_for_timeout(300)
    pg.screenshot(path='/tmp/tui_web_small.png')
    check('a small window still draws (the message)', pixels(pg) > 100)

    pg = new(900, 640)
    state = lambda: pg.evaluate('window.__galaga.x.web_state()')
    chk = lambda: pg.evaluate('window.__galaga.x.web_checksum()')
    check('starts on the title screen', state() == 0)
    pg.keyboard.press('Space')
    pg.wait_for_timeout(300)
    check('Space starts the game', state() == 1)
    pg.wait_for_timeout(3500)
    check('the intro ends and the play begins', state() == 2)
    before = chk()
    pg.keyboard.down('ArrowLeft')
    pg.wait_for_timeout(500)
    pg.keyboard.up('ArrowLeft')
    mid = chk()
    pg.wait_for_timeout(300)
    check('the ship moves while the key is down', abs(mid - before) > 30, (before, mid))
    still = chk()
    pg.wait_for_timeout(300)
    check('and it stops when the key is up', (chk() - still) < 40, (still, chk()))   # (the frame counter still counts)
    pg.keyboard.press('Space')
    pg.keyboard.press('p')
    pg.wait_for_timeout(300)
    paused = chk()
    pg.wait_for_timeout(300)
    check('P pauses', chk() == paused)
    pg.screenshot(path='/tmp/tui_web_play.png')
    check('no errors in the console', not errors, errors[:3])
    b.close()

sys.exit(1 if bad else 0)
