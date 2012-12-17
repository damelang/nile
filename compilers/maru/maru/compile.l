;;; literal

(define-structure <literal> (location value))

(define-method do-print <literal> ()
  (print "<literal ")
  (dump  (<literal>-value    self))
  (print " ")
  (print (<literal>-location self))
  (print ">"))

(define-function literal (value)
  (let ((self (new <literal>)))
    (set (<literal>-value self) value)
    self))

;;; variable

(define-structure <variable> (location name value next))

(define-method do-print <variable> ()
  (print "<variable ")
  (print (<variable>-name self))
  (print " ")
  (print (<variable>-location self))
  (print ">"))

(define-function variable (name value next)
  (let ((self (new <variable>)))
    (set (<variable>-name	self) name)
    (set (<variable>-value	self) value)
    (set (<variable>-next	self) next)
    self))

;;; operator

(define-structure <operator> (operation arguments))

(define-method do-print <operator> ()
  (print "{"(<operator>-operation self))
  (print " "(<operator>-arguments self))
  (print "}"))

(define-function operator (operation arguments)
  (let ((self (new <operator>)))
    (set (<operator>-operation	self) operation)
    (set (<operator>-arguments	self) arguments)
    self))

;;; compiler

(define-structure <compiler> (scope level program))

(define-method do-print <compiler> ()
  (print "<compiler "(<compiler>-level self)" "(<compiler>-scope self)">"))

(define-function compiler (scope level)
  (let ((self (new <compiler>)))
    (set (<compiler>-scope	self) scope)
    (set (<compiler>-level	self) level)
    self))

(define-function define-variable (compiler name value)
  (let ((variable (variable name value (<compiler>-scope compiler))))
    (set (<compiler>-scope compiler) variable)))

;;; encoding

(define-selector encode-expr)

(define-function encode-define (expr compiler)
  (let ((name (cadr expr))
	(init (caddr expr)))
    (define-variable compiler name ())
    (operator 'set (list (encode-expr name compiler) (encode-expr init compiler)))))

(define-method encode-expr <symbol> (compiler)	(variable self 'VALUE 'NEXT))

(define-method encode-expr <long>   (compiler)	(literal self))
(define-method encode-expr <string> (compiler)	(literal self))

(define-method encode-expr <pair>   (compiler)
  (let ((head (car self))
	(args (cdr self)))
    (cond
     ((= head 'define)	(encode-define self compiler))
     (else
       (operator (encode-expr (car self) compiler)
		 (map-with encode-expr (cdr self) compiler))))))

(define-function encode-top-level-expr (expr compiler)
  (let ((e (encode-expr expr compiler)))
    (if e
	(set (<compiler>-program compiler) (cons e (<compiler>-program compiler))))))

;;; compiling

(define-selector compile-node)

(define-function compile-set (compiler)
  xxx

(define-method compile-node <operator> (compiler)
  (let ((op (<operator>-operation self)))
    (cond
     ((= op 'set)	(compile-set self compiler))
     (else
       (error "cannot compile-node operator " self)))))

(define-function compile (source)
  (let ((c (compiler 0 ())))
    (println source)
    (println "=======>")
    (map-with encode-top-level-expr source c)
    (set (<compiler>-program c) (reverse (<compiler>-program c)))
    (println (<compiler>-program c))
    (map-with compile-node (<compiler>-program c) c)
    ))

(compile '((define a (+ 3 4))))

(exit 0)

(compile '
 ((define printf (extern int "printf" (char *) ...))
  (printf "Hello, world\n")))

(exit 0)

(define *top-level* (cons () ()))

(set (car *top-level* (cons '*top-level* *top-level*)))

(define-structure <extern> (type name args))

(define-method do-print <extern> ()
  (print "<extern="(<extern>-name self)">"))

(define-function extern (type name args)
  (let ((self (new <extern>)))
    (set (<extern>-type self) type)
    (set (<extern>-name self) name)
    (set (<extern>-args self) args)
    self))

(define-function define-in (env name value)
  (set-cdr env (cons (cons name value) (cdr env)))
  value)

(define-in *top-level* 'extern
  (form (lambda (expr env)
	  (let ((type ( cadr expr))
		(name (caddr expr))
		(args (cdddr expr)))
	    (define-in *top-level* name (extern type name args)))
	  ())))
  
(define-selector compile-expr (expr env)	(error "cannot compile-expr: " expr))

(define-function compile-args (args env)
  (if (pair? args)
      (let ()
	(compile-args (cdr args) env)
	(compile-expr (car args) env))))

(define-method compile-expr <extern> (env)	(emit 'define self))
(define-method compile-expr <symbol> (env)	(emit 'lookup self))
(define-method compile-expr <undefined> (env)	)
(define-method compile-expr <long> (env)	(emit 'load self))
(define-method compile-expr <string> (env)	(emit 'load self))

(define-function emit args (print "EMIT ") (dumpln args))

(define-method compile-expr <pair> (env)
  (let ((head  (car self))
	(value ()))
    (if (and (symbol? head) (form? (set value (cdr (assq head env)))))
	(compile-expr (apply (<form>-function value) (cons self (cons env ())) env) env)
      (let ((args (cdr self)))
	(compile-args args env)
	(compile-expr head env)
	(emit 'apply (list-length args))))))

(define-function compile (program)
  (while program
    (let ((expr (car program)))
      (print "COMPILE ")
      (dumpln expr)
      (compile-expr expr *top-level*)
      )
    (set program (cdr program))))

(compile '(
  (extern int printf (* char) ...)
  (define nfibs
    (lambda (n)
      (if (< n 2)
	  1
	(+ 1
	   (+ (nfibs (- n 1))
	      (nfibs (- n 2)))))))
  (printf "%d\n" (nfibs 5))))

;; (define-structure <RI32> (generator))

;; (define-method do-print <RI32> ()
;;   (print (<RI32>-generator self) ":RI32"))

;; (define-function RI32 (gen)
;;   (let ((self (new <RI32>)))
;;     (set (<RI32>-generator self) gen)
;;     self))



;; (define-structure <ADDI32> (a b))

;; (define-method do-print <ADDI32> ()
;;   (print "ADDI32("(<ADDI32>-a self)","(<ADDI32>-b self)")"))

;; (define-function ADDI32 (a b)
;;   (let ((self (new <ADDI32>)))
;;     (set (<ADDI32>-a self) a)
;;     (set (<ADDI32>-b self) b)
;;     self))



;; (define-generic add)

;; (define-multimethod add ((a <RI32>) (b <RI32>))		(RI32 (ADDI32 a b)))

;; (define %eax (RI32 "%eax"))
;; (define %ebx (RI32 "%ebx"))

;; (println (add %eax %ebx))
