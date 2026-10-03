#!/usr/bin/env python3
"""Count the PICO-8 tokens of Lua files (the cart limit is 8192). The pico8 command line does not check the limit, so this
follows the manual: names, numbers (a unary minus on a number is part of it), strings, keywords and operators count; ( [ { count,
the closing ) ] } do not; neither do , . : ; and the keywords end and local. Usage: python3 tools/p8_tokens.py file.lua [...]"""
import re
import sys

TOK = re.compile(r'''--\[\[.*?\]\]|--[^\n]*|\[\[.*?\]\]|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|0x[0-9a-fA-F.]+|\d+\.?\d*|[A-Za-z_]\w*|\.\.\.|\.\.|>>>|<<>|>><|[<>=~!]=|\+=|-=|\*=|/=|\\=|%=|\.\.=|\^=|\|=|&=|\^\^=|<<=|>>=|//|<<|>>|[-+*/%^#&|~<>=(){}\[\],;:.\\@$?]''', re.S)
SKIP = {',', '.', ':', ';', ')', ']', '}', 'end', 'local'}
OPEN = {'(', '[', '{', ',', '=', '+', '-', '*', '/', '%', '^', '<', '>', 'return', 'and', 'or', 'not', 'then', 'do', 'else', '\\', '&', '|', '<<', '>>', '..', '==', '~=', '!=', '<=', '>=', '#', '~', ';', 'in', 'if', 'while', 'until', 'elseif'}


def count(src):
    toks = [t for t in TOK.findall(src) if not t.startswith('--')]
    n, prev = 0, None
    for i, t in enumerate(toks):
        if t in SKIP:
            prev = t
            continue
        if t == '-' and (prev is None or prev in OPEN) and i + 1 < len(toks) and re.match(r'[\d]', toks[i + 1]):
            prev = t
            continue                      # "-5" is one token: the number counts
        n += 1
        prev = t
    return n


if __name__ == '__main__':
    total = 0
    for f in sys.argv[1:]:
        c = count(open(f).read())
        total += c
        print('%6d  %s' % (c, f))
    print('%6d  total' % total)
