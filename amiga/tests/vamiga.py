"""Runs an ADF in vAmigaWeb (https://vamigaweb.github.io, with its built-in AROS ROM: no copyrighted ROM) in a headless
browser. Needs: pip install playwright && playwright install chromium. The page asks the server for the ADF; a route
answers it from the file, so nothing is uploaded. Used by test_selftest.py and shots.py."""
import time

from playwright.sync_api import sync_playwright

URL = 'https://vamigaweb.github.io/#AROS=true#navbar=hidden#%shttps://adf.test/game.adf'


class Session:
    def __init__(self, adf, warp=None, size=(1000, 800)):
        """warp = number of frames to run as fast as possible (the emulator then plays at normal speed)."""
        self.data = open(adf, 'rb').read()
        self.warp = warp
        self.size = size

    def __enter__(self):
        self.p = sync_playwright().start()
        self.b = self.p.chromium.launch(args=['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
                                              '--autoplay-policy=no-user-gesture-required'])
        ctx = self.b.new_context(viewport={'width': self.size[0], 'height': self.size[1]}, service_workers='block')
        ctx.route('https://adf.test/**', lambda r: r.fulfill(status=200, body=self.data, headers={
            'Access-Control-Allow-Origin': '*', 'Content-Type': 'application/octet-stream'}))
        self.page = ctx.new_page()
        self.page.goto(URL % ('warpto=%d#' % self.warp if self.warp else ''))
        return self

    def __exit__(self, *a):
        self.b.close()
        self.p.stop()

    def shot(self, path):
        self.page.screenshot(path=path)

    def settle(self, path, timeout=180):
        """Waits until the picture does not change any more (a game that freezes with -DHALT), then saves it. The emulator runs at
        a speed that depends on the load of the Mac: a fixed time is not enough."""
        end, last, same = time.time() + timeout, None, 0
        while time.time() < end:
            self.page.wait_for_timeout(2000)
            shot = self.page.screenshot()
            same = same + 1 if shot == last else 0
            last = shot
            if same >= 2:
                break
        open(path, 'wb').write(last)

    def pixel_is(self, rgb, x=None, y=None, tol=40):
        """True if the screen pixel is this colour. Reads a screenshot (the emulator draws in a canvas)."""
        import io
        from PIL import Image
        im = Image.open(io.BytesIO(self.page.screenshot())).convert('RGB')
        p = im.getpixel((x if x is not None else self.size[0] // 2, y if y is not None else self.size[1] // 2))
        return all(abs(a - b) <= tol for a, b in zip(p, rgb))

    def wait_pixel(self, colours, timeout=300):
        """Waits until the middle of the screen has one of the colours {name: rgb}; returns the name (None: timeout)."""
        end = time.time() + timeout
        while time.time() < end:
            self.page.wait_for_timeout(2000)
            for name, rgb in colours.items():
                if self.pixel_is(rgb):
                    return name
        return None
