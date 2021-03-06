(println "TEST")

(define *root* *globals*)

(define ns1 (environment *globals*))
(define ns2 (environment *globals*))

(println *globals*)

(set *globals* ns1)

(println *globals*)

(define a 41)
(define b 42)
(define c 43)

(set *globals* ns2)

(define a 101)
(define b 102)
(define c 103)

(set *globals* ns1)

(println a b c)

(set *globals* ns2)

(println a b c)

(set *globals* *root*)

(println (<env>-bindings ns1))
(println (<env>-bindings ns2))

(define-function fibs (n)
  (if (< n 2) 1
    (+ 1 (+ (fibs (- n 1)) (fibs (- n 2))))))

;(println (fibs 5))

(let ((c))
  (while (< 0 (set c (getc)))
    (print (format "%c" c))))This is a here-document.
It shows how to embed arbitrary test in a file.
 (println "done")

(define-structure <object> ())

;;(println <object> " " (array-at %type-names <object>))
;;(println (array-at %structure-derivatives <object>))

(define-class <point> <object> (x y))

;;(println <point> " " (array-at %type-names <point>))
;;(println (array-at %structure-sizes <point>))
;;(println (array-at %structure-fields <point>))
;;(println (array-at %structure-bases <point>))
;;(println (array-at %structure-derivatives <object>))

(define-class <point3> <point> (z))

;;(println <point3> " " (array-at %type-names <point3>))
;;(println (array-at %structure-sizes <point3>))
;;(println (array-at %structure-fields <point3>))
;;(println (array-at %structure-bases <point3>))
;;(println (array-at %structure-derivatives <point>))
;;(println (array-at %structure-derivatives <object>))

(define-class <point3b> <point> (z))

;;(println <point3b> " " (array-at %type-names <point3b>))
;;(println (array-at %structure-sizes <point3b>))
;;(println (array-at %structure-fields <point3b>))
;;(println (array-at %structure-bases <point3b>))
;;(println (array-at %structure-derivatives <point>))
;;(println (array-at %structure-derivatives <object>))

(define-selector man)

(define-method man <point> ()
  (+ (* (<point>-x self) (<point>-x self))
     (* (<point>-y self) (<point>-y self))))

(let ((p2 (new <point>))
      (p3 (new <point3>)))
  (set (<point>-x  p2) 3)
  (set (<point>-y  p2) 4)
  (set (<point3>-x p3) 5)
  (set (<point3>-y p3) 12)
  (set (<point3>-z p3) 13)
  (println (man p2))
  (println (man p3)))

(define-class <magnitude> <object> ())
(define-class <integer> <magnitude> ())

(define-selector <integer>-value)
(define-selector <integer>-<)
(define-selector <integer>-+)
(define-selector <integer>--)

(define-class <smallinteger> <integer> (value))

(define-function smallinteger (n)
  (let ((self (new <smallinteger>)))
    (set (<smallinteger>-value self) n)
    self))

(define <integer>-1 (smallinteger 1))
(define <integer>-2 (smallinteger 2))

(define-method <integer>-value <smallinteger> ()	(<smallinteger>-value self))
(define-method <integer>-<     <smallinteger> (other)	(< (<smallinteger>-value self) (<smallinteger>-value other)))
(define-method <integer>-+     <smallinteger> (other)	(smallinteger (+ (<smallinteger>-value self) (<smallinteger>-value other))))
(define-method <integer>--     <smallinteger> (other)	(smallinteger (- (<smallinteger>-value self) (<smallinteger>-value other))))

(define-selector mfibs)

(define-method mfibs <integer> ()
  (if (<integer>-< self <integer>-2)
      <integer>-1
    (<integer>-+ <integer>-1
		 (<integer>-+ (mfibs (<integer>-- self <integer>-1))
			      (mfibs (<integer>-- self <integer>-2))))))

(println (<integer>-value (mfibs (smallinteger 25))))
