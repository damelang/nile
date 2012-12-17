(define-method ->string <string> () self)
(define-method ->string <symbol> () (symbol->string self))
(define-method ->string <long>   () (long->string self))
(define-method ->string <double> () (double->string self))

(define-structure <port> (buffer column))

(define-function port options (new <port> (car options) 0))

(define-function string-port  () (new <port> (array) 0))
(define-function console-port () (new <port> () 0))

(define-method do-print <port> () (print "<port "(array-length self.buffer)":"self.column">"))

(define-function port-contents (p)
  (let ((buf (<port>-buffer p)))
    (and buf (array->string buf))))

(define-method port-put <port> (char)
  (if self.buffer
      (array-append self.buffer char)
    (print (format "%lc" char)))
  (set self.column
       (if (or (= char ?\n) (= char ?\r))
	   0
	 (+ self.column 1)))
  char)

(define-method port-write-seq <port> (seq)
  (for-each (->string seq) (lambda (x) (port-put self x))))

(define-method port-write <port> seqs
  (list-do seq seqs (port-write-seq self seq)))

(define-method port-newline <port> ()
  (and (> self.column 0)
       (port-put self ?\n)))

(define-method port-indent <port> (col)
  (for (i 0 col) (port-put self ? )))

(define-method port-newline-indent <port> (col)
  (port-newline self)
  (port-indent self col))
