; TODO ask Ian about including these in maru?

(define-method ++ <undefined> (b) b)
(define-method ++ <string>    (b) (concat-string self b))
(define-method ++ <pair>      (b) (concat-list   self b))

(define-function replicate (n x)
  (if (< n 1) '() (cons x (replicate (- n 1) x))))

(define-function all? (l) (if l (foldr and 't l)))

(define-function is-a? (obj type) (= (type-of obj) type))

(define-function list-reverse (l)
  (if (pair? l)
    (concat-list (list-reverse (cdr l)) (list (car l)))))

(define-function list-at (l i)
  (if (and (pair? l) (>= i 0))
    (if (= 0 i)
      (car l)
      (list-at (cdr l) (- i 1)))))

(define-function flatten (l)
  (if (pair? l)
    (concat-list (flatten (car l)) (flatten (cdr l)))
    (if l (list l) l)))

(define-function filter (predicate l)
  (if (pair? l)
    (if (predicate (car l))
      (cons (car l) (filter predicate (cdr l)))
      (filter predicate (cdr l)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(require "print-structure.l")
(define compile-tpeg-definitions-only 1)
(require "compile-tpeg.l")

(define nile-target-lang (next-argument))
(define nile-module-name (next-argument))
(define nile-program-string
  (foldr ++ "" (map contents-of-file-named
    (cons "../prelude.nl" *arguments*))))

(define-form nile-fatal-error message
  `(and (println ,@message) (exit)))

(define-function nile-op-lookup-error (name fixity param-type)
  (println "Couldn't find operation with name: "name" fixity: "fixity" parameter type(s): ")
  (print-structure param-type 2)
  (println) (exit))

(load "nile-ast-nodes.l")
(load "nile-resolve.l")
(load "nile-type-check.l")

(println "Parsing and compiling Nile grammar...")
(map eval (parse-and-compile-grammar "nile-grammar.g"))
(peg-enable-recursion)

(cond ((= nile-target-lang "c")    (load "nile-gen-code-c.l"))
      ((= nile-target-lang "maru") (load "nile-gen-code-maru.l"))
      (else
        (nile-fatal-error "Unknown compilation target")))

(let* ((_    (println "Parsing Nile program..."))
       (ast  (parse-string <nile-parser> $start nile-program-string))
       (_    (println "Resolving references..."))
       (ast_ (map-with resolve ast (nile-resolve-env '()))))
  ;(map-with print-structure ast_ 0))
  (println "Type checking...")
  (map-with type-check ast_ '())
  (println "Generating the header file...")
  (nile-gen-code-for-header-file ast_ nile-module-name)
  (println "Generating the source file...")
  (nile-gen-code-for-source-file ast_ nile-module-name))

(println "\nDone.\n")
(set *arguments* ())
