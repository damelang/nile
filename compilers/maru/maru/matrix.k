(define-constant M.a (float-at m 0))
(define-constant M.b (float-at m 1))
(define-constant M.c (float-at m 2))
(define-constant M.d (float-at m 3))
(define-constant M.e (float-at m 4))
(define-constant M.f (float-at m 5))

(define-function matrix-with (a b c d e f)
  (let ((m (data (* 6 sizeof-float))))
    (set M.a a)
    (set M.b b)
    (set M.c c)
    (set M.d d)
    (set M.e e)
    (set M.f f)
    m))

(define-function matrix ()
  (matrix-with
    1.0 0.0
    0.0 1.0
    0.0 0.0))

(define-function matrix-translate (m x y)
  (matrix-with
    M.a					M.b
    M.c					M.d
    (+ (+ (* M.a x) (* M.c y)) M.e)	(+ (+ (* M.b x) (* M.d y)) M.f)))

(define-function matrix-rotate (m t)
  (let* ((sint  (sin t))
	 (msint (- sint))
	 (cost  (cos t)))
    (matrix-with
      (+ (* M.a  cost)	(* M.c sint))	(+ (* M.b  cost) (* M.d sint))
      (+ (* M.a msint)	(* M.c cost))	(+ (* M.b msint) (* M.d cost))
      M.e				M.f)))

(define-function matrix-scale (m x y)
  (matrix-with (* M.a x) (* M.b x) (* M.c y) (* M.d y) M.e M.f))

(define-form matrix-a (self) `(float-at ,self 0))
(define-form matrix-b (self) `(float-at ,self 1))
(define-form matrix-c (self) `(float-at ,self 2))
(define-form matrix-d (self) `(float-at ,self 3))
(define-form matrix-e (self) `(float-at ,self 4))
(define-form matrix-f (self) `(float-at ,self 5))
