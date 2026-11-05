;; AmigaCLISP: load the compiled system and save the memory image (run by MakeImage).
(and (load "init.fas") (ext::saveinitmem) (ext::exit))
(ext::exit t)
