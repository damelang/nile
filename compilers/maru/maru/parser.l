(define *recurred* '(*recurred*))

;; (define %make-accessor %make-unsafe-accessor)

(define-structure <*end-of-stream-marker*> ())

(define *end* (new <*end-of-stream-marker*>))

(define-method do-print <*end-of-stream-marker*> () (print "<*end-of-stream-marker*>"))

(define-selector $at-end)
(define-selector $peek)
(define-selector $next)

;;;----------------------------------------------------------------

(define-selector $size)

(<selector>-add-method $size <string> string-length)

(define-selector $at)

(<selector>-add-method $at <string> string-at)

(define-function binary-search (seq obj cmp)
  (let ((lo 0)
	(hi (- ($size seq) 1))
	(ix ()))
    (while (and (not ix) (<= lo hi))
      (let* ((m (/ (+ lo hi) 2))
	     (s ($at seq m)))
	(cond
	  ((cmp obj s)	(set hi (- m 1)))
	  ((cmp s obj)	(set lo (+ m 1)))
	  (else		(set ix m)))))
    (or ix -1)))

;;;----------------------------------------------------------------

(define-structure <string-stream> (string size position))

(define-function string-stream (string)
  (let ((self (new <string-stream>)))
    (set (<string-stream>-string   self) string)
    (set (<string-stream>-size     self) (string-length string))
    (set (<string-stream>-position self) 0)
    self))

(define-method $at-end <string-stream> ()
  (= self.position self.size))

(define-method $peek <string-stream> ()
  (let ((pos self.position))
    (if (< pos self.size)
	(string-at self.string pos)
      *end*)))

(define-method $next <string-stream> ()
  (let ((pos self.position))
    (if (< pos self.size)
	(let ((value (string-at self.string pos)))
	  (set self.position (+ pos 1))
	  value)
      *end*)))

(unit-test "<string-stream>"
  (let ((s (string-stream "xhello"))
	(c 0)
	(a (array)))					(unit-assert (= ?x ($peek s)))
							(unit-assert (= ?x ($next s)))
							(unit-assert (= ?h ($peek s)))
    (while (!= *end* (set c ($next s)))
      (array-append a c))				(unit-assert (= "hello" (array->string a)))
							(unit-assert (= *end* ($peek s)))
							(unit-assert (= *end* ($next s)))))

(define-method $source-position <undefined> ())

(define-method $source-position <string-stream> ()
  (cons "<string>" self.position))

;;;----------------------------------------------------------------

(define-structure <list-stream> (source))

(define-function list-stream (source)
  (let ((self (new <list-stream>)))
    (set (<list-stream>-source self) source)
    self))

(define-method $at-end <list-stream> ()
  (not self.source))

(define-method $peek <list-stream> ()
  (if self.source
      (car self.source)
    *end*))

(define-method $next <list-stream> ()
  (if self.source
      (let ((value (car self.source)))
	(set self.source (cdr self.source))
	value)
    *end*))

(unit-test "<list-stream>"
  (let ((s (list-stream '(?x ?h ?e (l (l)) () ?o)))
	(c 0)
	(a (array)))					(unit-assert (= ?x ($peek s)))
							(unit-assert (= ?x ($next s)))
							(unit-assert (= ?h ($peek s)))
    (while (!= *end* (set c ($next s)))
      (array-append a c))				(unit-assert (equal '(?h ?e (l (l)) () ?o) (array->list a)))
							(unit-assert (= *end* ($peek s)))
							(unit-assert (= *end* ($next s)))))

(define-method $source-position <list-stream> () ())

;;;----------------------------------------------------------------

(define-structure <input-stream> (source pending srcpos))

(define-function input-stream (source path)
  (let ((self (new <input-stream>)))
    (set (<input-stream>-source self) source)
    (set (<input-stream>-srcpos self) (cons path 0))
    self))

(define-method $at-end <input-stream> ()
  (= () ($peek self)))

(define-method $peek <input-stream> ()
  (or self.pending
      (if self.source
	  (let ((c (getc self.source)))
	    (if c
		(let ()
		  (and (= ?\n c) (set self.srcpos (cons (car self.srcpos) (+ 1 (cdr self.srcpos)))))
		  (set self.pending c))
	      (or (= self.source *input*) (close self.source))
	      (set self.source ())
	      (set self.pending *end*)))
	(set self.pending *end*))))

(define-method $next <input-stream> ()
  (let ((c ($peek self)))
    (set (<input-stream>-pending self) ())
    c))

(define-method $source-position <input-stream> ()
  self.srcpos)

(define-function input-stream-up-to (self delimiter)
  (let ((a (array)))
    (while (!= delimiter ($peek self))
      (array-append a ($next self)))
    (array->string a)))

;; (unit-test "<input-stream>"
;;   (let ((s (input-stream *input*))
;; 	(c 0)
;; 	(a (array)))						(unit-assert (= ?; ($peek s)))
;; 								(unit-assert (= ?; ($next s)))
;; 								(unit-assert (= ?h ($peek s)))
;;     (while (!= ?! (set c ($next s)))
;;       (array-append a c))					(unit-assert (= "hello" (array->string a)))
;; 								(unit-assert (= "goodbye" (input-stream-up-to s ?!)))));hello!goodbye!

;;;----------------------------------------------------------------

;(define <token> <pair>)		(define token cons)			(define new-<token> cons)
;(define <token>-value car)	(define set-<token>-value set-car)
;(define <token>-tail  cdr)	(define set-<token>-tail  set-cdr)

(define-structure <token> (value tail position notes index))

(define-function new-<token> () (new <token>))

(define-function token (value index srcpos)
  (let ((self (new <token>)))
    (set (<token>-value    self) value)
    (set (<token>-index    self) index)
    (set (<token>-position self) srcpos)
    self))

(define-method do-print <token> ()
  (print "<token "self.index" "(format "%c" self.value))
  (map (lambda (x)
	 (and (symbol? (car x))
	      (print " "(car x))))
       self.notes)
  (print ">"))

;(define <token> <pair>)		;(define token cons)			;(define new-<token> cons)
;(define <token>-value car)	(define set-<token>-value set-car)
;(define <token>-tail  cdr)	(define set-<token>-tail  set-cdr)

(define-structure <group> (first last))

(define-function group ()
  (let ((self  (new <group>))
	(token (new-<token>)))
    (set (<group>-first self) token)
    (set (<group>-last  self) token)
    self))

(define-function list-from-to (start stop)
  (and (!= start stop)
       (cons (<token>-value start) (list-from-to (<token>-tail start) stop))))

(define-function group-from-to (first last)
  (let ((self  (new <group>)))
    (set (<group>-first self) first)
    (set (<group>-last  self) last)
    self))

(define-method do-print <group> ()
  (print "{ ")
  (let ((pos (<group>-first self))
	(lim (<group>-last  self)))
    (while (!= pos lim)
      (dump (<token>-value pos))
      (print " ")
      (set pos (<token>-tail pos))))
  (print "}"))

(define-function group-empty? (self)
  (= (<group>-first self) (<group>-last  self)))

(define-function group-length (self)
  (let ((tok (<group>-first self))
	(lim (<group>-last  self))
	(len 0))
    (while (!= tok lim)
      (set len (+ len 1))
      (set tok (<token>-tail tok)))
    len))

(define-function group-append (self value . stream)
  (let ((tok  (new-<token>))
	(last (<group>-last self)))
    (set (<token>-value    last) value)
    (set (<token>-tail     last) tok)
    (set (<token>-position last) ($source-position (car stream)))
    (set (<group>-last     self) tok)))

;; (define-function group-append-all (self value)
;;   (let ((tok (<group>-first value))
;; 	(lim (<group>-last value)))
;;     (while (!= tok lim)
;;       (group-append self (<token>-value tok))
;;       (set tok (<token>-tail tok)))))

(define-function group-append-list (self list)
  (while (pair? list)
    (group-append self (car list))
    (set list (cdr list))))

(define-function group->string (self)
  (let* ((len (group-length self))
	 (str (string len))
	 (idx 0)
	 (tok (<group>-first self)))
    (while (< idx len)
      (set (string-at str idx) (<token>-value tok))
      (set tok (<token>-tail tok))
      (set idx (+ idx 1)))
    str))

(define-selector group->list (self) self)

(define-function set-pair-source-position (obj pos)
  (set (<pair>-source obj) pos)
  obj)

(define-function make-group->list (first last)
  (and (!= first last)
       (set-pair-source-position
	 (cons (<token>-value first) ;(group->list (<token>-value first))
	       (make-group->list (<token>-tail first) last))
	  (<token>-position first)
	  )))

(define-method group->list <group> ()
  (make-group->list (<group>-first self) (<group>-last self)))

(define-function group->list! (self)
  (group->list self)
;;    (let ((start (<group>-first self))
;;  	(stop  (<group>-last self)))
;;      (and (!= start stop)
;;  	 (let ((pos start))
;;  	   (while (!= (<token>-tail pos) stop) (set pos (<token>-tail pos)))
;;  	   (set (<token>-tail pos) ())
;;  	   start)))
  )

;; (define-function group->list (self)
;;   ;;(println "\n\n\n === " self)
;;   (let ((first (<group>-first self))
;; 	(last  (<group>-last  self)))
;;     (if (= first last)
;; 	()
;;       (while (!= last (cdr first))
;; 	;;(println "\n\n\n" first last)
;; 	(set first (cdr first)) last)
;;       (set-cdr first ())
;;       (<group>-first self))))

(unit-test "<group>"
  (let ((g (group)))			(unit-assert (= 0 (group-length g)))	(unit-assert (equal (group->list g) '()))
    (group-append g 'foo)		(unit-assert (= 1 (group-length g)))	(unit-assert (equal (group->list g) '(foo)))
    (group-append g 'bar)		(unit-assert (= 2 (group-length g)))	(unit-assert (equal (group->list g) '(foo bar)))
    (group-append-list g '(baz qux))	(unit-assert (= 4 (group-length g)))	(unit-assert (equal (group->list g) '(foo bar baz qux)))))

;;;----------------------------------------------------------------

(define-structure <parser-stream> (source position index))

;;(define-function parser-stream (source)
;;  (let ((self (new <parser-stream>)))
;;    (set (<parser-stream>-source self)   source)
;;    (set (<parser-stream>-position self) (new-<token>))
;;    self))

(define-function parser-stream (source)
  (let ((self (new <parser-stream>)))
    (set (<parser-stream>-source self)   source)
    (set (<parser-stream>-position self) (token ($next source) 0 ($source-position (<parser-stream>-source self))))
    (set (<parser-stream>-index self) 0)
    self))

(define-function parser-stream-at-end (self)
  (and (= *end* (<token>-value (<parser-stream>-position self)))))

(define-function parser-stream-peek-token (self)
  (<parser-stream>-position self))

(define-function parser-stream-peek (self)
  (<token>-value (<parser-stream>-position self)))

(define-function parser-stream-next-token (self)
  (let ((here (<parser-stream>-position self)))
    (or (= *end* (<token>-value here))
	(let ((tail (<token>-tail here)))
	  (set (<parser-stream>-position self)
	       (or tail (set (<token>-tail here)
			     (token ($next (<parser-stream>-source self))
				    (incr (<parser-stream>-index self) 1)
				    ($source-position (<parser-stream>-source self))
				    ))))))
    here))

(define-function parser-stream-next (self)
  (<token>-value (parser-stream-next-token self)))

(define-function parser-stream-push-token (self token)
  (set (<token>-tail token) (<parser-stream>-position self))
  (set (<parser-stream>-position self) token))

(define-function parser-stream-push (self value)
  (parser-stream-push-token self (token value (<parser-stream>-index self) ($source-position (<parser-stream>-source self)))))

(define-function parser-stream-match-object (self value)
  (and (= value (parser-stream-peek self))
       (parser-stream-next self)))

(define-function parser-stream-match-any (self)
  (and (!= *end* (parser-stream-peek self))
       (parser-stream-next self)))

(define-function make-class (s)
  (let* ((out (array))
	 (i   0)
	 (l   (string-length s))
	 (k   (- l 2)))
    (while (< i k)
      (let ((c (string-at s i))
	    (d (string-at s (+ i 1))))
	(if (= ?- d)
	    (let ((e (string-at s (+ i 2))))
	      (if (<= c e)
		  (if (<= (- e c) 2048)
		      (for (d c (+ e 1)) (array-append out d))
		    (error "character range too large: "c"-"e))
		(error "malformed character range: "c"-"e))
	      (set i (+ i 3)))
	  (array-append out c)
	  (set i (+ i 1)))))
    (while (< i l)
      (array-append out (string-at s i))
      (set i (+ i 1)))
    (let ((c (array->string (array-sort out))))
      c)))

(define-function parser-stream-match-class (self class)
  (let ((obj (parser-stream-peek self)))
    (and (long? obj) (<= 0 (binary-search class obj <))
	 (parser-stream-next self))))

(define-function parser-stream-fail (self position)
  (set (<parser-stream>-position self) position)
  ())

(define-function parser-stream-match-string (self str)
  (let ((pos (<parser-stream>-position self))
	(idx 0)
	(lim (string-length str)))
    (while (and (< idx lim) (parser-stream-match-object self (string-at str idx)))
      (set idx (+ idx 1)))
    (if (= idx lim)
	str
      (parser-stream-fail self pos))))

(define-function parser-stream-context (self)
  (let ((a (array)))
    (while (and (<token>-tail (parser-stream-peek-token self)) (!= *end* (parser-stream-peek self)))
      (array-append a (parser-stream-next self)))
    (and (> (array-length a) 0)
	 (string-do c "[31;1m<!>[30;0m" (array-append a c)))
    (for (i 0 32)
      (if (!= *end* (parser-stream-peek self))
	  (array-append a (parser-stream-next self))
	(string-do c "[34;1m<EOF>[30;0m" (array-append a c))
	(set i 999)))
    ;;(array-do x a (println x))
    (array->string a)))

(define-method $source-position <parser-stream> () ($source-position self.source))

;;;----------------

(unit-test "<parser-stream>"
  (let ((s (parser-stream (string-stream "xhello")))
	(c 0)
	(a (array)))						(unit-assert (= ?x (parser-stream-peek s)))
								(unit-assert (= ?x (parser-stream-next s)))
								(unit-assert (= ?h (parser-stream-peek s)))
    (let ((p (<parser-stream>-position s)))
      (while (!= *end* (set c (parser-stream-next s)))
	(array-append a c))					(unit-assert (= *end* (parser-stream-peek s)))
								(unit-assert (= *end* (parser-stream-next s)))
      (set (<parser-stream>-position s) p)			(unit-assert (= ?h (parser-stream-peek s)))
								(unit-assert (= ?h (parser-stream-next s)))
      (parser-stream-push s ?r)					(unit-assert (= ?r (parser-stream-peek s)))
      (parser-stream-push s ?o)					(unit-assert (= ?o (parser-stream-peek s)))
      (parser-stream-push s ?m)					(unit-assert (= ?m (parser-stream-peek s)))
      (while (!= *end* (set c (parser-stream-next s)))
	(array-append a c))					(unit-assert (= "hellomorello" (array->string a)))
      (set (<parser-stream>-position s) p)			(unit-assert (= ?h (parser-stream-peek s)))
								(unit-assert (= ?h (parser-stream-next s)))
      (while (!= *end* (set c (parser-stream-next s)))
	(array-append a c))					(unit-assert (= "hellomorelloello" (array->string a)))
      (parser-stream-push s (list 'and "strings!" (list 'and (list 'lists))))
      (parser-stream-push s 'symbols)
      (parser-stream-push s "yo dude...")			(unit-assert (= "yo dude..." (parser-stream-next s)))
								(unit-assert (= 'symbols (parser-stream-next s)))
								(unit-assert (equal '(and "strings!" (and (lists)))
										    (parser-stream-next s))))))

;;;----------------------------------------------------------------

(define-structure <rule> (name body recursive?))

(define-function new-<rule> (name body)
  (let ((self (new <rule>)))
    (set (<rule>-name self) name)
    (set (<rule>-body self) body)
    self))

(define-method do-print <rule> ()
  (print "<rule "self.name"="self.body">"))

;;;----------------------------------------------------------------

(define-structure <grammar> (name base fields rules type))

(define-method do-print <grammar> ()
  (print "Grammar["(<grammar>-name self)":"(<grammar>-base self)(<grammar>-fields self)"]={\n")
  (list-do rule (<grammar>-rules self) (println "  " rule))
  (print " }"))

(define-function grammar-add-rule (self rule)
  (let* ((name  (car rule))
	 (body  (cadr rule))
	 (rules (<grammar>-rules self))
	 (pair  (or (assq name rules)
		    (car (set (<grammar>-rules self)
			      (cons (cons name body) rules))))))
    (set-cdr pair (new-<rule> name body))))

(define-function grammar (name base fields rules)
  (let ((self (new <grammar>)))
    (set (<grammar>-name   self) name)
    (set (<grammar>-base   self) base)
    (set (<grammar>-fields self) fields)
    (with-map grammar-add-rule self rules)
    self))

(define-function grammar-find-rule-or-nil (self name)
  (cdr (assq name (<grammar>-rules self))))

(define-function grammar-find-rule (self name)
  (or (grammar-find-rule-or-nil self name)
      (error "rule '"name"' not found in grammar "(<grammar>-name self))))

(define-function grammar-find-body (self name)
  (<rule>-body (grammar-find-rule self name)))

;;;----------------

(define-method $reachable-from <grammar> (exp reached)
  ;;(dumpln "REACHABLE-FROM "exp)
  (and (pair? exp)
       (let ((op (car exp)))
	 (and (!= op 'quasiquote)
	      (!= op 'quote)
	      (if (= 'match-rule (car exp))
		  (let ((name (cadr exp)))
		    (or (member? name reached)
			(set reached ($reachable-from self (grammar-find-body self name) (cons name reached)))))
		(map (lambda (exp) (set reached ($reachable-from self exp reached))) (cdr exp))))))
  reached)

(define-method $warn-unreachable <grammar> ()
  (let ((start (grammar-find-rule-or-nil self 'start)))
    (and start
	 (let ((reached ($reachable-from self (<rule>-body start) '(start))))
	   (list-do assoc self.rules
	     (or (member? (<rule>-name (cdr assoc)) reached)
		 (println "; WARNING: unreachable from start: "(<rule>-name (cdr assoc)))))))))

(define-selector $consumes-input?)

(define-method $consumes-input-all? <grammar> (exps)
  (and exps
       (or ($consumes-input?     self (car exps))
	   ($consumes-input-all? self (cdr exps)))))

(define-method $consumes-input-first? <grammar> (exps)
  (or (not exps)
      (and ($consumes-input?       self (car exps))
	   ($consumes-input-first? self (cdr exps)))))

(define-method $consumes-input? <grammar> (exp)
  ;;(dumpln "CONSUMES-INPUT? "exp)
  (let ((op (car exp)))
    (cond
      ((= op 'match-object)		1)
      ((= op 'match-string)		1)
      ((= op 'match-class)		1)
      ((= op 'match-rule-in)		1)	;xxx THIS IS NOT RELIABLE xxx
      ((= op 'match-rule)		($consumes-input? self (grammar-find-body self (cadr exp))))
      ((= op 'match-any)		1)
      ((= op 'result-expr)		())
      ((= op 'match-list)		1)
      ((= op 'match-zero-one)		())
      ((= op 'match-zero-more)		())
      ((= op 'match-one-more)		($consumes-input? 	self (cadr  exp)))
      ((= op 'make-span)		($consumes-input? 	self (cadr  exp)))
      ((= op 'make-number)		($consumes-input? 	self (caddr exp)))
      ((= op 'make-radix-number)	($consumes-input? 	self (caddr exp)))
      ((= op 'make-symbol)		($consumes-input? 	self (cadr  exp)))
      ((= op 'make-string)		($consumes-input? 	self (cadr  exp)))
      ((= op 'assign-result)		($consumes-input? 	self (caddr exp)))
      ((= op 'peek-not)			($consumes-input? 	self (cadr  exp)))
      ((= op 'peek-for)			($consumes-input? 	self (cadr  exp)))
      ((= op 'match-all)		($consumes-input-all?   self (cdr   exp)))
      ((= op 'match-first)		($consumes-input-first? self (cdr   exp)))
      (else				(error "$consumes-input? does not know about "op)))))

(define-selector $recursive-from?)

(define-method $recursive-from-all? <grammar> (exps name)
  (and exps
       (let ((hd (car exps)))
	 (or ($recursive-from? self hd name)
	     (and (not ($consumes-input? self hd))
		  ($recursive-from-all? self (cdr exps) name))))))

(define-method $recursive-from-first? <grammar> (exps name)
  (and exps
       (or ($recursive-from?       self (car exps) name)
	   ($recursive-from-first? self (cdr exps) name))))

(define-method $recursive-from? <grammar> (exp name)
  ;;(dumpln "RECURSIVE-FROM? "exp)
  (let ((op (car exp)))
    (cond
      ((= op 'match-object)		())
      ((= op 'match-string)		())
      ((= op 'match-class)		())
      ((= op 'match-rule-in)		())	;xxx THIS IS NOT RELIABLE xxx
      ((= op 'match-rule)		(or (= name (cadr exp)) ($recursive-from? self (grammar-find-body self (cadr exp)) name)))
      ((= op 'match-any)		())
      ((= op 'result-expr)		())
      ((= op 'match-list)		())
      ((= op 'match-zero-one)		($recursive-from? 	self (cadr  exp) name))
      ((= op 'match-zero-more)		($recursive-from? 	self (cadr  exp) name))
      ((= op 'match-one-more)		($recursive-from? 	self (cadr  exp) name))
      ((= op 'make-span)		($recursive-from? 	self (cadr  exp) name))
      ((= op 'make-number)		($recursive-from? 	self (caddr exp) name))
      ((= op 'make-radix-number)	($recursive-from? 	self (caddr exp) name))
      ((= op 'make-symbol)		($recursive-from? 	self (cadr  exp) name))
      ((= op 'make-string)		($recursive-from? 	self (cadr  exp) name))
      ((= op 'assign-result)		($recursive-from? 	self (caddr exp) name))
      ((= op 'peek-not)			($recursive-from? 	self (cadr  exp) name))
      ((= op 'peek-for)			($recursive-from? 	self (cadr  exp) name))
      ((= op 'match-all)		($recursive-from-all?   self (cdr   exp) name))
      ((= op 'match-first)		($recursive-from-first? self (cdr   exp) name))
      (else				(error "$recursive-from? does not know about "op)))))

(define-method $left-recursive? <grammar> (rule)
  ($recursive-from? self (<rule>-body rule) (<rule>-name rule)))

(define-method $warn-left-recursion <grammar> ()
  (list-do assoc self.rules
    (let ((rule (cdr assoc)))
      (and ($left-recursive? self rule)
	   (set (<rule>-recursive? rule) 1)
	   (println "; WARNING: left-recursive rule: "(<rule>-name (cdr assoc)))))))

(define-method $sanity-check <grammar> ()
  ($warn-unreachable self)
  ($warn-left-recursion self)
  )

;;;----------------------------------------------------------------

(define-structure <parser> (source result))

(define-function parser (type stream)
  (let ((self (new type)))
    (set (<parser>-source self) stream)
    self))

(define-selector $start)

(define-selector parse-from)

(define-method parse-from <parser> (source rule)
  (set self.source (parser-stream source))
  (rule self))

(define-selector parse)

(define-function parse (self source)
  (parse-from self source $start))

(define-selector parse-all-from)

(define-method parse-all-from <parser> (source rule)
  (set self.source (parser-stream source))
  (let ((results (array)))
    (while (rule self)
      (array-append results self.result))
    results))

(define-function parse-all (self source)
  (parse-all-from self source $start))

;;;----------------------------------------------------------------

(define-class <peg> <parser> ())

(define %make-accessor %make-safe-accessor)

;;;----------------------------------------------------------------

(define-function %set-list-source (x y)
  (and (pair? x)
       (let ()
	 (and (pair? y) (set (<pair>-source x) (<pair>-source y)))
	 (%set-list-source (cdr x) (cdr y))))
  x)

(define-function set-list-source (x pos)
  ;;(println "SET LIST "x" SOURCE "pos)
  (%set-list-source x pos) ;; ($source-position pos))
  x)

;;;----------------------------------------------------------------

(define *outer* '(*outer*))
(define *inner* '(*inner*))
(define *recur* '(*recur*))

(define-structure <memo> (success result position))

(define-method do-print <memo> ()
  (if (long? self.success)
      (print "#"self.success)
    (print "<memo>")))

(define-function memoise (self success result position)
  (with-instance-accessors <memo>
    (set self.success  success)
    (set self.result   result)
    (set self.position position)))

(define %cookies 0)

(define-form put (where key val)	`(set ,where (cons (cons ,key ,val) ,where)))
(define-form get (where key)		`(cdr (assq ,key ,where)))
(define-form rem (where key)		`(set ,where (%rm ,where ,key)))

(define-function %rm (where key)
  (and (pair? where)
       (if (= key (caar where))
	   (cdr where)
	 (cons (car where) (%rm (cdr where) key)))))
