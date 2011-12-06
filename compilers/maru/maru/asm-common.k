(define == =)
(define ASMFAIL error)

(define-function _s0P (x)	(= x 0))
(define-function _s1P (x)	(and (<= -128 x) (<= x 127)))
(define-function _s2P (x)	(and (<= -32768 x) (<= x 32767)))
