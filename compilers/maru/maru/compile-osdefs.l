;;; compile-osdefs.l									-*- coke -*-
;;;
;;; ./eval compile-osdefs.l <filename>.osdefs

(require "text-parser.l")

(define *headers*  (array))
(define *prologue* (array))
(define *program*  (array))

(define-function do-header	(x)	(println "#include <"x">"))
(define-function do-default	(i e)	(println "#ifndef "i) (println "#define "i" "e) (println "#endif"))
(define-function do-type	(i t)	(println "typedef "t" "i";"))
(define-function do-integer	(x)	(println "  defint("x");"))
(define-function do-float	(x)	(println "  defflt("x");"))
(define-function do-string	(x)	(println "  defstr("x");"))
(define-function do-size	(i)	(println "  defsao("i");"))

(define-function def-headers  (i)	(list-do x i (array-append *headers*  (list do-header  x  ))))
(define-function def-alt      (i e)		     (array-append *prologue* (list do-default i e)) )
(define-function def-type     (i t)		     (array-append *prologue* (list do-type    i t)) )
(define-function def-integers (i)	(list-do x i (array-append *program*  (list do-integer x  ))))
(define-function def-floats   (i)	(list-do x i (array-append *program*  (list do-float   x  ))))
(define-function def-strings  (i)	(list-do x i (array-append *program*  (list do-string  x  ))))
(define-function def-sizes    (i)	(list-do x i (array-append *program*  (list do-size    x  ))))

(require "osdefs.g.l")

(while *arguments*
  (let* ((file    (next-argument))
	 (source  (contents-of-file-named file))
	 (parser  (text-parser-for-on <osdefs> source))
	 (program (if ($file parser) (<osdefs>-result parser) (error "syntax error"))))))

(define-function process (arr)
  (array-do elt arr
    (let* ((emitter (car  elt))
	   (item    (cadr elt)))
      (if (= (car item) 'qualified)
	  (let ((qualifier (cadr  item))
		(value     (caddr item)))
	    (if (= qualifier 'defined?) (println "#ifdef "value) (println "#if "qualifier))
	    (emitter value)
	    (println "#endif"))
	(apply emitter (cdr elt))))))

(println "#include <stdio.h>")

(process *headers*)

(println "#define STR(X)		#X")
(println "#define defint(X)	printf(\"(define-constant %s %ld)\\n\", #X, (long)X)")
(println "#define defflt(X)	printf(\"(define-constant %s %12e)\\n\", #X, (double)X)")
(println "#define defstr(X)	printf(\"(define-constant %s \\\"%s\\\")\\n\", #X, STR(X))")
(println "#define defsize(X)	printf(\"(define-constant sizeof-%s %ld)\\n\", #X, (long)sizeof(X))")
(println "#define defalign(X)	{ struct { char _;  X x; } x;  printf(\"(define-constant alignof-%s %ld)\\n\", #X, (long)&x.x - (long)&x); }")
(println "#define defsao(X)	defsize(X);  defalign(X)")

(process *prologue*)
(println "int main() {")
(process *program*)
(println "  return 0;")
(println "}")
