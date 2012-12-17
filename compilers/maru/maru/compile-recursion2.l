;;; compile-recursion2.l									-*- coke -*-
;;;
;;; ./eval compile-recursion2.l <filename>.txt

(require "parser.l")
(require "test-recursion2.g.l")

(peg-enable-recursion)

(while *arguments*
  (let ((g (parse-file <r2> $program (next-argument))))
    (dumpln g)
    (println)
    (list-do elt g (dumpln elt))))
