#!/usr/bin/env python3
"""Packs a drawer into an Amiga LhA archive (level-1 headers, lh5) with our own
packer (lha_archive.py, AmiCradle's LhA writer), and reads it back to check.
Usage: mklha.py <drawer> <archive.lha>   Scripts get the S protection bit.
Copyright (c) 2026 AmiCradle Team."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import lha_archive as L

SCRIPTS = {"CLISP", "Install", "MakeImage"}
root, out = Path(sys.argv[1]), Path(sys.argv[2])
members = [L.Member(p.relative_to(root.parent).as_posix(), p.read_bytes(),
                    0x40 if p.name in SCRIPTS else 0, "", p.stat().st_mtime)
           for p in sorted(root.rglob("*")) if p.is_file()]
L.write(out, members)
back = {m.path: m.data for m in L.read(out.read_bytes())}
bad = [m.path for m in members if back.get(m.path) != m.data]
if bad:
    sys.exit("read back differs: " + ", ".join(bad))
print(f"{out.name}: {len(members)} files, {out.stat().st_size} bytes, read back ok")
