#!/usr/bin/env python3
"""Drive Gearlynx headless through its MCP server (JSON-RPC over stdio).

Library: `with Gearlynx() as g: g.load('build/galaga.lnx'); g.frames(200); g.screenshot('x.png')`.
CLI:     gearlynx.py tools                       list the MCP tools and their arguments
         gearlynx.py shot ROM FRAMES OUT.png     run ROM for FRAMES frames, save a screenshot
"""
import base64
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = '/Applications/Gearlynx.app/Contents/MacOS/gearlynx'
BIOS = os.environ.get('LYNX_BIOS', os.path.join(HERE, '..', 'lynxboot.img'))


class Gearlynx:
    def __init__(self):
        self.p = subprocess.Popen([EXE, '--headless', '--mcp-stdio'], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        self.n = 0
        self.rpc('initialize', {'protocolVersion': '2024-11-05', 'capabilities': {},
                                'clientInfo': {'name': 'galagas', 'version': '1'}})
        self.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.p.kill()

    def send(self, msg):
        self.p.stdin.write(json.dumps(msg) + '\n')
        self.p.stdin.flush()

    def rpc(self, method, params=None):
        self.n += 1
        self.send({'jsonrpc': '2.0', 'id': self.n, 'method': method, 'params': params or {}})
        while True:
            r = json.loads(self.p.stdout.readline())
            if r.get('id') == self.n:
                if 'error' in r:
                    raise RuntimeError(r['error'])
                return r['result']

    def tool(self, name, **args):
        r = self.rpc('tools/call', {'name': name, 'arguments': args})
        if r.get('isError'):
            raise RuntimeError(r['content'])
        return r['content']

    def load(self, rom, bios=BIOS):
        self.tool('load_bios', file_path=os.path.abspath(bios))
        self.tool('load_media', file_path=os.path.abspath(rom))

    def frames(self, n):
        while n > 0:                                    # the tool steps at most 1000 frames at a time
            self.tool('debug_step_frame', frames=min(n, 1000), mode='sync')
            n -= 1000

    def screenshot(self, out):
        for c in self.tool('get_screenshot'):
            if c.get('type') == 'image':
                open(out, 'wb').write(base64.b64decode(c['data']))
                return
        raise RuntimeError('no image in screenshot reply')


if __name__ == '__main__':
    with Gearlynx() as g:
        if sys.argv[1] == 'tools':
            for t in g.rpc('tools/list')['tools']:
                print(t['name'], json.dumps(t.get('inputSchema', {}).get('properties', {})))
        elif sys.argv[1] == 'shot':
            g.load(sys.argv[2])
            g.frames(int(sys.argv[3]))
            g.screenshot(sys.argv[4])
