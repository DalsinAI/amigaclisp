#!/bin/sh
# Builds wxMaxima for AmigaOS 3 (68040; the FPU when there is one, through
# fpuauto) with Maxima on AmigaCLISP beside it.
#   STOVE=.../stoves/os32-gcc16-open6 OUT=out ./build-amiga.sh
# Everything third-party is fetched at the versions wxmaxima.lock gives.
# A Cradle job lasts 900 s at most: each stage keeps its work in WORK, so a
# run that stops says RESUME and the next run goes on from there; call it
# until it says DONE.
#
# Stages:
#   1 toolkit  the GFOpenWX Toolkit's SDK (once for each toolkit commit)
#   2 clisp    AmigaCLISP's own build: the host CLISP and the Amiga lisp
#   3 maxima   Maxima compiled by that host CLISP (.fas are the same on every
#              machine), installed into a staging folder, and its load order
#   4 fpuauto  libfpuauto.a
#   5 wxmaxima wxMaxima with our patches, through its CMake build
#   6 package  the wxMaxima drawer: wxMaxima, Maxima/ (launcher, lisp, CLISP's
#              and Maxima's compiled files, Maxima's packages); maxima.mem is
#              made on the Amiga at first start
# Copyright (c) 2026 AmiCradle Team. GPL-2.0-or-later, as wxMaxima and Maxima.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/wxmaxima.lock"
STOVE=${STOVE:-"$HOME/AmiCradle/stoves/os32-gcc16-open6"}
# the work tree lives outside the checkout (Cradle cleans its checkout
# before every job)
WORK="${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/gfamigawxmaxima/build}"
OUT="${OUT:-$WORK/out}"; JOBS=${JOBS:-12}
BUDGET=${BUDGET:-800}          # seconds of work per run, inside Cradle's 900 s
TC="$STOVE/prefix"
mkdir -p "$WORK/deps" "$WORK/dl" "$OUT"
t0=$(date +%s)
left() { echo $(( BUDGET - ($(date +%s) - t0) )); }
resume() { echo "[$(( $(date +%s) - t0 )) s] RESUME: run build-amiga.sh again ($1)"; exit 0; }
log() { echo "[$(( $(date +%s) - t0 )) s] $*"; }
log "stove: $("$TC/bin/m68k-amigaos-gcc" --version | head -1)"
command -v cmake >/dev/null || { echo "no cmake here"; exit 1; }
export LC_ALL=C.UTF-8 LANG=C.UTF-8

