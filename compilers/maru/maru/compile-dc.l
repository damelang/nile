;;; compile-dc.l									-*- coke -*-
;;;
;;; ./eval compile-dc.l <filename>.dc

(require "parser.l")
(require "test-dc.g.l")

(while *arguments*
  (let* ((arg (next-argument))
	 (ans ()))
    (peg-disable-memoisation)
    (map dumpln (parse-file <dc> $program arg))
    (peg-enable-memoisation)
    (map dumpln (parse-file <dc> $program arg))
    (peg-enable-recursion)
    (map dumpln (parse-file <dc> $program arg))))
