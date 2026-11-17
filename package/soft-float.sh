#!/bin/sh
# soft-float.sh STOVE PROGRAM [--allow FILE] [--log FILE]... OBJECT-OR-DRAWER...
# The checks every port's package build makes after its build: one binary
# for every 68040 and 68060, built -m68040 -msoft-float, so the stove's
# fpuauto takes the FPU only when there is one.
# - each --log (a build's output): it shows compile lines, each compile and
#   link is -m68040 -msoft-float, and -m68881 is nowhere in it;
# - each object (*.o and *.a, or every one under a drawer): no FPU
#   instruction (package/fpu_check.py; --allow, by default
#   package/fpu-allow.txt, names C constant tables, "OBJECT SYMBOL  # why"
#   a line);
# - PROGRAM (not stripped, or its .debug): fpuauto is linked in.
# STOVE is the stove's prefix (bin/m68k-amigaos-*). Exits 1 on the first
# check that fails, with what failed.
# MIT, Copyright (c) 2026 AmiCradle Team.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STOVE=$1 PROGRAM=$2
shift 2
ALLOW= LOGS=
while [ $# -gt 0 ]; do
	case $1 in
	--allow) ALLOW=$2; shift 2 ;;
	--log) LOGS="$LOGS
$2"; shift 2 ;;
	*) break ;;
	esac
done

echo "$LOGS" | while IFS= read -r log; do
	[ -n "$log" ] || continue
	! grep -q -- '-m68881' "$log" || { echo "FAIL $log: -m68881 is in the build"; exit 1; }
	grep -E 'm68k-amigaos-g(cc|\+\+)( |$)' "$log" | grep -qE ' -c | -o ' ||
		{ echo "FAIL $log shows no compile lines to check (make it print them)"; exit 1; }
	if grep -E 'm68k-amigaos-g(cc|\+\+)( |$)' "$log" | grep -E ' -c | -o ' | grep -v -- '-m68040 -msoft-float' | grep -q .; then
		echo "FAIL $log: a compile or link without -m68040 -msoft-float:"
		grep -E 'm68k-amigaos-g(cc|\+\+)( |$)' "$log" | grep -E ' -c | -o ' | grep -v -- '-m68040 -msoft-float' | head -n 3
		exit 1
	fi
done

LIST=$(mktemp "${TMPDIR:-/tmp}/soft-float.XXXXXX")
trap 'rm -f "$LIST"' EXIT INT TERM
for o in "$@"; do
	if [ -d "$o" ]; then find "$o" \( -name '*.o' -o -name '*.a' \) -type f; else echo "$o"; fi
done | sort > "$LIST"
[ -s "$LIST" ] || { echo "FAIL no objects to check"; exit 1; }
# Without --allow, package/fpu-allow.txt when there is one.
[ -n "$ALLOW" ] || [ ! -f "$HERE/fpu-allow.txt" ] || ALLOW="$HERE/fpu-allow.txt"
set --
[ -z "$ALLOW" ] || set -- --allow "$ALLOW"
# shellcheck disable=SC2046
python3 "$HERE/fpu_check.py" "$STOVE/bin/m68k-amigaos-objdump" "$STOVE/bin/m68k-amigaos-c++filt" "$@" \
	$(cat "$LIST") > "$LIST.out" || { grep '^FAIL' "$LIST.out"; rm -f "$LIST.out"; exit 1; }
tail -n 1 "$LIST.out"
rm -f "$LIST.out"
"$STOVE/bin/m68k-amigaos-nm" "$PROGRAM" | grep -q '___fpuauto_select' ||
	{ echo "FAIL fpuauto is not linked into $PROGRAM"; exit 1; }
echo "soft float: OK ($(wc -l < "$LIST") objects, fpuauto linked)"
