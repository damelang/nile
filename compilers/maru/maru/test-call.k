(load "define-class.l")
(load "port.l")
(load "data-stream.k")
(load "ansiterm.l")

(define-function nth (n list)
  (while (and (pair? list) (>= (incr n -1) 0))
    (set list (cdr list)))
  (car list))

(define-function %receive (vars)
  (and (pair? vars)
       (cons `(set ,(car vars) (car _))
	     (cons '(set _ (cdr _))
		   (%receive (cdr vars))))))

(define-form receive (expr . vars)
  `(let ((_ ,expr))
     ,@(%receive vars)))

(define values list)

;;; ----------------

(define-structure <label> (name address))

(define-class <global-label> <label> () = global-label
  (do-print ()			(print "<global-label "self.name" "(format "%08x"self.address)">"))
  (label-relocate (offset)	)
  )

(define-class <local-label> <label> () = local-label
  (do-print ()			(print "<local-label "self.name" "(format "%08x"self.address)">"))
  (label-relocate (offset)	(incr self.address offset) (println self)))

(define-function label-address (l)
  (<label>-address l))

;;;

(define-structure <assembler> (data labels references pass))

(define-function assembler opts (new <assembler> (or (car opts) (data-stream)) (cadr opts)))

(with-instance-accessors <assembler>

  (define-function new-external-label (self name)
    (let ((l (global-label name (long-at (subr name) 0))))
      (and (assq name self.labels) (println "warning: label "name" shadows an earlier definition"))
      (push self.labels (cons name l))
      (println l)
      l))

  (define-function new-local-label (self name)
    (let ((l (local-label name ())))
      (and (assq name self.labels) (println "warning: label "name" shadows an earlier definition"))
      (push self.labels (cons name l))
      l))

  (define-function lookup-label-name (self addr)
    (let ((labels self.labels))
      (while (and labels (!= addr (cdar labels))) (set labels (cdr labels)))
      (or (caar labels) (format "0x%08x" addr))))

  (define-function set-assembler-pass (self p)
    (set self.pass p)
    (cond
      ((= 0 p)	(set self.references ()))
      (else	(data-stream-truncate self.data)
		(let ((org (data-stream-origin self.data)))
		  (println "relocating to origin 0x"(format "%08x" org)":")
		  (list-do ref self.references (label-relocate ref org)))))
    (data-stream-rewind self.data))
  )

(define-function _B (a x)	(data-stream-put-byte (<assembler>-data a) x))
(define-function _W (a x)	(_B a x) (_B a (>> x 8)))
(define-function _L (a x)	(_W a x) (_W a (>> x 16)))

(define-function _D1 (a x)	(_B a (- (- x (data-stream-address (<assembler>-data a))) 1)))
(define-function _D4 (a x)	(_L a (- (- x (data-stream-address (<assembler>-data a))) 4)))

(load "asm-x86.k")

(define-function LABEL (x l)
  (let ((pass (<assembler>-pass x)))
    (cond
      ((= pass 0)	(set (<label>-address l) (data-stream-position (<assembler>-data x)))
			(push (<assembler>-references x) l)
			(println l))
      (else		(or (= (<label>-address l) (data-stream-address (<assembler>-data x)))
			    (error "phase error: "l))))))

(define-function CALLl (x l)	(CALLm x (label-address l) 0 0 0))
(define-function JNESl (x l)	(JNESm x (label-address l) 0 0 0))

(define-function extB (b)	(>> (<< b 24) 24))

(define-function getB (a)	(data-stream-get-byte (<assembler>-data a)))
(define-function getL (s)	(let ((a (getB s)) (b (getB s)) (c (getB s)) (d (getB s)))  (+ a (+ (<< b 8) (+ (<< c 16) (<< d 24))))))
(define-function getD1 (s)	(let ((d (extB (getB s)))) (lookup-label-name s (+ d (data-stream-address (<assembler>-data s))))))
(define-function getD4 (s)	(let ((d (getL s)))        (lookup-label-name s (+ d (data-stream-address (<assembler>-data s))))))

(load "dsm-x86.k")

(define %EAX 0x40)
(define %ECX 0x41)
(define %EDX 0x42)
(define %EBX 0x43)
(define %ESP 0x44)
(define %EBP 0x45)
(define %ESI 0x46)
(define %EDI 0x47)

(let* ((x       (assembler (data-stream 8)))	;; small init guarantees buffer will move during assembly
       (putchar (new-external-label x "putchar"))
       (loop1   (new-local-label    x "loop1")))
  (for (pass 0 2)
    (set-assembler-pass x pass)
    (PUSHLr	x	%EBP				)
    (MOVLrr	x	%ESP		%EBP		)
    (SUBLir	x	8		%ESP		)
    (MOVLim	x	?A		0 %ESP 0 0	)
    (LABEL	x	loop1				)
    (CALLl	x	putchar				)
    (ADDLim	x	1		0 %ESP 0 0	)
    (CMPLim	x	(+ ?Z 1)	0 %ESP 0 0	)
    (JNESl	x	loop1				)
    (MOVLim	x	?\n		0 %ESP 0 0	)
    (CALLl	x	putchar				)
    (LEAVE	x					)
    (RET	x					))
  (println (data-stream-position (<assembler>-data x))" bytes generated")
  (data-stream-truncate (<assembler>-data x))
  (data-stream-rewind (<assembler>-data x))
  (let ((p (console-port)))
    (while (not (data-stream-at-end? (<assembler>-data x)))
      (port-write p (format "%08x"(data-stream-address (<assembler>-data x)))"\t")
      (disassemble-on x p)
      (port-put p ?\n)))
  (println (native-call (data-stream-data (<assembler>-data x)) 3 4))
  )
