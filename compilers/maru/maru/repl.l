(define-function array-append-all (arr . vals)
  (list-do val vals (array-append arr val)))

(define-function pval (expr)
  ;;(println "### expr")
  (eval expr))

(define-function load (name) (list-do expr (read name) (pval expr)))

(load "parser.l")
(load "peg-compile.l")
(load "peg.l")

(define *parser-stream*)

(define-form grammar-extend (name . rules)
  (println "GRAMMAR EXTEND" rules)
  (exit 0))

(define-form grammar-define (name parent fields . rules)
  (eval `(define-class ,name ,parent ,fields))
  (peg-compile-rules name rules)
  ())

(define-class <temp-grammar> <parser> ())

(define-form grammar-eval (rules expr)
  ;;(println "GRAMMAR EVAL "rules" -> "expr)
  (peg-compile-rules '<temp-grammar> rules)
  (and expr (peg-compile-rules '<temp-grammar> (list (list 'start expr))))
  ;;(println "GRAMMAR "*temp-grammar*)
  (and expr
       `(let ((_p (parser <temp-grammar> *parser-stream*)))
	  ($start _p)
	  (<parser>-result _p))))

;;(define-eval <temp-grammar> (self) ($start self *parser-stream*))

(define-function repl-parser-stream (stream prompt)
  (let ((p (parser <peg> stream))
	(s *parser-stream*)
	(v))
    (set *parser-stream* stream)
    (while (let ()
	     (and prompt (print prompt))
	     ($sexpression p))
      (set v (<parser>-result p))
      ;;(println "*** " v)
      (set v (eval v))
      ;;(println " => "v)
      )
    (set *parser-stream* s)
    v))

(define-function repl-stream (stream prompt)	(repl-parser-stream (parser-stream stream) prompt))
(define-function repl-file   (file prompt)	(repl-stream (input-stream file) prompt))
(define-function repl-path   (path prompt)	(repl-file (or (open path) (error "cannot open: "path)) prompt))

(map-with repl-path *arguments* ())

(exit 0)
