(define-structure <data-stream> (data position limit))

(define-function data-stream rest
  (let* ((size (or (car rest) 32))
	 (coln (or (cadr rest) (data size))))
    (new <data-stream> coln 0 size)))

(with-instance-accessors <data-stream>

  (define-function data-stream-data (self)		self.data)
  (define-function data-stream-position (self)		self.position)
  (define-function data-stream-size (self)		self.limit)
  (define-function data-stream-origin (self)		(address-of self.data))
  (define-function data-stream-address (self)		(+ (address-of self.data) self.position))

  (define-function data-stream-grow (self)		(let ((lim (max 8 (* self.limit 2)))
							      (old self.data)
							      (big (data lim)))
							  (for (i 0 self.limit) (set-byte-at big i (byte-at old i)))
							  (set self.data  big)
							  (set self.limit lim)
							  self))

  (define-function data-stream-at-end? (self)		(>= self.position self.limit))

  (define-function data-stream-truncate (self)		(set self.limit self.position))

  (define-function data-stream-rewind (self . rest)	(set self.position (if rest (car rest) 0)))

  (define-function data-stream-byte-at (self n)		(let ((i (+ self.position n)))
							  (and (< i self.limit)
							       (byte-at self.data i))))

  (define-function data-stream-set-byte-at (self n b)	(let ((i (+ self.position n)))
							  (and (>= i self.limit) (data-stream-grow self))
							  (set-byte-at self.data i b)))

  (define-function data-stream-get-byte (self)		(and (< self.position self.limit)
							     (let ((b (byte-at self.data self.position)))
							       (incr self.position)
							       b)))

  (define-function data-stream-put-byte (self b)	(while (>= self.position self.limit) (data-stream-grow self))
							(set-byte-at self.data self.position b)
							(incr self.position)
							b)

  (define-function data-stream-contents (self)
    (let ((in  self.data)
	  (out (data self.position)))
      (for (i 0 self.position) (set-byte-at out i (byte-at in i)))
      out))
  )
