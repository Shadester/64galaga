#!/usr/bin/env python3
"""Generate Galaga/paths_data.py from the path builder in psp/game.c (so the Python port has the same paths).
Usage: python3 tools/gen_paths.py"""
import os
import subprocess
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
exe = os.path.join(root, 'build', 'dump_paths')
os.makedirs(os.path.join(root, 'build'), exist_ok=True)
subprocess.run(['cc', '-O1', '-w', '-o', exe, os.path.join(root, 'tools', 'dump_paths.c'), '-lm'], check=True)
out = subprocess.run([exe], check=True, capture_output=True, text=True).stdout
open(os.path.join(root, 'Galaga', 'paths_data.py'), 'w').write(out)
print('Galaga/paths_data.py', len(out), 'bytes')
