(require "port.l")

(define pretty-on) ;; forward

(define-selector do-pretty (self p col)
  (let* ((t (type-of self))
	 (n (array-at %type-names t)))
    (if n
	(port-write p (symbol->string n))
      (port-write p "<type="(long->string t)">"))))

(define-method do-pretty <long>		(port col)	(port-write port (symbol->string self)))
(define-method do-pretty <undefined>	(port col)	(port-write port "()"))
(define-method do-pretty <long>		(port col)	(port-write port (long->string self)))
(define-method do-pretty <double>	(port col)	(port-write port (double->string self)))
(define-method do-pretty <string>	(port col)	(port-write port "\""self"\""))
(define-method do-pretty <symbol>	(port col)	(port-write port (symbol->string self)))

(define-method do-pretty <pair>		(port col)
  (port-newline-indent port col)
  (port-write port "(")
  (set col (+ col 2))
  (while (pair? self)
    (pretty-on (car self) port col)
    (set self (cdr self)))
  (and self
       (let ()
	 (port-write port " .")
	 (pretty-on self port col)))
  (port-write port ")"))

(define-method do-pretty <array>       	(port col)
  (port-newline-indent port col)
  (port-write port "[")
  (set col (+ col 2))
  (array-do x self (pretty-on x port col))
  (port-write port "]"))

(define-method do-pretty <expr>		(port col)	(port-write port "<expr>"))
(define-method do-pretty <form>		(port col)	(port-write port "<form>"))
(define-method do-pretty <fixed>	(port col)	(port-write port "<fixed>"))
(define-method do-pretty <subr>		(port col)	(port-write port "<subr>"))
;;(define-method do-pretty <variable>	(port col)	(port-write port "<variable>"))
;;(define-method do-pretty <env>		(port col)	(port-write port "<env>"))
;;(define-method do-pretty <context>	(port col)	(port-write port "<context>"))

(define-function pretty-on (obj p col)
  (and (>= (<port>-column p) col) (port-put p ? ))
  (do-pretty obj p col))

(define-function pretty-string (obj)
  (let ((p (string-port)))
    (pretty-on obj p 0)
    (array->string (<port>-buffer p))))

(define-function pretty-print (obj)
  (println (pretty-string obj))
  obj)

;;(pretty-print (read "pretty-print.l"))
