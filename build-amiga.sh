#!/bin/sh
# AmigaCLISP: GNU CLISP for 68k AmigaOS 3.x (68040, soft float).
# Cradle entry: STOVE= (stove folder) and OUT= (output folder) are set by stove_build.
# Each run carries on from where the last one stopped, so call it until it says DONE
# (a Cradle job lasts 900 s at most). State is kept in CLISP_CACHE.
#
# Stages:
#   1 fetch   the pinned upstream source (source.json), SHA-256 checked
#   2 host    a native CLISP, used to compile the Lisp sources to .fas
#             (.fas byte code is the same on every platform)
#   3 cross   lisp.run for m68k-amigaos with this port's patches
#   4 package lisp.run, the .fas files and lab/MakeImage for the lab, where
#             lispinit.mem is saved (a memory image must be made on the target)
#
# Copyright (c) 2026 AmigaChrome Team. GPL-2.0-or-later, as CLISP.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
STOVE=${STOVE:?STOVE is not set}
OUT=${OUT:-$HERE/build/out}
CACHE=${CLISP_CACHE:-$HOME/.cache/amigaclisp}
JOBS=${JOBS:-4}
BUDGET=${BUDGET:-780}          # seconds of work per run, inside Cradle's 900 s
START=$(date +%s)
NICE="nice -n 19"
mkdir -p "$CACHE" "$OUT"
log() { echo "[$(( $(date +%s) - START )) s] $*"; }
left() { echo $(( BUDGET - ($(date +%s) - START) )); }
# show a failed log: its first error with what led to it, then its end
showlog() { n=$(grep -n -m1 -E ' error:|Error [0-9]' "$1" | cut -d: -f1); [ -n "$n" ] && sed -n "$(( n > 30 ? n - 30 : 1 )),$(( n + 25 ))p" "$1"; echo "-- distinct errors in $1:"; grep -E " error:" "$1" | sed "s/^.*\/\([^/]*:[0-9]*:[0-9]*: error\)/\1/" | sort | uniq -c | sort -rn | head -60; echo "-- undefined symbols:"; grep -o "undefined reference to .*" "$1" | sort | uniq -c; echo "-- end of $1:"; tail -8 "$1"; }

COMMIT=$(sed -n 's/.*"commit": *"\([0-9a-f]*\)".*/\1/p' "$HERE/source.json")
URL=$(sed -n 's/.*"archive": *"\([^"]*\)".*/\1/p' "$HERE/source.json")
WANT=$(sed -n 's/.*"archive_sha256": *"\([0-9a-f]*\)".*/\1/p' "$HERE/source.json")
SRC=$CACHE/clisp-$COMMIT
TGZ=$CACHE/clisp-$COMMIT.tar.gz
CC_AMIGA="$STOVE/prefix/bin/m68k-amigaos-gcc"
SPECS="$HERE/toolchain/m68k-soft-m68040.specs"

# 1 fetch: SRC is the pristine source (host build), XSRC a patched copy (cross build),
# made again whenever the patch set changes.
if [ ! -f "$SRC/.unpacked" ]; then
  [ -f "$TGZ" ] || { log "fetch $URL"; curl -fsSL -o "$TGZ.part" "$URL"; mv "$TGZ.part" "$TGZ"; }
  GOT=$(sha256sum "$TGZ" | cut -d' ' -f1)
  log "source sha256 $GOT"
  if [ -n "$WANT" ] && [ "$GOT" != "$WANT" ]; then echo "SHA-256 mismatch: want $WANT"; exit 1; fi
  rm -rf "$SRC" "$SRC.tmp"; mkdir -p "$SRC.tmp"
  tar -xzf "$TGZ" -C "$SRC.tmp" --strip-components=1
  mv "$SRC.tmp" "$SRC"
  touch "$SRC/.unpacked"
