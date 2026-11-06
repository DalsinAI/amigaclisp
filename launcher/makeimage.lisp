;;; Maxima for AmigaCLISP, first start: CLISP's own system, then Maxima
;;; (loadmaxima.lisp), saved as maxima.mem. The launcher runs it in clisp/.
(load "init.fas")
(load (concatenate 'string (ext:getenv "MAXIMA_PREFIX") "/loadmaxima.lisp"))
(ext:exit t)
