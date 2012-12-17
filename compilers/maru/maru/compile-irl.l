;;; compile-irl.l									-*- coke -*-
;;;
;;; ./eval compile-irl.l <filename>.irl

(require "ir.k")
(require "text-parser.l")

(set text-parser-invoke-rule text-parser-invoke-rule-with-recursion)

(define-function param-list-types (pl)	(map car pl))
(define-function param-list-decls (pl)	(map (lambda (p) `(ir-arg ',(cadr p) ,(car p))) pl))

(require "irl.g.l")

(while *arguments*
  (let* ((file    (next-argument))
	 (source  (contents-of-file-named file))
	 (parser  (text-parser-for-on <irl> source))
	 (program (if ($program parser) (<irl>-result parser) (error "syntax error"))))
    (print "/*")
    (map (lambda (x) (print "\n   ")  (println x)) program)
    (println "*/")
    (eval
     `(let ((ir (ir-new <ir> ())))
	,@program
	(ir-gen-main ir)))))
