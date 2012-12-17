;;; SYNTAX

;; Special forms are evaluated while constructing the compilation environment.  They are ignored by
;; the compiler.

(define-form assert expr
  ;; The LET* here places each definition in the scope of its successors.  It does not support any
  ;; other extended behaviours since the synax would be incompatible with that of type annotation.
  (let* ((source (<pair>-source expr))
	 (file   (car source))
	 (line   (cdr source)))
    `(unless ,(car expr)
       (printf "assertion failed at %s:%d\n" ,(or file "?") ,(or line 0))
       (exit 1))))

;; The syntax is that of Lisp s-expressions except that
;; 
;; - where a variable name appears in a definition, it can be a list of: (variable-name type-specifier...)
;; - function definitions (either define-function or lambda) have a return type immediately before the formal parameter list
;; - function defintions must specify return type and all argument types
;; 
;; Type expressions use a postfix notation where each successive element modifies the type being constructed
;;
;; - a primitive type name specifies a basic type
;; - the symbol 'struct' precedes a structure type name; the two symbols together name a basic type
;; - a * modifies the current type to be a pointer to the current type
;; - a sequence of type names specifies a function type: return-type argument-types...
;; - the pseudo-type name '...' can appear at the end of a sequence of argument types to denote varargs
;; - '...' can be the first and only argument type, meaning nothing is known about the argument types
;; - type expressions can be parenthesized

;;; DECLARATIONS

;; External symbols are referred to by the special form (extern symbol-name)
;; 
;; Given all of the above, the following declares the global variable 'printf' to be
;; a pointer to a function, of pointer-to-character and unknown varargs, returning int
;; and then initialises it with the value of the external symbol 'printf'.
;; 
;;        name    type expression
;;       <----> <----------------->
;;          variable declaration      initialiser
;;       <------------------------> <------------->
;;              +---function---+ +-- modifies the function type to be a pointer-to-function type
;;              |---  type  ---| |
;;              v              v v
(define (printf (int char * ...) *) (extern printf))
;;                ^   ^   ^  ^
;;                |   |   |  |
;;  return type --+   |   |  +------ second arg type: zero or more varargs
;;  first arg type ---+   + -------- modifies first arg to be pointer-to-char

(define (exit (void int) *) (extern exit))

;;; FUNCTIONS

;; A standalone program begins executing at the function main.  This function should expect two
;; arguments (the argument count and a pointer to an array of strings containing the arguments) and
;; return an int.  The return type in a function definition precedes the formal parameter list.
;; This applies to lambda expressions as well as define-function (which is a form that expands to a
;; lambda expression).

(define-function main int ((argc int) (argv char * *))
  (printf "%d\n" (printf "Hello, world\n"))
  (test-conditionals)
  (test-calls)
  (test-bytes)
  (test-words)
  (test-ints)
  (test-structs)
  (test-pointers)
  (test-forms)
  ;; There is no implicit return of the value of the final expression in a function.  Returning a
  ;; value is always explicit.
  (return 0)
  )

;; The main function must also be exported so that the linker can find it.

(export main)

;; Exporting a variable has two effects:
;; 
;; - the variable becomes globally visible during linking, and
;; - the usual name mangling (to prevent clashes with standard namespaces) will be disabled for it.

;; An empty parameter list means a function takes exactly zero arguments.

(define-function test-conditionals void ()
  (let ((x 0)
        (i 0))
    ;; WHILE loops are as in Lisp, but they return no value.
    (while (< i 10)
      (printf "%d %d  " i x)
      (set x (+ x (set i (+ i 1)))))
    (assert (= x 55))
    (printf "\n")
    ;; IF statements are as in Lisp, and can optionally return a value.
    (set x 0)
    (set i 0)
    (while (< (incr i) 10)
      ;; If no value is returned then the FALSE branch can be omitted.
      (if (< i 5)
	  (let ()
	    (printf "%i<5 " i)
	    (incr x i)))
      ;; If a value is returned then both TRUE and FALSE branches must be supplied and their types
      ;; must be the same.
      (printf "%s " (if (= 0 (% i 2)) "even" "odd")))
    (printf "\n")
    (assert (= x 10))
    ))

(define-form with-variable-values (inits . body)
  `(let (((i8  int8)	,(or (nth inits 1) 8))
	 ((i16 int16)	,(or (nth inits 2) 16))
	 ((i32 int32)	,(or (nth inits 3) 32))
	 ((i64 int64)	,(or (nth inits 4) 64))
	 ((f32 float32)	,(or (nth inits 5) 3.2))
	 ((f64 float64)	,(or (nth inits 6) 6.4))
	 )
     ,@body))

(define-form with-variables body	`(with-variable-values () ,@body))

(define-function test-calls-1 void ((i8 int8) (i16 int16) (i32 int32) (i64 int64) (f32 float32) (f64 float64))
  ;; varargs MUST be cast explicitly to match the ABI of the reciving function
  (printf "%d %d %d %lld %f %f \n" (cast i8 int) (cast i16 int) i32 i64 (cast f32 double) f64))

(define-function test-calls void ()
  ;; The function call ABI treats the call frame exactly like a structure, with the same alignment
  ;; rules.  Arguments passed in a position corresponding to a declared formal argument type must
  ;; match that type exactly.  All arguments are passed as-is, without any type promotion at all.
  (with-variable-values (1 2 3 4 5.6 7.8)
    ;; In the following internal call, the argument portion of the stack frame occupies 28 bytes.
    (test-calls-1 i8 i16 i32 i64 f32 f64)
    ;; For external functions, arguments *must* be cast explicitly to match the ABI of the reciving
    ;; function.  In the case of C this means integers smaller than INT must be cast to INT, and
    ;; floats passed through varargs must be cast to DOUBLE.
    ;; 
    ;; In the following call the arguments occupy 36 bytes.  Had the arguments been passed to an
    ;; external C function with a declared prototype, the arguments would still have to be cast as
    ;; shown with the exception of the f32 argument which is only promoted to double when passed
    ;; through varargs.
    (printf "%d %d %d %lld %f %f \n" (cast i8 int) (cast i16 int) i32 i64 (cast f32 double) f64)
    ;; This arrangement provides more efficient use of resources when calling internal functions at
    ;; the cost of placing responsibility on the client to know and enforce the ABI constraints of
    ;; all external functions that are called.  (In the case of C this means no integer argument
    ;; smaller than INT and FLOAT promoted to DOUBLE when passed through varargs.)
    ))

(define-function printi int ((i int))
  (printf "%d\n" i)
  (return i))

(define-function test-bytes void ()
  ;; No integer promotion is performed on bytes when manipulation them.  They are considered signed
  ;; when cast to another type.  To perform an unsigned cast, AND the signed cast with a mask.
  (let (((a int8) 10)	((b int8) 20)	((c int8) 40)	((d int8) 80)	((e int8) 160))
    ;;        signed cast                                 unsigned cast
    (assert (=  -96 (cast      e  int)))    (assert (= 160 (& 255 (cast      e  int))))
    (assert (=  -16 (cast (+ d e) int)))    (assert (= 240 (& 255 (cast (+ d e) int))))
    (assert (=   64 (cast (+ e e) int)))
    (assert (=  64 (& 255 (cast (+ e e) int))))
    (assert (=  -10 (cast (- a b) int)))    (assert (= 246 (& 255 (cast (- a b) int))))
    (assert (=  116 (cast (- b e) int)))    (assert (= 116 (& 255 (cast (- b e) int))))
    (assert (=  -56 (cast (* a b) int)))    (assert (= 200 (& 255 (cast (* a b) int))))
    (assert (= -112 (cast (* a c) int)))    (assert (= 144 (& 255 (cast (* a c) int))))
    (assert (=   32 (cast (* a d) int)))    (assert (=  32 (& 255 (cast (* a d) int))))
    (assert (=    2 (cast (/ b a) int)))
    (assert (=    2 (cast (/ c b) int)))
    (assert (=    4 (cast (/ d b) int)))
    ;; Quotient has the same sign as dividend.
    (assert (=   -1 (cast (/ e d) int))) ;; -96 / 80
    (assert (=   10 (cast (% a b) int)))    (assert (=   0 (cast (% b a) int)))
    (assert (=   20 (cast (% b c) int)))    (assert (=   0 (cast (% c b) int)))
    (assert (=   40 (cast (% c d) int)))    (assert (=   0 (cast (% d c) int)))
    ;; Remainder has the same sign as dividend.
    (assert (=   80 (cast (% d e) int)))    (assert (= -16 (cast (% e d) int)))	;; -96 % 80
    )
  (let (((x0a int8) 10) ((x80 int8) 128))
    (assert (=   10 (cast (<< x0a 0) int)))
    (assert (=   80 (cast (<< x0a 3) int)))
    (assert (=  -96 (cast (<< x0a 4) int)))
    (assert (= -128 (cast (>> x80 0) int)))
    (assert (=  -64 (cast (>> x80 1) int)))
    (assert (=   -2 (cast (>> x80 6) int)))
    (assert (=   -1 (cast (>> x80 7) int)))
    )
  (let (((b1 int8) 1)  ((b2 int8) 2)  ((b7 int8) 7)  ((b8 int8) 8))
    (assert (= 1 (& b1 b7)))    (assert (= 2 (& b2 b7)))    (assert (=  0 (& b8 b7)))
    (assert (= 7 (| b1 b7)))    (assert (= 7 (| b2 b7)))    (assert (= 15 (| b8 b7)))
    (assert (= 6 (^ b1 b7)))    (assert (= 5 (^ b2 b7)))    (assert (= 15 (^ b8 b7)))
    )
  (printf "bytes ok\n")
  )

(define-function test-words void ()
  (let (((a int16) 100)  ((b int16) 200)  ((c int16) 4000)  ((d int16) 8000)  ((e int16) 16000)  ((f int16) 32000) ((g int16) 1717))
    (assert (= 	  16000 (cast      e  int)))
    (assert (= 	  24000 (cast (+ d e) int)))
    (assert (= 	  32000 (cast (+ e e) int)))
    (assert (= 	 -17536 (cast (+ e f) int)))
    (assert (= 	   -100 (cast (- a b) int)))
    (assert (= 	 -15800 (cast (- b e) int)))
    (assert (= 	  20000 (cast (* a b) int)))
    (assert (= 	   6784 (cast (* a c) int)))
    (assert (=   -32768 (cast (* e f) int)))	;; 16000 * 32000 (= 512000000) % 65536 = 32768 = -32768
    (assert (=        2 (cast (/ f e) int)))
    (assert (=       18 (cast (/ f g) int)))
    (assert (=     1094 (cast (% f g) int)))
    )
  (let (((x0a00 int16) 0x0a00) ((x8000 int16) 0x8000))
    (assert (=  2560  (cast (<< x0a00  0) int)))
    (assert (= 20480  (cast (<< x0a00  3) int)))
    (assert (= 0x4000 (cast (<< x0a00  5) int)))
    (assert (= -32768 (cast (>> x8000  0) int)))
    (assert (= -16384 (cast (>> x8000  1) int)))
    (assert (=     -2 (cast (>> x8000 14) int)))
    (assert (=     -1 (cast (>> x8000 15) int)))
    )
  (let (((w1 int16) 0x101)  ((w2 int16) 0x202)  ((w7 int16) 0x707)  ((w8 int16) 0x808))
    (assert (= 0x101 (& w1 w7)))    (assert (= 0x202 (& w2 w7)))    (assert (= 0x000 (& w8 w7)))
    (assert (= 0x707 (| w1 w7)))    (assert (= 0x707 (| w2 w7)))    (assert (= 0xf0f (| w8 w7)))
    (assert (= 0x606 (^ w1 w7)))    (assert (= 0x505 (^ w2 w7)))    (assert (= 0xf0f (^ w8 w7)))
    )
  (printf "words ok\n")
  )

(define-function test-ints void ()
  (let (((a int32) 1000)  ((b int32) 2000)  ((c int32) 40000)  ((d int32) 80000)  ((e int32) 160000)  ((f int32) 320000) ((g int32) 17171))
    (assert (= 	         160000      (cast      e  int)))
    (assert (= 	         240000      (cast (+ d e) int)))
    (assert (= 	         320000      (cast (+ e e) int)))
    (assert (= 	          -1000      (cast (- a b) int)))
    (assert (= 	        -158000      (cast (- b e) int)))
    (assert (= 	        2000000      (cast (* a b) int)))
    (assert (= 	       40000000      (cast (* a c) int)))
    (assert (= (cast 3955359744 int) (cast (* e f) int)))  ;; 160000 * 320000 (= 51200000000) % 2^32
    (assert (=  	      2      (cast (/ f e) int)))
    (assert (= 	             18      (cast (/ f g) int)))
    (assert (= 	          10922      (cast (% f g) int))))
  (let (((x0a00 int32) 0x0a00) ((x80kk int32) 0x80000000))
    (assert (=        2560 (cast (<< x0a00  0) int)))
    (assert (=       20480 (cast (<< x0a00  3) int)))
    (assert (=  0x50000000 (cast (<< x0a00 19) int)))
    (assert (= -0x60000000 (cast (<< x0a00 20) int)))
    (assert (=  0x40000000 (cast (<< x0a00 21) int)))
    (assert (=          -1 (cast (>> x80kk 31) int)))
    (assert (=          -2 (cast (>> x80kk 30) int)))
    (assert (=          -4 (cast (>> x80kk 29) int)))
    )
  (let (((l1 int32) 0x10101)  ((l2 int32) 0x20202)  ((l7 int32) 0x70707)  ((l8 int32) 0x80808))
    (assert (= 0x10101 (& l1 l7)))    (assert (= 0x20202 (& l2 l7)))    (assert (= 0x00000 (& l8 l7)))
    (assert (= 0x70707 (| l1 l7)))    (assert (= 0x70707 (| l2 l7)))    (assert (= 0xf0f0f (| l8 l7)))
    (assert (= 0x60606 (^ l1 l7)))    (assert (= 0x50505 (^ l2 l7)))    (assert (= 0xf0f0f (^ l8 l7)))
    )
  ;; Variables are typed implicitly from their initialiser.  Integers have type INT by default.
  (let ((x 0x12345678))
    ;; Casts can be used to truncate a value.
    (assert (= 0x12345678             x            ))
    (assert (= 0x78   	  (cast (cast x int8 ) int)))
    (assert (= 0x5678 	  (cast (cast x int16) int)))
    )
  ;; Literal integers will coerce themselves to match the type of any non-literal they are combined with.
  (let (((b int8) 12)  ((w int16) 12)  ((l int32) 12))
    (assert (= b 12))
    (assert (= w 12))
    (assert (= l 12))
    )
  ;; The following is to test that resource allocation is not confused by deep expressions.
  (assert (= 4 (% (+ (- (* 5 6) (/ 100 5))
		     (- (* 7 8) (/ 100 2)))
		  (>> 96 (<< 1 2)))))
  (printf "ints ok\n")
  )

;; Structure types can be defined anywhere a statement or global declaration is legal.  (Their scope
;; is currently global, but they might become block-local in future.)  Member declarations look like
;; a formal parameter list.

;; Structure type names exist in an independent namespace.  The following declares a new named
;; structure type in that namespace.

(define-struct <point>	;; The type 'struct <point>' is now available in type expressions.
  (;; Member declarations are similar to a formal parameter list.  Members are laid out in order,
   ;; with implicit padding to ensure each member is aligned correctly.  The overall alignment of
   ;; the structure is the largest member alignment.
   (x int)	;; First member at offset '0'.
   (y int)	;; Second member at offset '(sizeof int)'.
   ;; Etc...
   ))

(define-form assert-point (pt xx yy)
  `(let ()
     (assert (= ,xx (member ,pt x)))
     (assert (= ,yy (member ,pt y)))))

;; Structures can be passed by reference by explicitly passing a pointer to the structure object.

(define-function init-<point> void ((pp struct <point> *) (x int) (y int))
  (set (member pp x) x)
  (set (member pp y) y))

;; Structures can be passed by copy by passing the structure object itself.

(define-function print-<point> void ((p struct <point>))
  (printf "<point>(%d %d)\n" (member p x) (member p y)))

;; Structures can be returned from a function.  (The caller passes an implicit first argument
;; which is the address of space in the caller's frame to receive the returned structure object.)

(define-function make-<point> (struct <point>) ((x int) (y int))
  (let (((p struct <point>)))
    (init-<point> (addressof p) x y)
    (return p)))

(define-function test-structs void ()
  (assert (= (* 2 (sizeof int)) (sizeof struct <point>)))
  ;; Automatic storage for structures can be allocated using LET.
  (let (((p struct <point>)))	;; 'p' is an *uninitialised* structure object.
    ;; MEMBER creates a reference to a member of an object of structure type.  The
    ;; reference can be used as an expression or as the target for an assignment.
    (set (member p x) 42)
    (set (member p y) 666)
    (assert-point p 42 666)
    ;; The ADDRESSOF operator works on structure member references.
    (let ((px (addressof (member p x)))
	  (py (addressof (member p y))))
      (assert (= 42  (indir px)))
      (assert (= 666 (indir py))))
    (let ((pp (addressof p)))
      (assert (= (cast (addressof p) void *) (cast (addressof (member p x)) void *)))
      (assert (= (sizeof int) (- (cast (addressof (member p y)) void *)
				 (cast (addressof         p   ) void *))))
      ;; INDIR takes an optional argument that is scaled by the reference type's size and added to
      ;; the base address.
      (assert (= 42  (indir (cast pp int *))))
      (assert (= 666 (indir (cast pp int *) 1)))
      )
    (init-<point> (addressof p) 123 456)	;; Pass by reference.
    (assert-point p 123 456)
    (print-<point> p)				;; Pass by copy.
    (set p (make-<point> 777 888))		;; Assignment from a structure-valued function.
    (assert-point p 777 888)
    (let (((q struct <point>) (make-<point> 111 222)))	;; Implicit structure assignment in a LET initialiser.
      (assert-point q 111 222)
      (assert-point p 777 888)
      (set p q)				;; Explicit structure assignment.
      (assert-point p 111 222))
    (assert-point p 111 222)
    (set p (make-<point> 34 56))	;; Explicit assignment from a structure-valued function.
    (assert-point p 34 56)
    (set (indir (addressof p)) (make-<point> 78 90))	;; Dereferencing a structure reference.
    (assert-point p 78 90))
  (printf "structs ok\n"))

(define (malloc ((void *) long  ) *) (extern malloc))
(define (free   (void     void *) *) (extern free  ))

(define-function test-pointers void ()
  (let ((p (make-<point> 1 2)))
    ;; Pointer subtraction yields the difference in *unscaled bytes* between the two pointers.
    (assert (= (sizeof int) (- (addressof (member p y)) (addressof (member p x))))))
  ;; The LET* here places each definition in the scope of its successors.  It does not support any
  ;; other extended behaviours since the synax would be incompatible with that of type annotation.
  (let* (((mem void *) (malloc 1024))
	 (pb  (cast mem int8  	*))
	 (pw  (cast mem int16 	*))
	 (pl  (cast mem int32 	*))
	 ;;(pf  (cast mem float32 *))
	 ;;(pd  (cast mem float64 *))
	 )
    (printf "memory at %p\n" mem)
    (set (indir pw) 0x0102)
    (if (= 0x02 (indir pb))
	(let ()
	  (printf "little endian\n")
	  ;; Pointer addition adds the *unscaled* offset to the base address.
	  (set (indir (+ pw 2) 0x0304))
	  (assert (= 0x03040102 (indir pl))))
      (assert (= 0x01 (indir pb)))
      (printf "big endian\n")
	  (set (indir (+ pw 2) 0x0304))
	  (assert (= 0x01020304 (indir pl))))
    ;; The optional second argument to INDIR is added to the base address after it is *scaled* by
    ;; the size of the referent type.
    (set (indir pb 8) 42)	(assert (= 42 (indir (+ pb (* 8 (sizeof int8 ))))))
    (set (indir pw 8) 42)	(assert (= 42 (indir (+ pw (* 8 (sizeof int16))))))
    (set (indir pl 8) 42)	(assert (= 42 (indir (+ pl (* 8 (sizeof int32))))))
    (free mem)
    )
  (printf "pointers ok\n"))

(define-function test-forms void ()
  (for (i 0 10) (printf "%d " i))  (printf "\n")
  (printf "%d\n" (let* (((a int) 1) ((b int) (+ a 1))) b))
  )
