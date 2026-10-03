#!/usr/bin/env python3
"""A small client of the VICE binary monitor: run a PRG in x64sc, stop at an address each time it is reached, read memory.

    with Vice(prg) as v:
        v.add_stop(0x087f)          # e.g. the label tick_mark
        v.start()                   # autostarts the PRG
        while True:
            v.wait_stop()           # blocks until the stop
            data = v.read(0x2387, 32)
            v.resume()

The protocol is described in the VICE manual (chapter "Binary monitor"). Only the commands used here are implemented."""
import socket
import struct
import subprocess
import time

STX, API = 0x02, 0x02
MEM_GET, CP_SET, CP_DEL, EXIT, AUTOSTART, PING = 0x01, 0x12, 0x13, 0xAA, 0xDD, 0x81
EV_STOPPED, EV_RESUMED = 0x62, 0x63


class Vice:
    def __init__(self, prg, port=6502, extra=()):
        self.prg, self.port = prg, port
        self.rid = 0
        self.stopped = False
        self.cmd = ['x64sc', '-default', '+sound', '-warp', '-console', '-VICIIdsize', '-VICIIfilter', '0',
                    '-binarymonitor', '-binarymonitoraddress', 'ip4://127.0.0.1:%d' % port, *extra]

    def __enter__(self):
        self.proc = subprocess.Popen(self.cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(100):
            try:
                self.sock = socket.create_connection(('127.0.0.1', self.port))
                break
            except OSError:
                time.sleep(0.1)
        else:
            raise RuntimeError('cannot connect to the VICE monitor')
        self.sock.settimeout(60)
        self.buf = b''
        return self

    def __exit__(self, *a):
        try:
            self.sock.close()
        finally:
            self.proc.kill()
            self.proc.wait()

    def _read(self, n):
        while len(self.buf) < n:
            d = self.sock.recv(65536)
            if not d:
                raise RuntimeError('VICE closed the monitor')
            self.buf += d
        r, self.buf = self.buf[:n], self.buf[n:]
        return r

    def _response(self):
        h = self._read(12)
        assert h[0] == STX, h
        ln, typ, err, rid = struct.unpack('<IBBI', h[2:12])
        return typ, err, rid, self._read(ln)

    def _send(self, cmd, body=b''):
        self.rid += 1
        self.sock.sendall(struct.pack('<BBIIB', STX, API, len(body), self.rid, cmd) + body)
        return self.rid

    def _call(self, cmd, body=b''):
        rid = self._send(cmd, body)
        while True:
            typ, err, r, data = self._response()
            if r == rid:
                if err:
                    raise RuntimeError('VICE monitor error %02x for command %02x' % (err, cmd))
                return data
            self._event(typ)

    def _event(self, typ):
        if typ == EV_STOPPED:
            self.stopped = True
        elif typ == EV_RESUMED:
            self.stopped = False

    def add_stop(self, addr):
        """Stop whenever the CPU is about to execute addr."""
        self._call(CP_SET, struct.pack('<HHBBBBB', addr, addr, 1, 1, 4, 0, 0))   # stop, enabled, exec, not temporary, main memspace

    def start(self):
        name = self.prg.encode()
        self._call(AUTOSTART, struct.pack('<BHB', 1, 0, len(name)) + name)

    def wait_stop(self):
        while not self.stopped:
            typ, err, rid, data = self._response()
            self._event(typ)

    def read(self, addr, n):
        data = self._call(MEM_GET, struct.pack('<BHHBH', 0, addr, addr + n - 1, 0, 0))
        ln = struct.unpack('<H', data[:2])[0]
        assert ln == n
        return list(data[2:2 + n])

    def resume(self):
        self.stopped = False
        self._call(EXIT)


if __name__ == '__main__':
    import sys
    prg = sys.argv[1]
    with Vice(prg) as v:
        v.add_stop(int(sys.argv[2], 16))
        v.start()
        t0 = time.time()
        for i in range(int(sys.argv[3])):
            v.wait_stop()
            if i % 100 == 0:
                print(i, v.read(int(sys.argv[4], 16), 1), '%.1fs' % (time.time() - t0))
            v.resume()
