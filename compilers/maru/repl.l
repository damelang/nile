(define-function array-append-all (arr . vals)
  (list-do val vals (array-append arr val)))

(define-function pval (expr)
  ;;(println "### expr")
  (eval expr))

(load "maru/parser.l")
(load "maru/peg-compile.l")
(load "maru/peg.l")

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

(define-function concat-files (files)
  (inject (lambda (file string)
    (let ((contents (input-stream-up-to (input-stream (open file)) *end*)))
      (concat-string contents string)))
  "" files))

(define-function make-constructor-inits (fields offset)
  (let ((init `(set (oop-at self ,offset) ,(car fields))))
    (if fields (cons init (make-constructor-inits (cdr fields) (+ offset 1))))))

(define-form define-constructor (struct-name constructor-name fields)
  `(define-function ,constructor-name ,fields
     (let ((self (new ,struct-name)))
       ,@(make-constructor-inits fields 0)
       self)))

(define-function make-structure-method (spec struct-name)
  (let ((name (car spec)) (args (cadr spec)) (body (cddr spec)))
    (println `(define-method ,name ,struct-name ,args ,body))
    `(define-method ,name ,struct-name ,args ,@body)))

(define-form define-ast-node (name fields . methods)
  (let ((struct-name (concat-symbol '< (concat-symbol name '>))))
    `(let ()
        (define-structure ,struct-name ,fields)
        (define-constructor ,struct-name ,name ,fields)
        ,@(map-with make-structure-method methods struct-name))))

(let ((path (car *arguments*)))
  (set *arguments* (cdr *arguments*))
  (if path (repl-path path ())))

(exit 0)