fetch() {   # name repo commit [paths...]: one commit, its tree (or those paths)
    d="$WORK/deps/$1"; repo=$2; c=$3; shift 3
    if [ "$(cat "$d/.commit" 2>/dev/null)" != "$c" ]; then
        rm -rf "${d:?}"; mkdir -p "$d"
        git -C "$d" init -q
        git -C "$d" fetch -q --depth 1 "$repo" "$c"
        if [ $# -gt 0 ]; then git -C "$d" checkout -q FETCH_HEAD -- "$@"; else git -C "$d" checkout -q FETCH_HEAD; fi
        echo "$c" > "$d/.commit"
    fi
}

# ---- 1 the toolkit's SDK, when its commit changed
fetch gfopenwxtoolkit "$WXT_REPO" "$WXT_COMMIT"
WXT="$WORK/deps/gfopenwxtoolkit"; WXB="$WORK/gfopenwx"
if [ ! -x "$WXB/out/sdk/bin/wx-config" ] || [ "$(cat "$WXB/.rev" 2>/dev/null)" != "$WXT_COMMIT" ]; then
    log "toolkit $WXT_COMMIT: building its SDK"
    if ! STOVE="$STOVE" WORK="$WXB" OUT="$WXB/out" JOBS=$JOBS timeout "$(left)" sh "$WXT/build-amiga.sh" > "$WORK/wx.log" 2>&1; then
        [ "$(left)" -le 5 ] && resume "toolkit"
        tail -40 "$WORK/wx.log"; exit 1
    fi
    echo "$WXT_COMMIT" > "$WXB/.rev"
    log "toolkit built"
fi
SDK="$WXB/out/sdk"
[ -x "$SDK/bin/wx-config" ] || { tail -40 "$WORK/wx.log"; echo "no toolkit SDK"; exit 1; }

# ---- 2 AmigaCLISP: its build-amiga.sh, with its cache in our work tree
fetch amigaclisp "$CLISP_REPO" "$CLISP_COMMIT"
CL="$WORK/deps/amigaclisp"; CLC="$WORK/clisp"; CLO="$WORK/clisp-out"
if [ "$(cat "$CLO/.commit" 2>/dev/null)" != "$CLISP_COMMIT" ]; then
    [ "$(left)" -gt 60 ] || resume "AmigaCLISP"
    log "AmigaCLISP $CLISP_COMMIT (budget $(left) s)"
    STOVE="$STOVE" OUT="$CLO" CLISP_CACHE="$CLC" BUDGET=$(( $(left) - 20 )) sh "$CL/build-amiga.sh" > "$WORK/clisp.log" 2>&1 \
        || { tail -60 "$WORK/clisp.log"; exit 1; }
    tail -3 "$WORK/clisp.log"
    grep -q 'DONE' "$WORK/clisp.log" || resume "AmigaCLISP"
    echo "$CLISP_COMMIT" > "$CLO/.commit"
fi
HOSTCLISP=$(ls -d "$CLC"/host-*/clisp 2>/dev/null | head -1)
[ -x "$HOSTCLISP" ] || { echo "no host CLISP in $CLC"; exit 1; }
[ -x "$CLO/AmigaCLISP/lisp" ] || { echo "no Amiga lisp in $CLO"; exit 1; }

# ---- 3 Maxima, compiled by the host CLISP
TB="$WORK/dl/maxima-$MAXIMA_VERSION.tar.gz"
if [ ! -f "$TB" ] || ! echo "$MAXIMA_SHA256  $TB" | sha256sum -c - >/dev/null 2>&1; then
    log "fetch $MAXIMA_URL"
    curl -fsSL -o "$TB.part" "$MAXIMA_URL"
    echo "$MAXIMA_SHA256  $TB.part" | sha256sum -c - >/dev/null || { echo "sha256 mismatch: $MAXIMA_URL"; exit 1; }
    mv "$TB.part" "$TB"
fi
MX="$WORK/maxima-$MAXIMA_VERSION"; MXS="$WORK/maxima-stage"
MSUM=$( (echo "$HOSTCLISP"; cat "$CLC"/host-*/.done "$HERE/scripts/make-loadlist.py") | sha256sum | cut -c1-16)
if [ "$(cat "$MXS/.built" 2>/dev/null)" != "$MSUM" ]; then
    [ "$(left)" -gt 200 ] || resume "Maxima"
    log "Maxima $MAXIMA_VERSION: compiling with $HOSTCLISP"
    rm -rf "$MX" "$MXS"; mkdir -p "$MX"
    tar xzf "$TB" -C "$MX" --strip-components=1
    ( cd "$MX" && FORCE_UNSAFE_CONFIGURE=1 ./configure --enable-clisp --with-clisp="$HOSTCLISP" \
        --disable-build-docs --prefix="$MXS" > "$WORK/maxima-configure.log" 2>&1 ) \
        || { tail -30 "$WORK/maxima-configure.log"; exit 1; }
    ( cd "$MX/src" && nice -n 19 make clisp > "$WORK/maxima-make.log" 2>&1 ) \
        || { grep -n -B3 -A8 '\*\*\* -' "$WORK/maxima-make.log" | head -40; tail -20 "$WORK/maxima-make.log"; exit 1; }
    ( cd "$MX" && nice -n 19 make install > "$WORK/maxima-install.log" 2>&1 ) \
        || { tail -30 "$WORK/maxima-install.log"; exit 1; }
    # Maxima's own load order (its defsystem, verbose), for the Amiga's image
    cat > "$WORK/maxima-order.lisp" <<EOF
(defparameter cl-user::*maxima-binary-directory* "$MX/src/")
(load "../lisp-utils/defsystem.lisp")
(mk:add-registry-location "../src/")
(funcall (intern (symbol-name :operate-on-system) :mk) "maxima" :load :verbose t)
EOF
    ( cd "$MX/src" && "$HOSTCLISP" -norc -q "$WORK/maxima-order.lisp" > "$WORK/maxima-order.log" 2>&1 ) \
        || { tail -20 "$WORK/maxima-order.log"; exit 1; }
    python3 -I "$HERE/scripts/make-loadlist.py" "$WORK/maxima-order.log" "$MAXIMA_VERSION" "$WORK/loadmaxima.lisp"
    echo "$MSUM" > "$MXS/.built"
    log "Maxima compiled: $(find "$MX/src/binary-clisp" -name '*.fas' | wc -l) files"
fi

# ---- 4 fpuauto: libfpuauto.a from its fpuauto.S, as its build-amiga.sh makes it
fetch fpuauto "$FPUAUTO_REPO" "$FPUAUTO_COMMIT" common/fpuauto
FA="$WORK/deps/fpuauto/common/fpuauto"; FAL="$WORK/fpuauto"
if [ "$(cat "$FAL/.commit" 2>/dev/null)" != "$FPUAUTO_COMMIT" ]; then
    rm -rf "$FAL"; mkdir -p "$FAL/obj"
    "$TC/bin/m68k-amigaos-gcc" -m68040 -DFPUAUTO_COMMON -c "$FA/fpuauto.S" -o "$FAL/obj/fa_common.o"
    for n in $(sed 's/^--wrap=//' "$FA/fpuauto.wraps"); do
        "$TC/bin/m68k-amigaos-gcc" -m68040 -DR_$n -c "$FA/fpuauto.S" -o "$FAL/obj/fa_$n.o"
    done
    "$TC/bin/m68k-amigaos-ar" rcs "$FAL/libfpuauto.a" "$FAL"/obj/fa_*.o
    echo "$FPUAUTO_COMMIT" > "$FAL/.commit"
fi

# ---- the launcher
SPECS="$HERE/scripts/m68k-soft-m68040.specs"
"$TC/bin/m68k-amigaos-gcc" -noixemul -m68040 -specs="$SPECS" -O2 -Wall -o "$OUT/maxima" "$HERE/launcher/maxima.c"
"$TC/bin/m68k-amigaos-strip" "$OUT/maxima"

# ---- 5 wxMaxima, at its commit, with our patches (again when they change)
SRC="$WORK/wxmaxima"; B="$WORK/wxbuild"
PSUM=$(cat "$HERE"/patches/*.patch | sha256sum | cut -c1-16)
if [ "$(cat "$SRC/.patched" 2>/dev/null)" != "$WXMAXIMA_COMMIT-$PSUM" ]; then
    rm -rf "$SRC" "$B"; mkdir -p "$SRC"
    git -C "$SRC" init -q
    git -C "$SRC" fetch -q --depth 1 "$WXMAXIMA_GIT" "$WXMAXIMA_COMMIT"
    git -C "$SRC" checkout -q FETCH_HEAD
    [ "$(git -C "$SRC" rev-parse HEAD)" = "$WXMAXIMA_COMMIT" ] || { echo "wxMaxima commit mismatch"; exit 1; }
    for p in "$HERE"/patches/*.patch; do
        patch -s -d "$SRC" -p1 < "$p" || { echo "patch failed: $p"; exit 1; }
    done
    echo "$WXMAXIMA_COMMIT-$PSUM" > "$SRC/.patched"
fi
CSUM=$( (cat "$0" "$HERE/cmake/toolchain-m68k-amigaos.cmake" "$HERE"/cmake/Platform/*.cmake; echo "$WXT_COMMIT") | sha256sum | cut -c1-16)
if [ "$(cat "$B/.configured" 2>/dev/null)" != "$CSUM" ]; then
    rm -rf "$B"; mkdir -p "$B"
    (cd "$B" && cmake "$SRC" -G "Unix Makefiles" \
        -DCMAKE_TOOLCHAIN_FILE="$HERE/cmake/toolchain-m68k-amigaos.cmake" \
        -DAMIGA_TOOLCHAIN="$TC" -DAMIGA_SPECS="$SPECS" \
        -DAMIGA_FPUSPECS="$FA/fpuauto.specs" -DAMIGA_FPULIB="$FAL" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/wxMaxima \
        -DwxWidgets_CONFIG_EXECUTABLE="$SDK/bin/wx-config" \
        -DWXM_DISABLE_WEBVIEW=ON -DWXM_DISABLE_QA=ON -DWXM_ENABLE_PRECOMPILED_HEADERS=OFF \
        -DWXM_UNIT_TESTS=OFF -DWXM_INTERPROCEDURAL_OPTIMIZATION=OFF \
        -DCMAKE_THREAD_LIBS_INIT=-lpthread -DCMAKE_HAVE_PTHREAD_CREATE=1 -DCMAKE_HAVE_THREADS_LIBRARY=1 \
        -DCMAKE_USE_PTHREADS_INIT=1 -DThreads_FOUND=TRUE > cmake.log 2>&1) \
        || { grep -B2 -A12 'CMake Error' "$B/cmake.log" | head -80; tail -20 "$B/cmake.log"; exit 1; }
    echo "$CSUM" > "$B/.configured"
fi
[ "$(left)" -gt 30 ] || resume "wxMaxima"
log "wxMaxima: make (budget $(left) s)"
set +e
(cd "$B" && timeout "$(left)" nice -n 19 make -k -j"$JOBS" wxmaxima > make.log 2>&1)
rc=$?
set -e
if [ ! -f "$B/src/wxmaxima" ] || [ $rc -ne 0 ]; then
    [ "$(left)" -le 5 ] && resume "wxMaxima, $(find "$B" -name '*.o' | wc -l) objects so far"
    grep -E 'error|Error|undefined reference' "$B/make.log" | cut -c1-300 | sort | uniq -c | sort -rn | head -50
    tail -15 "$B/make.log" | cut -c1-300
    exit 1
fi
cp "$B/src/wxmaxima" "$OUT/wxMaxima.debug"
"$TC/bin/m68k-amigaos-strip" -o "$OUT/wxMaxima" "$B/src/wxmaxima"
ls -l "$OUT/wxMaxima"
echo "fpuauto: $("$TC/bin/m68k-amigaos-objdump" -d "$OUT/wxMaxima" | grep -c 'jsr.*<___wrap_' || true) wrapped calls in wxMaxima"

# ---- 6 the package: the wxMaxima drawer
P="$WORK/pkg/wxMaxima"; M="$P/Maxima"
rm -rf "$WORK/pkg"; mkdir -p "$M/clisp" "$M/share/maxima" "$M/info"
cp "$OUT/wxMaxima" "$P/"
cp "$OUT/maxima" "$CLO/AmigaCLISP/lisp" "$M/"
cp "$CLO"/AmigaCLISP/full/*.fas "$M/clisp/"
(cd "$MX/src" && find binary-clisp -name "*.fas" -exec cp --parents {} "$M/" \;)
cp -R "$MXS/share/maxima/$MAXIMA_VERSION" "$M/share/maxima/"
cp "$MX"/doc/info/maxima-index.lisp "$MX"/doc/info/maxima-index-html.lisp "$MX"/doc/info/maxima.info* "$M/info/" 2>/dev/null || :
cp "$WORK/loadmaxima.lisp" "$HERE/launcher/makeimage.lisp" "$M/"
cp "$HERE/README.md" "$P/ReadMe" 2>/dev/null || :
cp "$SRC/COPYING" "$P/COPYING"
( cd "$WORK/pkg" && find . -type f | sort | xargs sha256sum ) > "$OUT/SHA256SUMS"
du -sh "$P" | sed 's/^/package: /'
# the package as one tar.gz, and in parts under 256 KiB (lab_get takes one
# file up to 256 KiB): cat parts/* | tar -xz
tar -C "$WORK/pkg" -czf "$OUT/wxMaxima-$WXMAXIMA_VERSION.tgz" wxMaxima
rm -rf "$OUT/parts"; mkdir -p "$OUT/parts"
split -b 200k -d -a 3 "$OUT/wxMaxima-$WXMAXIMA_VERSION.tgz" "$OUT/parts/wxMaxima.tgz."
ls -l "$OUT/wxMaxima-$WXMAXIMA_VERSION.tgz"
log "DONE"
