#!/bin/sh
# Probe: report the Cradle build environment for the CLISP port.
echo "pwd=$(pwd) STOVE=$STOVE OUT=$OUT HOME=$HOME user=$(id -un) host=$(hostname)"
nproc; uname -a; df -h . "$OUT" 2>/dev/null | tail -2
ls "$STOVE" "$STOVE/prefix/bin" 2>&1 | head -40
"$STOVE/prefix/bin/m68k-amigaos-gcc" --version 2>&1 | head -1
command -v gcc make autoconf clisp sbcl python3 curl git xz
gcc --version 2>&1 | head -1
ls -d "$STOVE"/prefix/m68k-amigaos/ndk-include 2>&1
ls "$HOME"/AmiCradle-dev/cradle-builds 2>&1 | head
timeout 20 git ls-remote https://gitlab.com/gnu-clisp/clisp.git HEAD 2>&1 | head -2
timeout 20 curl -sSI https://gitlab.com/gnu-clisp/clisp/-/archive/db78dbd2cf08910596aeda694a23773346e703b0/clisp.tar.gz 2>&1 | head -1
ls /run/media/da1ek/DevDrive 2>&1 | head
mkdir -p "$OUT" && echo probe > "$OUT/probe.txt"
