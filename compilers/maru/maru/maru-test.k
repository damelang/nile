(define (printf (int	char * ...	) *) (extern printf))
(define (malloc (void *	long		) *) (extern malloc))
(define (atoi   (int	char *		) *) (extern atoi))

(define-struct <foo> ((x int) (y int)))

(define-function print-foo int ((foo struct <foo>))
  (printf "print-foo: %d %d\n" (member foo x) (member foo y))
  (return (+ (member foo x) (member foo y))))

(define-function double-foo (struct <foo>) ((foo struct <foo>))
  (set (member foo x) (* 2 (member foo x)))
  (set (member foo y) (* 2 (member foo y)))
  (return foo))

(define (putchar (int int) *)	(extern putchar))

;; (define-function my-printf int ((fmt char *) (rest ...))
;;   (let ((c 0))
;;     (while (set c (indir fmt))
;;       (incr fmt)
;;       (if (= c ?%)
;; 	  (cond
;; 	    ((= c ?f)	(printf "%f" ))
;; 	    ((= c ?i)	())
;; 	    ((= c ?s)	())
;; 	    (else	(putchar c)))
;; 	(putchar c))))
;;   (return 0))

(define-type foo_t struct <foo>)

(define-function main int ((argc int) (argv char * *))
  (let ((n (if (= argc 1) 10 (atoi (indir argv 1)))))
    (let (((s int *)	(malloc (cast (* (sizeof int) n) long))))
      (for (i 0 n) (set (indir s i) 1))
      (for (i 2 n)
	(if (indir s i)
	    (let ()
	      (for (k i n i) (set (indir s k) 0))
	      (printf "%10d" i)
	      )))
      ))
  (printf "\n")

  (let (((foo foo_t)))	(printf "%d\n" (member foo x))    (printf "%d\n" (member foo y))
    (set (member foo x 42))	(printf "%d\n" (member foo x))    (printf "%d\n" (member foo y))
    (set (member foo y 666))	(printf "%d\n" (member foo x))    (printf "%d\n" (member foo y))
    (printf "sum is %d\n" (print-foo foo))
    (set foo (double-foo foo))
    (print-foo foo)
    )

  ;;(my-printf "%s world %i %f\n" "goodbye" 42 6.66)

  (return 0))
