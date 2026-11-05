#!/usr/bin/env python3
"""AmigaCLISP: turn .fas files made on a little-endian host big-endian.

Every compiled function's code vector, written #<n>Y(<hex bytes>) in a .fas
file, starts with a header of 16-bit words in the byte order of the Lisp that
compiled it (lispbibl.d, Codevec): stack depths, required and optional
argument counts at bytes 0-7, flags at byte 8, and, when flag bit 7 (&KEY) is
set, the keyword count and offset at bytes 10-13. The 68k reads them
big-endian, so swap each of those words. The byte code after the header is
byte-wise and stays as it is.

usage: fas-be.py IN.fas OUT.fas
Copyright (c) 2026 AmigaChrome Team. GPL-2.0-or-later, as CLISP.
"""
import re
import sys

CODEVEC = re.compile(rb'#(\d+)Y\(([0-9A-Fa-f\s]*)\)')


def swap(match):
    n = int(match.group(1))
    body = match.group(2)
    tokens = body.split()
    if len(tokens) != n or n < 10:
        raise SystemExit('fas-be: code vector of %d bytes has %d' % (n, len(tokens)))
    words = [0, 2, 4, 6]
    if int(tokens[8], 16) & 0x80:
        if n < 14:
            raise SystemExit('fas-be: &key code vector shorter than 14 bytes')
        words += [10, 12]
    for w in words:
        tokens[w], tokens[w + 1] = tokens[w + 1], tokens[w]
    # keep the line breaks: put the swapped tokens back in the old spacing
    out, i = [], 0
    for piece in re.split(rb'(\s+)', body):
        if piece and not piece.isspace():
            out.append(tokens[i]); i += 1
        else:
            out.append(piece)
    return b'#%dY(%s)' % (n, b''.join(out))


def main():
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, 'rb').read()
    new, count = CODEVEC.subn(swap, data)
    open(dst, 'wb').write(new)
    print('fas-be: %s: %d code vectors' % (src.rsplit('/', 1)[-1], count))


if __name__ == '__main__':
    main()
