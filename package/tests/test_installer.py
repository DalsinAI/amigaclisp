#!/usr/bin/env python3
"""Host tests for the Installer and the soft-float package build.

python3 package/tests/test_installer.py, from the checkout (no stove needed):
- each package/*installer.json and the Install script made from it
  (amicradle scripts/ports/port_installer.py): a 68040 with an FPU, this
  version, every data item's drawer, download (address, SHA-256, size) and
  import in the script;
- package/soft-float.json's Makefiles: soft float by default, no -m68881;
  package/build-amiga.sh (or soft-float.json's builds) runs
  package/soft-float.sh;
- package/soft-float.sh stops on a build log with -m68881, with a compile
  without -msoft-float, or with no compile lines;
- package/fpu_check.py: tables are data, functions are code;
- package/fpu-allow.txt, when there is one: "OBJECT SYMBOL  # why" a line.
MIT, Copyright (c) 2026 AmiCradle Team.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PKG = ROOT / "package"
checks = fails = 0


def check(ok: bool, what: str) -> None:
    global checks, fails
    checks += 1
    if not ok:
        fails += 1
        print(f"FAIL {what}")


HEX64 = re.compile(r"[0-9a-f]{64}")
sf = json.loads((PKG / "soft-float.json").read_text())
specs = sorted(PKG.glob("*installer.json"))
check(specs != [], "package/ has an Installer spec")
for path in specs:
    spec = json.loads(path.read_text())
    drawer, name = spec["drawer"], path.name
    fpu = sf.get("fpu", True)              # false: the port runs without an FPU too
    check(spec.get("cpu") == "68040" and spec.get("fpu") is fpu, f"{name}: a 68040" + (" with an FPU" if fpu else ""))
    inst_path = PKG / "installer" / f"Install-{drawer}"
    check(inst_path.is_file() and (PKG / "installer" / f"Install-{drawer}.info").is_file(),
          f"{name}: Install-{drawer} and its icon are in package/installer")
    if not inst_path.is_file():
        continue
    inst = inst_path.read_text(encoding="latin-1")
    check(inst.startswith(f"; $VER: Install-{drawer} {spec['version']} ("), f"{name}: Install-{drawer} is version {spec['version']}")
    for k in spec.get("keep", []):
        check(k in inst, f"{name}: an update keeps {k}")
    for m in spec.get("modules", []):
        check(m in inst, f"{name}: the Installer checks for {m}")
    for d in spec.get("data", []):
        what = d["what"]
        check(bool(d.get("files") or d.get("any")), f"{name}: {what} names its files")
        check(not d.get("into") or d["into"] in inst, f"{name}: {what} goes into {d.get('into') or 'the drawer'}")
        for f in d.get("files", []) + d.get("any", []):
            check(f in inst, f"{name}: the Installer looks for {f}")
        dl = d.get("download")
        if dl:
            check(dl["url"].startswith("https://"), f"{name}: {what} is fetched over https")
            check(bool(HEX64.fullmatch(dl["sha256"])), f"{name}: {what} has a SHA-256")
            check(isinstance(dl["size"], int) and dl["size"] > 0, f"{name}: {what} has a size")
            check(dl["url"] in inst and dl["sha256"] in inst, f"{name}: C:Atlas FETCH gets {dl['url']} and checks its SHA-256")
            check("C:Atlas FETCH" in inst, f"{name}: the download is C:Atlas FETCH")
        check(bool(dl) or bool(d.get("import", True)), f"{name}: {what} has a download or an import")

for mk in sf["makefiles"]:
    text = (ROOT / mk).read_text()
    check("-m68881" not in text, f"{mk} has no -m68881")
    check(re.search(r"^CPU\s*\??=\s*-m68040 -msoft-float\s*$", text, re.M) is not None or mk in sf.get("no_cpu", []),
          f"{mk}: CPU is -m68040 -msoft-float by default")
for b in sf.get("builds", ["package/build-amiga.sh"]):
    build = (ROOT / b).read_text()
    check("soft-float.sh" in build, f"{b} runs package/soft-float.sh")
    check("-m68881" not in build, f"{b} has no -m68881")

with tempfile.TemporaryDirectory() as t:
    t = Path(t)
    stove = t / "stove"
    (stove / "bin").mkdir(parents=True)
    cc = "/x/bin/m68k-amigaos-gcc"
    cases = {
        "hard": (f"{cc} -noixemul -m68040 -m68881 -c -o a.o a.c\n", "-m68881 is in the build"),
        "nosoft": (f"{cc} -noixemul -m68040 -c -o a.o a.c\n", "without -m68040 -msoft-float"),
        "quiet": ("CC a.o\nLD game\n", "no compile lines"),
        "good": (f"{cc} -noixemul -m68040 -msoft-float -c -o a.o a.c\n", "no objects to check"),
    }
    for case, (log, want) in cases.items():
        (t / case).write_text(log)
        (t / f"{case}-objs").mkdir()
        r = subprocess.run(["sh", str(PKG / "soft-float.sh"), str(stove), str(t / "game"), "--log", str(t / case),
                            str(t / f"{case}-objs")], capture_output=True, text=True)
        check(r.returncode == 1 and want in r.stdout, f"soft-float.sh stops on {case!r} ({want})")

sys.path.insert(0, str(PKG))
import fpu_check  # noqa: E402
check(fpu_check.is_data("__EH_FRAME_BEGIN__", "__EH_FRAME_BEGIN__"), "fpu_check reads the exception frame records as data")
check(not fpu_check.is_data("_main", "_main"), "fpu_check fails an FPU instruction in a C function")
check(fpu_check.is_data("__ZN4Math13sineWindow512E", "Math::sineWindow512"), "fpu_check reads a C++ table as data")
check(fpu_check.fpu_hits("00000000 <_f>:\n   0:\tf200 0400 \tfmovel %d0,%fp0\n") == [("_f", "fmovel")],
      "fpu_check finds an FPU instruction")
switch = ("00000000 <_f>:\n   0:\t303b 0a06 \tmovew %pc@(8 <_f+0x8>,%d0:l:2),%d0\n"
          "   4:\t4efb 0002 \tjmp %pc@(8 <_f+0x8>,%d0:w)\n   8:\tf2c2 0004 \tfbogtl 12\n"
          "   c:\tf200 0400 \tfmovel %d0,%fp0\n")
check(fpu_check.fpu_hits(switch) == [("_f", "fmovel")], "fpu_check skips a switch's jump table, and finds code after it")
backward = ("00000000 <_g>:\n   0:\t4efb 0002 \tjmp %pc@(4 <_g+0x4>,%d0:w)\n   4:\tf2c2 fffc \tfbogtl 2\n"
            "00000008 <_h>:\n   8:\tf200 0400 \tfmovel %d0,%fp0\n")
check(fpu_check.fpu_hits(backward) == [("_h", "fmovel")], "a jump table with every case before it ends at the next symbol")

allow = PKG / "fpu-allow.txt"
if allow.exists():
    for line in allow.read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            words, _, why = line.partition("#")
            check(len(words.split()) == 2 and why.strip() != "", f"fpu-allow.txt: OBJECT SYMBOL  # why ({line})")

print(f"installer and soft float: {checks} checks, {fails} failed")
sys.exit(1 if fails else 0)
