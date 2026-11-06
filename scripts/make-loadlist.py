#!/usr/bin/env python3
# Copyright (c) 2026 AmiCradle Team. GPL-2.0-or-later, as Maxima.
"""Maxima's load order for the Amiga's image: what Maxima's own build
(defsystem's :load of "maxima", run verbose on the build host) loaded, in
that order, as loadmaxima.lisp. The Amiga loads the same files from
MAXIMA_PREFIX (binary-clisp/ for compiled files, share/maxima/V/src/ for
the few sources the build loads as they are) and saves maxima.mem there,
as Maxima's Makefile does.
    make-loadlist.py LOAD_LOG VERSION OUT"""
import re, sys
log, version, out = sys.argv[1:4]
items = []
# CLISP wraps a long line: a quoted path can go on the next ";" line
text = re.sub(r'\n;\s+(?=")', ' ', open(log, encoding="utf-8", errors="replace").read())
for line in text.split("\n"):
    m = re.search(r'Loading binary file "binary-clisp/(.+)\.fas"', line)
    if m:
        items.append(("bin", m.group(1)))
        continue
    m = re.search(r'Loading source (?:private-)?file "(?:.*/)?([^/"]+\.lisp)"', line)
    if m:
        items.append(("src", m.group(1)))
if not any(k == "bin" for k, _ in items):
    sys.exit("make-loadlist: no compiled files in " + log)
with open(out, "w") as f:
    f.write(";;; Maxima %s for AmigaCLISP: load Maxima, save MAXIMA_PREFIX/maxima.mem.\n" % version)
    f.write(";;; Made by make-loadlist.py from Maxima's own load order (%d files).\n" % len(items))
    f.write("(in-package :cl-user)\n")
    f.write("(setf *read-default-float-format* 'double-float)\n")
    f.write("(defvar *amiga-maxima-prefix* (ext:getenv \"MAXIMA_PREFIX\"))\n")
    f.write("(defun amiga-maxima-file (kind name)\n"
            "  (concatenate 'string *amiga-maxima-prefix*\n"
            "               (if (eq kind :bin) \"/binary-clisp/\" \"/share/maxima/%s/src/\")\n"
            "               name (if (eq kind :bin) \".fas\" \"\")))\n" % version)
    f.write("(dolist (f '(\n")
    for k, n in items:
        f.write("  (:%s \"%s\")\n" % (k, n))
    f.write("  ))\n  (load (amiga-maxima-file (first f) (second f)) :verbose nil))\n")
    f.write("(ext:saveinitmem (concatenate 'string *amiga-maxima-prefix* \"/maxima.mem\")\n"
            "                 :init-function (function cl-user::run))\n")
    f.write("(ext:exit)\n")
print("make-loadlist: %d files" % len(items))
