;;; compile-grammar.l									-*- coke -*-
;;;
;;; ./eval compile-grammar.l <filename>.g ... | tee <filename>.l

(require "parser.l")
(require "peg.l")

(while *arguments*
  (let ((g (parse-file <peg> $start (next-argument))))
    (map dumpln g)))
