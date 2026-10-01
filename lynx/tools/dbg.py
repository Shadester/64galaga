#!/usr/bin/env python3
"""Debug helper: run ROM for N frames, then print PC and the values of named labels (from build/galaga.lbl).
Usage: dbg.py ROM FRAMES [label[:size] ...]"""
import json, re, sys
sys.path.insert(0, __import__('os').path.dirname(__file__))
from gearlynx import Gearlynx
lbl = open(__import__('os').path.join(__import__('os').path.dirname(__file__), '..', 'build', 'galaga.lbl')).read()
with Gearlynx() as g:
    g.load(sys.argv[1])
    g.frames(int(sys.argv[2]))
    s = json.loads(g.tool('debug_get_status')[0]['text'])
    print('pc', s['pc'])
    for a in sys.argv[3:]:
        name, _, size = a.partition(':')
        m = re.search(r'al ([0-9A-F]+) \.%s\n' % re.escape(name), lbl)
        if not m:
            print(name, 'no label'); continue
        d = json.loads(g.tool('read_memory', area=0, offset='$' + m.group(1), size=int(size or 1))[0]['text'])['data']
        print(name, m.group(1), d)
