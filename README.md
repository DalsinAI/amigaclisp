# AmigaCLISP

A port of GNU CLISP (ANSI Common Lisp) to 68k AmigaOS 3.x: 68040, one binary that uses the FPU when there is one and soft float otherwise,
built with OpenAmigaGCC and OpenNDK.

Status: 0.1 rc2 (6 Nov 2026). The Lisp prompt, scripts, the compiler and CLOS
run on a 68040; see lab/ReadMe for installing. -O2 is still to come.

CLISP is GPL-2.0-or-later; this port's patches and build scripts are under the
same licence.

Designed, tested and delivered by The AmiCradle Team.

## Release archive and Installer

`package/build-amiga.sh` (Cradle's stove_build, target `package`; run it again
until the top build says DONE) makes `AmigaCLISP-VERSION.lha`: the AmigaCLISP
drawer and its icon, and beside them `Install-AmigaCLISP`, the Amiga Installer
script (made by amicradle's `scripts/ports/port_installer.py` from
`package/installer.json`). The Installer copies the drawer where you choose;
then run `Execute Install` once in it, as lab/ReadMe says, to assign CLISP:
and save the memory image. `package/soft-float.sh` checks that lisp's objects
have no FPU instruction and that fpuauto is linked in. Host tests:
`python3 package/tests/test_installer.py`.
