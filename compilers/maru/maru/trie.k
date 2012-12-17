(define-structure <trie> (suffixes key value))

(define-function trie-new key-value	(new <trie> (array) (car key-value) (cadr key-value)))

(define-function trie-suffix-at (trie key)
  (array-detect suffix (<trie>-suffixes trie)
		(and suffix (= key (<trie>-key suffix)))))

(define-function trie-append-suffix (trie suffix)
  (array-append (<trie>-suffixes trie) suffix))

(define-function trie-at (trie keys)
  (while (and trie keys)
    (set trie (trie-suffix-at trie (car keys)))
    (set keys (cdr keys)))
  (and trie (<trie>-value trie)))

(define-function set-trie-at (trie keys value)
  (while keys
    (let ((key (car keys)))
      (set trie (or (trie-suffix-at trie key)
		    (trie-append-suffix trie (trie-new key)))))
    (set keys (cdr keys)))
  (set (<trie>-value trie) value))

(define-function trie-print (trie)
  (and trie
       (let ()
	 (println (<trie>-value trie))
	 (array-do suffix (<trie>-suffixes trie) (trie-print suffix)))))
