(require "parser.l")
(require "peg.l")

(define-function read-file (filename)
  (input-stream-up-to (input-stream (open filename) filename) *end*))

(define-function load-grammar (grammar-file)
  (map eval (parse-file <peg> $start grammar-file)))

(define-function invoke-parser (parser-class stream)
    (let ((pstream (parser-stream stream))
          (p (parser parser-class pstream)))
      ($start p)
      (<parser>-result p)))

(load "nile-ast.l")
(load-grammar "nile-grammar.g")

(define nile-prelude-ast (list
    (nile-typedef "Real" ())
    (nile-opdef (nile-opsig "-" (list (nile-vardecl "a" "Real"))                           "Real") () ())
    (nile-opdef (nile-opsig "<" (list (nile-vardecl "a" "Real") (nile-vardecl "b" "Real")) "Real") () ())
    (nile-processdef (nile-processsig "DupZip" (list (nile-vardecl "p1" ())
                                                     (nile-vardecl "p2" ())) ()) () () ())
    (nile-processdef (nile-processsig "Passthrough" () ()) () () ())
    (nile-processdef (nile-processsig "SortBy" (list (nile-vardecl "e" "Real")) ()) () () ())))

(define-function nile-compile-ast (ast)
    (let ((defs (concat-list nile-prelude-ast ast))
          (globals (map (lambda (def) (cons (name def) def)) defs))
          (_ (list-do def defs (resolve-refs def globals))))
        defs))

(let ((program (foldr concat-string "" (map read-file *arguments*)))
      (stream (string-stream program))
      (ast (invoke-parser <nile-parser> stream))
      (result (nile-compile-ast ast)))
    (map-with print-structure result 0))

(set *arguments* ())
