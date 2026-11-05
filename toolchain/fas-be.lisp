;;; AmigaCLISP: compile the Lisp system to big-endian .fas files on the
;;; (little-endian) build machine, run by build-amiga.sh in the host CLISP.
;;; The code header of every compiled function holds 16-bit counts in the
;;; byte order of the Lisp that compiled it; the 68k reads them big-endian.
;;; Copyright (c) 2026 AmigaChrome Team. GPL-2.0-or-later, as CLISP.
;;;
;;; FAS_COMPILER  the patched compiler.lisp (patch 0012, *FAS-BIG-ENDIAN*)
;;; FAS_LIST      a file with one source path per line
;;; FAS_OUT       the directory for the .fas files (ends in /)
(setq *load-verbose* nil *compile-verbose* nil *compile-print* nil)
(let ((tmp (concatenate 'string (ext:getenv "FAS_OUT") "compiler-host.fas")))
  ;; this compiler, made for and loaded into the host, writes big-endian .fas
  (compile-file (ext:getenv "FAS_COMPILER") :output-file tmp)
  (load tmp)
  (delete-file tmp))
(setq system::*fas-big-endian* t)
(let ((failed 0))
  (with-open-file (list (ext:getenv "FAS_LIST"))
    (loop for src = (read-line list nil) while src do
      (let ((out (concatenate 'string (ext:getenv "FAS_OUT")
                              (pathname-name src) ".fas")))
        (multiple-value-bind (fas warnings-p failure-p)
            (compile-file src :output-file out)
          (declare (ignore warnings-p))
          (cond ((null fas) (format t "~&fas-be: ~A failed~%" src) (incf failed))
                (failure-p (format t "~&fas-be: ~A compiled with warnings~%" src)))))))
  (format t "~&fas-be: done, ~D failed~%" failed)
  (ext:exit (if (zerop failed) 0 1)))
