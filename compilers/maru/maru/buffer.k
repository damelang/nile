(define-structure <buffer> (size capacity data))

(define-function buffer-new (capacity)	(new <buffer> 0 capacity (data capacity)))

(define-function buffer-grow (self)
  (with-instance-accessors <buffer>
    (let* ((cap (* 2 (max self.size 16)))
	   (big (data cap)))
      (for (i 0 self.size)
	(set (byte-at big i) (byte-at self.data i)))
      (set self.data big)
      (set self.capacity cap))))

(define-function buffer-write (self byte)
  (with-instance-accessors <buffer>
    (or (< self.size self.capacity) (buffer-grow self))
    (set (byte-at self.data self.size) byte)
    (incr self.size)))

(define-function buffer-at (self offset)
  (with-instance-accessors <buffer>
    (and (<= 0 offset)
	 (<    offset self.size)
	 (byte-at self.data offset))))

(define-function buffer-set-byte-at (self offset value)
  (with-instance-accessors <buffer>
    (and (<= 0 offset)
	 (<    offset self.size)
	 (set-byte-at self.data offset value))))

(define-function buffer-set-long-at (self offset value)
  (buffer-set-byte-at self    offset        value    )
  (buffer-set-byte-at self (+ offset 1) (>> value 8 ))
  (buffer-set-byte-at self (+ offset 2) (>> value 16))
  (buffer-set-byte-at self (+ offset 3) (>> value 24)))

(define-function buffer-reset (self)	(set (<buffer>-size self) 0))
(define-function buffer-size (self)	(<buffer>-size self))

(define-function buffer-save (self path)
  (with-instance-accessors <buffer>
    (let ((f (or (open path "w" -1)
		 (error "cannot open for writing: "path))))
      (for (i 0 self.size) (putb (byte-at self.data i) f))
      (close f))))

(define-function buffer-address (self)
  (address-of (<buffer>-data self)))

(define-function buffer-call (self offset)
  (native-call (+ (address-of (<buffer>-data self)) offset)))

;; (let ((b (buffer-new 4096)))
;;   (buffer-write b 65)
;;   (buffer-write b 66)
;;   (buffer-write b 67)
;;   (buffer-save b "a.out"))
