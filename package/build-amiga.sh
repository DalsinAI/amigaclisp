#!/bin/sh
# AmigaCLISP release archive: runs the top build-amiga.sh (cached stages are
# reused), then packs OUT/AmigaCLISP into AmigaCLISP-<version>.lha with our own
# LhA packer, plus the archive in parts under 256 KiB for taking from a lab.
# Copyright (c) 2026 AmiCradle Team. GPL-2.0-or-later, as CLISP.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(dirname "$HERE")
OUT=${OUT:?OUT is not set}
VERSION=${CLISP_VERSION:-0.1-rc2}
sh "$TOP/build-amiga.sh" | tee "$OUT/build.log"
grep -q '] DONE$' "$OUT/build.log" || { echo "top build not done: run again"; exit 1; }
LHA=$OUT/AmigaCLISP-$VERSION.lha
python3 -I "$TOP/tools/mklha.py" "$OUT/AmigaCLISP" "$LHA"
rm -rf "$OUT/lha-parts"; mkdir -p "$OUT/lha-parts"
split -b 200k -d -a 2 "$LHA" "$OUT/lha-parts/$(basename "$LHA")."
( cd "$OUT" && sha256sum "$(basename "$LHA")" ) > "$OUT/lha.sha256"
cat "$OUT/lha.sha256"
echo "lha DONE"
