#!/usr/bin/env python3
"""fpu_check.py OBJDUMP CXXFILT [--allow FILE] OBJECT... - fail on FPU code in the game's objects.

The package is one binary for every 68040 and 68060: the port is built
-msoft-float, and the stove's fpuauto wrappers (from libfpuauto.a, not one
of these objects) take the FPU only when there is one. A 68881/68882
instruction in the port's own objects would trap on a 68LC040, so the build
stops. On m68k every FPU mnemonic starts with "f" and no integer one does.

AmigaOS objects keep constant tables in .text, and objdump decodes them as
code, so a table can look like an FPU instruction. A hit is data, and
passes, when its symbol is a C++ object rather than a function: CXXFILT
(m68k-amigaos-c++filt) demangles it to a name that doesn't end in a
parameter list, such as Math::sineWindow512 or
Scumm::ScummEngine::resetPalette(bool)::tableNESNTSCPalette. A hit in a
C++ object's exception tables are data too: the amiga format has no
.eh_frame section, so GCC puts the frame records in .text after
__EH_FRAME_BEGIN__. A hit in a
function, or in a C symbol (which can't be told apart), fails unless --allow
names it ("OBJECT-BASENAME SYMBOL  # why" per line).

objdump decodes for the 68040 (-m m68k:68040): as a plain m68k it reads
the 68020's bra.l as a short branch and its 32-bit offset as an FPU
instruction.

Prints each object with hits, then a summary; exits 1 on any hit that fails.
"""
import os
import re
import subprocess
import sys

INSN = re.compile(r"^\s*[0-9a-f]+:\t[0-9a-f ]+\t(\S+)")
LABEL = re.compile(r"^[0-9a-f]+ <(.+)>:$")
EH_FRAME = {"__EH_FRAME_BEGIN__", "___EH_FRAME_BEGIN__", "__FRAME_END__", "___FRAME_END__"}
FUNCTION = re.compile(r"\)(?: const| volatile| &&| &| noexcept)*$")


def fpu_hits(listing: str) -> list[tuple[str, str]]:
    """(symbol, mnemonic) for each FPU mnemonic in an objdump -d listing."""
    found, sym = [], ""
    for line in listing.splitlines():
        lab = LABEL.match(line)
        if lab:
            sym = lab.group(1)
            continue
        m = INSN.match(line)
        if m and m.group(1).startswith("f"):
            found.append((sym, m.group(1)))
    return found


def is_data(symbol: str, demangled: str) -> bool:
    """A C++ object (a table) or the exception frame records, not a function
    and not a C symbol."""
    if symbol in EH_FRAME:
        return True
    return symbol.startswith("__Z") and demangled != symbol and not FUNCTION.search(demangled)


def demangle(cxxfilt: str, symbols: list[str]) -> dict[str, str]:
    if not symbols:
        return {}
    out = subprocess.run([cxxfilt, "-_"], input="\n".join(symbols) + "\n", capture_output=True, text=True,
                         check=True).stdout.splitlines()
    return dict(zip(symbols, out))


def read_allow(text: str) -> set[tuple[str, str]]:
    allow = set()
    for line in text.splitlines():
        words = line.split("#", 1)[0].split()
        if words:
            if len(words) != 2:
                raise SystemExit(f"--allow: want OBJECT SYMBOL, got {' '.join(words)}")
            allow.add((words[0], words[1]))
    return allow


def main(argv: list[str]) -> int:
    args = argv[1:]
    if len(args) < 2:
        print(__doc__.splitlines()[0], file=sys.stderr)
        return 2
    objdump, cxxfilt, args = args[0], args[1], args[2:]
    allow: set[tuple[str, str]] = set()
    if args[:1] == ["--allow"]:
        with open(args[1], encoding="utf-8") as f:
            allow = read_allow(f.read())
        args = args[2:]
    bad = tables = 0
    for obj in args:
        out = subprocess.run([objdump, "-m", "m68k:68040", "-d", obj], capture_output=True, text=True, check=True).stdout
        hits = fpu_hits(out)
        if not hits:
            continue
        names = demangle(cxxfilt, sorted({s for s, _ in hits}))
        base = os.path.basename(obj)
        real = [(s, m) for s, m in hits if not is_data(s, names.get(s, s)) and (base, s) not in allow]
        kind = "FAIL" if real else "data"
        shown = real or hits
        print(f"{kind} {obj}: {len(hits)} ({', '.join(sorted({names.get(s, s) + ': ' + m for s, m in shown}))})")
        bad += bool(real)
        tables += not real
    print(f"{len(args)} objects, {bad} with FPU instructions ({tables} with constant tables objdump reads as code)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
