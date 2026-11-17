#!/bin/sh
# AmigaCLISP release archive, for Cradle's stove_build (target package): runs
# the top build-amiga.sh (cached stages are reused, so run it again until it
# says DONE), checks the soft-float build with package/soft-float.sh (no FPU
# instruction in lisp's objects, fpuauto linked in), then packs
# AmigaCLISP-VERSION.lha with our own LhA packer: the AmigaCLISP drawer
# (with its ReadMe and CLISP icons) and its icon, and at the archive's root
# the Installer (Install-AmigaCLISP and its icon, made by amicradle's
# scripts/ports/port_installer.py from package/installer.json). Also the
# archive in parts under 256 KiB for taking from a lab, and its .sha256.
# VERSION is package/VERSION. CLISP_CACHE is Team 2's on daletop unless set.
# Copyright (c) 2026 AmiCradle Team. GPL-2.0-or-later, as CLISP.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(dirname "$HERE")
OUT=${OUT:?OUT is not set}
VERSION=${CLISP_VERSION:-$(cat "$HERE/VERSION")}
T2=/home/da1ek/AmiCradle-dev/teams/team2/scratch
[ -n "${CLISP_CACHE:-}" ] || [ ! -d "$T2" ] || export CLISP_CACHE="$T2/clisp-cache-os32-gcc16"
CACHE=${CLISP_CACHE:-$HOME/.cache/amigaclisp}
export JOBS=${JOBS:-2}
sh "$TOP/build-amiga.sh" > "$OUT/build.log" 2>&1 || { tail -n 60 "$OUT/build.log"; exit 1; }
tail -n 20 "$OUT/build.log"
grep -q '] DONE$' "$OUT/build.log" || { echo "top build not done: run again"; exit 1; }

# One binary for every 68040 and 68060: lisp's objects have no FPU
# instruction (the stove's fpuauto takes the FPU when there is one).
sh "$HERE/soft-float.sh" "${STOVE%/}/prefix" "$CACHE/cross/lisp.run" "$CACHE/cross" > "$OUT/soft-float.txt" ||
	{ cat "$OUT/soft-float.txt"; exit 1; }
cat "$OUT/soft-float.txt"

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/amigaclisp-package.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT INT TERM
cp -R "$OUT/AmigaCLISP" "$STAGE/AmigaCLISP"
cp "$TOP/icons/ReadMe.info" "$TOP/icons/CLISP.info" "$STAGE/AmigaCLISP/"
cp "$TOP/icons/AmigaCLISP.info" "$STAGE/AmigaCLISP.info"
head -n 1 "$HERE/installer/Install-AmigaCLISP" | grep -q "^; \$VER: Install-AmigaCLISP $VERSION (" ||
	{ echo "package/installer/Install-AmigaCLISP is not for $VERSION: run port_installer.py again"; exit 1; }
cp "$HERE/installer/Install-AmigaCLISP" "$HERE/installer/Install-AmigaCLISP.info" "$STAGE/"
LHA=$OUT/AmigaCLISP-$VERSION.lha
python3 -I "$TOP/tools/mklha.py" --contents "$STAGE" "$LHA"
rm -rf "$OUT/lha-parts"; mkdir -p "$OUT/lha-parts"
split -b 200k -d -a 2 "$LHA" "$OUT/lha-parts/$(basename "$LHA")."
( cd "$OUT" && sha256sum "$(basename "$LHA")" ) > "$LHA.sha256"
cat "$LHA.sha256"
echo "lha DONE"
