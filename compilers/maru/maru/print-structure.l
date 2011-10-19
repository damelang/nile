(define-function list-index-of (key list)
  (let ((i 0))
    (while (and list (!= key (car list)))
      (incr i)
      (set list (cdr list)))
    (and list i)))

(define-function indent (n . objs)
  (for (i 0 n) (print "  "))
  (and objs (apply print objs)))
      
(define print-structure-fields) ;; forward

(define-selector print-structure (self n)	;; <--- this is the entry point, n = indentation level
  (let ((t (type-of self)))
    (if (<= t <context>)
	(dumpln self)
      (print-structure-fields self (+ n 1) (array-at %structure-fields t)))))

(define-function print-structure-fields (self n fields)
  (let ((t (type-of self))
	(m (array-at %structure-fields t)))
    (println (array-at %type-names t) " {")
    (list-do field fields
      (indent n field" = ")
      (print-structure (oop-at self (list-index-of field m)) n))
    (indent (- n 1) "}\n")))

(define-method print-structure <pair> (n)
  (print "( ")
  (print-structure self.head (+ n 1))
  (list-do elt self.tail
    (indent (+ n 1))
    (print-structure elt (+ n 1)))
  (indent n ")\n"))
