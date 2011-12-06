(define-function progress args (apply println (cons "; " args)))

(progress "defining bootstrap parser")

(define-structure <begpeg> (result))

(define-form define-rule (rule . body)
  (let ((name (concat-symbol '$ rule)))
    (or (defined? name) (eval (list 'define-selector name)))
    `(define-method ,name <begpeg> (_) ,@body)))

(define-form FAIL (pos)		`(let () (set (<parser-stream>-position _) ,pos) ()))
(define-form RULE (rule)	`(,(concat-symbol '$ rule) self _))
(define-form OBJECT (object)	`(parser-stream-match-object _ ,object))
(define-form CLASS (class)	`(parser-stream-match-class _ ,class))

(define-rule blank
  (or (OBJECT ?\ )
      (OBJECT ?\t)))

(define-rule eol
  (or (and (OBJECT ?\n)
	   (let ()
	     (while (OBJECT ?\r))
	     't))
      (and (OBJECT ?\r)
	   (let ()
	     (while (OBJECT ?\n))
	     't))))

(define-rule comment
  (if (OBJECT ?\#)
      (let ()
	(while (and (parser-stream-peek _)
		    (not (RULE eol)))
	  (parser-stream-next _))
	't)))

(define-rule space
  (while (or (RULE blank) (RULE eol) (RULE comment)))
  't)

(define-rule equals	(and (OBJECT ?=) (RULE space)))
(define-rule bar	(and (OBJECT ?|) (RULE space)))
(define-rule pling	(and (OBJECT ?!) (RULE space)))
(define-rule ampersand	(and (OBJECT ?&) (RULE space)))
(define-rule semicolon	(and (OBJECT ?\;) (RULE space)))
(define-rule colon	(and (OBJECT ?:) (RULE space)))

(define-rule arrow	(let ((pos (<parser-stream>-position _)))
			  (and (OBJECT ?-)
				    (if (OBJECT ?>)
					(RULE space)
				      (FAIL pos)))))

(define-rule dollarhash	(let ((pos (<parser-stream>-position _)))
			  (and (OBJECT ?$)
				    (if (OBJECT ?#)
					(RULE space)
				      (FAIL pos)))))

(define-rule dollardbl	(let ((pos (<parser-stream>-position _)))
			  (and (OBJECT ?$)
				    (if (OBJECT ?$)
					(RULE space)
				      (FAIL pos)))))

(define-rule commaat	(let ((pos (<parser-stream>-position _)))
			  (and (OBJECT ?,)
				    (if (OBJECT ?@)
					(RULE space)
				      (FAIL pos)))))

(define-rule dollar	(and (OBJECT ?$) (RULE space)))
(define-rule quotesgl	(and (OBJECT ?') (RULE space)))
(define-rule backquote	(and (OBJECT ?`) (RULE space)))
(define-rule comma	(and (OBJECT ?,) (RULE space)))
(define-rule at		(and (OBJECT ?@) (RULE space)))
(define-rule query    	(and (OBJECT ??) (RULE space)))
(define-rule plus     	(and (OBJECT ?+) (RULE space)))
(define-rule star     	(and (OBJECT ?*) (RULE space)))
(define-rule lparen    	(and (OBJECT ?() (RULE space)))
(define-rule rparen    	(and (OBJECT ?)) (RULE space)))
(define-rule lbrace   	(and (OBJECT ?{) (RULE space)))
(define-rule rbrace   	(and (OBJECT ?}) (RULE space)))
(define-rule dot      	(and (OBJECT ?.) (RULE space)))

(define-rule letter
  (set self.result
       (CLASS "ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz")))

(define-rule digit
  (set self.result
       (CLASS "0123456789")))

(define-rule identifier
  (let ((pos (<parser-stream>-position _)))
    (and (RULE letter)
	 (let ((ans (group)))
	   (group-append ans self.result)
	   (while (or (RULE letter) (RULE digit))
	     (group-append ans self.result))
	   (RULE space)
	   (set self.result (string->symbol (group->string ans)))))))

(define-rule number
  (let ((pos (<parser-stream>-position _)))
    (and (RULE digit)
	 (let ((ans (group)))
	   (group-append ans self.result)
	   (while (RULE digit) (group-append ans self.result))
	   (RULE space)
	   (set self.result (string->number (group->string ans)))))))

(define-rule char
  (if (OBJECT ?\\)
      (or
	(and (OBJECT ?t)	(set self.result ?\t))
	(and (OBJECT ?n)	(set self.result ?\n))
	(and (OBJECT ?r)	(set self.result ?\r))
	(set self.result (parser-stream-next _)))
    (set self.result (parser-stream-next _))))

(define-rule string
  (and (OBJECT ?\")
       (let ((ans (group)))
	 (while (not (OBJECT ?\"))
	   (if (RULE char)
	       (group-append ans self.result)
	     (error "char expected")))
	 (RULE space)
	 (set self.result (group->string ans)))))

(define-rule class
  (and (OBJECT ?\[)
       (let ((ans (group)))
	 (while (not (OBJECT ?\]))
	   (if (RULE char)
	       (group-append ans self.result)
	     (error "char expected")))
	 (RULE space)
	 (set self.result (group->string ans)))))

(define-selector $expression) ;; forward

(define-rule symfirst
  (set self.result
       (CLASS "!#$%&*+-./:<=>@ABCDEFGHIJKLMNOPQRSTUVWXYZ^_abcdefghijklmnopqrstuvwxyz|~")))

(define-rule symrest
  (set self.result
       (CLASS "!#$%&*+-./:0123456789<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ^_abcdefghijklmnopqrstuvwxyz|~")))

(define-rule symbol
  (let ((pos (<parser-stream>-position _)))
    (and (RULE symfirst)
	 (let ((ans (group)))
	   (group-append ans self.result)
	   (while (RULE symrest) (group-append ans self.result))
	   (RULE space)
	   (set self.result (string->symbol (group->string ans)))))))

(define-rule llist
  (and (RULE lparen)
       (or (RULE expression) (error "expression expected after ("))
       (let ((ans self.result))
	 (or (RULE rparen) (error ") expected"))
	 (RULE space)
	 (set self.result ans))))

(define-rule sexpr
  (or (RULE symbol)
      (RULE number)
      (RULE string)
      (and (RULE lparen)
	   (let ((ans (group)))
	     (while (RULE sexpr) (group-append ans self.result))
	     (or (RULE rparen) (error ") expected in list near: "(parser-stream-context _)))
	     (set self.result (group->list! ans))
	     't))
      (and (RULE quotesgl)  (RULE sexpr)	(set self.result (list 'quote		 self.result)))
      (and (RULE backquote) (RULE sexpr)	(set self.result (list 'quasiquote	 self.result)))
      (and (RULE commaat)   (RULE sexpr)	(set self.result (list 'unquote-splicing self.result)))
      (and (RULE comma)	    (RULE sexpr)	(set self.result (list 'unquote		 self.result)))))

(define-rule atom
  (cond 
    ((RULE lparen)				(let ((ans))
						  (or (RULE expression) (error "expression expected after ("))
						  (set ans self.result)
						  (or (RULE rparen) (error ") expected"))
						  (set self.result ans)))
    ((and (RULE quotesgl) (RULE sexpr))		(set self.result (list 'match-object self.result)))
    ((RULE string)				(set self.result (list 'match-string self.result)))
    ((RULE class)				(set self.result (list 'match-class  self.result)))
    ((RULE identifier)				(set self.result (list 'match-rule   self.result)))
    ((RULE lbrace)				(let ((ans (group)))
						  (while (and (not (= ?> (parser-stream-peek _)))
							      (RULE sexpr))
						    (group-append ans self.result))
						  (or (RULE rbrace) (error "} expected in rule invocation"))
						  (set self.result (cons 'match-rule (group->list! ans)))))
    ((and (RULE backquote) (RULE llist))	(set self.result (list 'match-list self.result)))
    ((RULE dot)					(set self.result (list 'match-any)))
    ((and (RULE arrow) (RULE sexpr))		(set self.result (list 'result-expr self.result)))
    (else					())))

(define-rule repetition
  (and (RULE atom)
       (let ((exp self.result))
	 (cond
	   ((RULE query)	(set exp (list 'match-zero-one  exp)))
	   ((RULE star)		(set exp (list 'match-zero-more exp)))
	   ((RULE plus)		(set exp (list 'match-one-more  exp))))
	 (set self.result exp))))

(define-rule conversion
  (and (RULE repetition)
       (let ((exp self.result))
	 (while (cond
		  ((RULE at)		(set exp (list 'make-span exp)))
		  ((RULE dollarhash)	(if (RULE number)
					    (set exp (list 'make-number self.result exp))
					  (set exp   (list 'make-number 10 exp))))
		  ((RULE dollardbl)	(set exp (list 'make-symbol exp)))
		  ((RULE dollar)	(set exp (list 'make-string exp)))
		  ((RULE colon)		(if (RULE identifier)
					    (set exp (list 'assign-result self.result exp))
					  (error "identifier expected after :")))
		  (else			())))
	 (set self.result exp))))

(define-rule predicate
  (let ((pos (<parser-stream>-position _)))
    (if (and (RULE pling) (RULE conversion))
	(set self.result (list 'peek-not self.result))
      (set (<parser-stream>-position _) pos)
      (if (and (RULE ampersand) (RULE conversion))
	  (set self.result (list 'peek-for self.result))
	(RULE conversion)))))

(define-rule sequence
  (and (RULE predicate)
       (let ((p self.result)
	     (q (group)))
	 (while (RULE predicate) (group-append q self.result))
	 (set self.result
	      (if (group-empty? q)
		  p
		`(match-all ,p ,@(group->list! q)))))))

(define-rule expression
  (and (RULE sequence)
       (let ((p self.result)
	     (q (group)))
	 (while (and (RULE bar) (RULE sequence)) (group-append q self.result))
	 (set self.result
	      (if (group-empty? q)
		  p
		`(match-first ,p ,@(group->list! q)))))))

(define-rule definition
  (let ((id) (exp))
    (RULE space)
    (and (RULE identifier)
	 (set id self.result)
	 (RULE equals)
	 (or (RULE expression) (error "expression expected after ="))
	 (set exp self.result)
	 (or (OBJECT ?\;) (error "; expected"))
	 (set self.result (list id exp)))))

(unit-test "<begpeg>"
  (let ((self (new <begpeg>))
        (_    (parser-stream (string-stream "= | ! & : -> $ ? + * ( ) { } .
  					q6ident1f1er
  					a\nb\"multi\n\tline\n\tstring\"
  					[character-class]
  					\"string\" [class] identifier .
  					foo? bar* baz+
  					letter+$
  					digit+$#
  					digit+$#42
  					&foo !bar -> baz -> \"string\" -> ( a list )
  					atom
  					this is a sequence of stuffs ;
  					and this | is an | expression ;
  					definition = lots of | rules here . ;
  					"))))
    (unit-assert (RULE equals		))
    (unit-assert (RULE bar		))
    (unit-assert (RULE pling		))
    (unit-assert (RULE ampersand	))
    (unit-assert (RULE colon		))
    (unit-assert (RULE arrow		))
    (unit-assert (RULE dollar		))
    (unit-assert (RULE query		))
    (unit-assert (RULE plus		))
    (unit-assert (RULE star		))
    (unit-assert (RULE lparen		))
    (unit-assert (RULE rparen		))
    (unit-assert (RULE lbrace		))
    (unit-assert (RULE rbrace		))
    (unit-assert (RULE dot		))
    (unit-assert (RULE letter		))	(unit-assert (= (<begpeg>-result self) ?q ))
    (unit-assert (RULE digit		))	(unit-assert (= (<begpeg>-result self) ?6 ))
    (unit-assert (RULE identifier	))	(unit-assert (= (<begpeg>-result self) 'ident1f1er))
    (unit-assert (RULE char		))	(unit-assert (= (<begpeg>-result self) ?a ))
    (unit-assert (RULE char		))	(unit-assert (= (<begpeg>-result self) ?\n))
    (unit-assert (RULE char		))	(unit-assert (= (<begpeg>-result self) ?b ))
    (unit-assert (RULE string		))	(unit-assert (= (<begpeg>-result self) "multi\n	line\n	string"))
    (unit-assert (RULE class		))	(unit-assert (= (<begpeg>-result self) "character-class"))
    (unit-assert (RULE atom		))	(unit-assert (equal (<begpeg>-result self) '(match-string "string")))
    (unit-assert (RULE atom		))	(unit-assert (equal (<begpeg>-result self) '(match-class "class")))
    (unit-assert (RULE atom		))	(unit-assert (equal (<begpeg>-result self) '(match-rule identifier)))
    (unit-assert (RULE atom		))	(unit-assert (equal (<begpeg>-result self) '(match-any)))
    (unit-assert (RULE repetition	))	(unit-assert (equal (<begpeg>-result self) '(match-zero-one (match-rule foo))))
    (unit-assert (RULE repetition	))	(unit-assert (equal (<begpeg>-result self) '(match-zero-more (match-rule bar))))
    (unit-assert (RULE repetition	))	(unit-assert (equal (<begpeg>-result self) '(match-one-more (match-rule baz))))
    (unit-assert (RULE conversion	))	(unit-assert (equal (<begpeg>-result self) '(make-string (match-one-more (match-rule letter)))))
    (unit-assert (RULE conversion	))	(unit-assert (equal (<begpeg>-result self) '(make-number 10 (match-one-more (match-rule digit)))))
    (unit-assert (RULE conversion	))	(unit-assert (equal (<begpeg>-result self) '(make-number 42 (match-one-more (match-rule digit)))))
    (unit-assert (RULE predicate	))	(unit-assert (equal (<begpeg>-result self) '(peek-for (match-rule foo))))
    (unit-assert (RULE predicate	))	(unit-assert (equal (<begpeg>-result self) '(peek-not (match-rule bar))))
    (unit-assert (RULE predicate	))	(unit-assert (equal (<begpeg>-result self) '(result-expr baz)))
    (unit-assert (RULE predicate	))	(unit-assert (equal (<begpeg>-result self) '(result-expr "string")))
    (unit-assert (RULE predicate	))	(unit-assert (equal (<begpeg>-result self) '(result-expr (a list))))
    (unit-assert (RULE predicate	))	(unit-assert (equal (<begpeg>-result self) '(match-rule atom)))
    (unit-assert (RULE sequence		))	(unit-assert (equal (<begpeg>-result self) '(match-all (match-rule this) (match-rule is) (match-rule a) (match-rule sequence) (match-rule of) (match-rule stuffs))))
    (unit-assert (RULE semicolon	))
    (unit-assert (RULE expression	))	(unit-assert (equal (<begpeg>-result self) '(match-first (match-all (match-rule and) (match-rule this)) (match-all (match-rule is) (match-rule an)) (match-rule expression))))
    (unit-assert (RULE semicolon	))
    (unit-assert (RULE definition	))	(unit-assert (equal (<begpeg>-result self) '(definition (match-first (match-all (match-rule lots) (match-rule of)) (match-all (match-rule rules) (match-rule here) (match-any))))))))

;;;----------------------------------------------------------------

(define peg-grammar-string (input-stream-up-to (input-stream (open "peg.g") "peg.g") *end*))

;;;----------------

(progress "parsing peg grammar definition")

;;(define BEG (grammar '<peg> '<parser> ()))

(define BEG)

(let ((p (new <begpeg>))
      (_ (parser-stream (string-stream peg-grammar-string))))
  (while ($definition p _)
    ;;(println "\nBEG: " (<begpeg>-result p) " ")
    (set BEG (cons (<begpeg>-result p) BEG)))
  ;;(println)
  ($space p _)
  (and (!= *end* (parser-stream-peek _)) (error "syntax error in BEG near: "(parser-stream-context _)))
  )

(progress "generating compiled parser")

;;(define GEN ($compile (peg-compiler BEG)))

(progress "compiling generated parser")

;; (map eval GEN)

(define-class <peg> <parser> ())

(define GEN (peg-compile-rules '<peg> BEG))

(progress "reparsing grammar definition")

(define PEG)

(define-function peg (stream)
  (let ((self (new <peg>)))
    (set (<peg>-source self) stream)
    self))

(let* ((s (parser-stream (string-stream peg-grammar-string)))
       (p (peg s)))
  (while ($definition p)
    (set PEG (cons (<peg>-result p) PEG)))
  ($space p)
  (and (!= *end* (parser-stream-peek s)) (error "syntax error in PEG near: "(parser-stream-context s))))

(progress "comparing output")

(let ((a BEG)
      (b PEG))
  (while (pair? a)
    (or (equal (car a) (car b))
	(let ()
	  (println "\n\n"(car a)"\n!=\n"(car b))
	  (error "grammars are not identical")))
    (set a (cdr a))
    (set b (cdr b))))

(progress "dumping generated parser")

(println "(define-class <peg> <parser> ())")
(map dumpln GEN)

(progress "parser bootstrap complete")

($sanity-check (grammar '<peg> '<parser> () PEG))