fi
PSET=$(cat "$HERE"/patches/*.patch "$HERE"/compat/*.c "$HERE/toolchain/config.site" "$HERE/build-amiga.sh" 2>/dev/null | sha256sum | cut -c1-16)
XSRC=$CACHE/xsrc
CROSS=$CACHE/cross
if [ "$(cat "$XSRC/.pset" 2>/dev/null)" != "$PSET" ]; then
  log "patch set $PSET: fresh cross source"
  rm -rf "$XSRC" "$CROSS"; mkdir -p "$XSRC"
  tar -xzf "$TGZ" -C "$XSRC" --strip-components=1
  ( cd "$XSRC" && for p in "$HERE"/patches/*.patch; do [ -f "$p" ] || continue; log "patch $(basename "$p")"; patch -p1 < "$p"; done )
  echo "$PSET" > "$XSRC/.pset"
fi

# 2 host
HOST=$CACHE/host
if [ ! -f "$HOST/.done" ]; then
  if [ ! -f "$HOST/Makefile" ]; then
    log "host configure"
    rm -rf "$HOST"
    ( cd "$SRC" && $NICE ./configure --without-ffcall --without-readline \
        --without-dynamic-modules --ignore-absence-of-libsigsegv --disable-nls "$HOST" ) > "$CACHE/host-configure.log" 2>&1 \
      || { tail -40 "$CACHE/host-configure.log"; exit 1; }
  fi
  log "host make (budget $(left) s)"
  if ( cd "$HOST" && timeout "$(left)" $NICE make -j"$JOBS" ) > "$CACHE/host-make.log" 2>&1; then
    touch "$HOST/.done"; log "host CLISP built"
  else
    showlog "$CACHE/host-make.log"
    [ "$(left)" -le 5 ] && { log "RESUME: run build-amiga.sh again"; exit 0; }
    exit 1
  fi
fi

# 3 cross
# file calls that take a path go through compat/unixpath.c
WRAPS="-Wl,--wrap=open,--wrap=stat,--wrap=lstat,--wrap=access,--wrap=opendir,--wrap=chdir,--wrap=getcwd"
WRAPS="$WRAPS,--wrap=mkdir,--wrap=rmdir,--wrap=unlink,--wrap=rename,--wrap=realpath,--wrap=readlink,--wrap=abort"
if [ ! -f "$CROSS/.done" ]; then
  [ -x "$CC_AMIGA" ] || { echo "no compiler at $CC_AMIGA"; exit 1; }
  log "$("$CC_AMIGA" --version | head -1)"
  if [ ! -f "$CROSS/Makefile" ]; then
    log "cross configure"
    # compat/: the POSIX calls libnix lacks (sigprocmask, execl), the console mode,
    # and unixpath.c, the Unix view of AmigaDOS paths behind the wrapped file calls
    rm -f "$CACHE/libamigacompat.a"
    for c in amigacompat unixpath; do
      $CC_AMIGA -noixemul -m68040 -specs=$SPECS -O2 -Wall -c "$HERE/compat/$c.c" -o "$CACHE/$c.o"
      "$STOVE/prefix/bin/m68k-amigaos-ar" rcs "$CACHE/libamigacompat.a" "$CACHE/$c.o"
    done
    rm -rf "$CROSS"; mkdir -p "$CROSS"; cp "$HERE/toolchain/intparam.h" "$CROSS/intparam.h"
    ( cd "$XSRC" && CONFIG_SITE="$HERE/toolchain/config.site" \
        CC="$CC_AMIGA -noixemul -m68040 -specs=$SPECS" LDFLAGS="$WRAPS -Wl,-Map=$CACHE/lisp.ldmap" LIBS="$CACHE/libamigacompat.a -lm" \
        $NICE ./configure --host=m68k-amigaos --build="$(sh "$XSRC/src/build-aux/config.guess")" \
        --without-ffcall --without-readline --without-dynamic-modules --ignore-absence-of-libsigsegv \
        --disable-nls --disable-mmap --enable-portability "$CROSS" ) > "$CACHE/cross-configure.log" 2>&1 \
      || { tail -60 "$CACHE/cross-configure.log"; exit 1; }
  fi
  # the build's own tools (comment5, gctrigger, varbrace, ...) run on the build machine:
  # take the host build's, so make doesn't make them with the cross compiler
  for u in comment5 gctrigger varbrace ccpaux txt2c ccmp2c; do
    [ -x "$HOST/$u" ] && [ ! -e "$CROSS/.tools" ] && cp -p "$HOST/$u" "$CROSS/$u" && touch "$CROSS/$u"
  done
  touch "$CROSS/.tools"
  log "cross make lisp.run (budget $(left) s)"
  if ( cd "$CROSS" && timeout "$(left)" $NICE make -k -j"$JOBS" lisp.run ) > "$CACHE/cross-make.log" 2>&1; then
    touch "$CROSS/.done"; log "lisp.run built"
  else
    showlog "$CACHE/cross-make.log"
    [ "$(left)" -le 5 ] && { log "RESUME: run build-amiga.sh again"; exit 0; }
    exit 1
  fi
fi

# 4 package
PKG=$OUT/AmigaCLISP
rm -rf "$PKG"; mkdir -p "$PKG/full"
cp "$CROSS/lisp.run" "$PKG/lisp"
cp "$HOST"/*.fas "$PKG/full/"
cp "$HERE/lab/MakeImage" "$PKG/"; cp "$HERE/lab/makeimage.lisp" "$PKG/full/"
OBJDUMP="$STOVE/prefix/bin/m68k-amigaos-objdump"
# symbol map for crash addresses ([amiga abort] lines give an address and main's)
"$STOVE/prefix/bin/m68k-amigaos-nm" -n "$PKG/lisp" > "$OUT/lisp.map" 2>/dev/null || true
# static functions are not in the executable: give each object's .text start
# (from the link map) and spvw.o's own symbols, where the GC and startup live
grep -E '^ \.text +0x[0-9a-f]+ +0x[0-9a-f]+ ' "$CACHE/lisp.ldmap" > "$OUT/text-objects.txt" 2>/dev/null || true
"$STOVE/prefix/bin/m68k-amigaos-nm" -n "$CROSS/spvw.o" > "$OUT/spvw.nm" 2>/dev/null || true
"$STOVE/prefix/bin/m68k-amigaos-strip" -o "$PKG/lisp.stripped" "$PKG/lisp" 2>/dev/null && mv "$PKG/lisp.stripped" "$PKG/lisp" || log "strip failed: lisp left unstripped"
# FPU instructions, by function (68040 disassembly; libnix's start-up FPCR set-up is guarded)
"$OBJDUMP" -m m68k:68040 -d "$CROSS/lisp.run" | awk -F'\t' '/^[0-9a-f]+ <.*>:$/ {fn=$0} $3 ~ /^f[a-z]/ {n[fn]++; t++} END {print "FPU instructions:", t+0; for (f in n) print "  " n[f], f}' | head -40
log "lisp $(wc -c < "$PKG/lisp") bytes"
( cd "$PKG" && find . -type f | sort | xargs sha256sum ) > "$OUT/SHA256SUMS"
log "DONE"
