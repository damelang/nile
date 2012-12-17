; (require "parser.l")
;; (require "peg-compile.l")
;; (require "peg.l")

;;; message

(define %message-dictionaries (array))

(define-structure <message-send> (name methods next))

(define *message-sends*)

(define-function message-send (name)
  (let ((self (new <message-send>)))
    (set (<message-send>-name    self) name)
    (set (<message-send>-methods self) (array))
    (set (<message-send>-next    self) *message-sends*)
    (set *message-sends* self)
    self))

(define-method do-print <message-send> ()
  (print "message<"self.name">"))

(define-function message-send-lookup (send arguments)
  ;;(println "LOOKUP "send)
  (let* ((type   (type-of (car arguments)))
	 (posn   type)
	 (name   (<message-send>-name send))
	 (method ()))
    (while (and (not method) type)
      (set method (assq name (array-at %message-dictionaries type)))
      (set type (array-at %structure-bases type)))
    (if method
	(set-array-at (<message-send>-methods send) posn (cdr method))
      (error "does not understand: "name" "arguments))))

(define-apply <message-send> (self . arguments)
  (apply (or (array-at (<message-send>-methods self) (type-of (car arguments)))
	     (message-send-lookup self arguments))
	 arguments))

(define-function %define-method (type name method)
  (let* ((dict (array-at %message-dictionaries type))
	 (bind (or (assq name dict)
		   (car (set dict
			     (set-array-at %message-dictionaries type
					   (cons (cons name method) dict)))))))
    (set-cdr bind method)))
  
(%define-method <long> 'hello (lambda (self) (println "hello from "self)))

(define-form send (message receiver . arguments)
  (let ((msg (concat-symbol 'send$ message)))
    (or (defined? msg) (eval `(define ,msg (message-send ',message))))
    `(,msg ,receiver ,@arguments)))

;;;----------------------------------------------------------------

(%define-method <long> '* (lambda (self other) (* self other)))

;;;----------------------------------------------------------------

(define *parser-stream*)

(define-form grammar-extend (name . rules)
  (println "GRAMMAR EXTEND" rules)
  ())

(define-form grammar-extend (name parent . rules)
  (println "GRAMMAR DEFINE" rules)
  ())

(define-class <reader> <parser> ())

(define-form grammar-eval (rules expr)
  (println "GRAMMAR EVAL "rules" -> "expr)
  (peg-compile-rules '<reader> rules)
  (and expr (peg-compile-rules '<reader> (list (list 'start expr))))
  ;;(println "GRAMMAR "*reader*)
  (and expr ($start (parser <reader> *parser-stream*)))
  ())

(define-function repl-parser-stream (stream prompt)
  (let ((p (parser <peg> stream))
	(s *parser-stream*)
	(v))
    (set *parser-stream* stream)
    (let ((pos (<parser-stream>-position stream)))
      (if (and (= ?# (parser-stream-next stream))
	       (= ?! (parser-stream-next stream)))
	  (while (<= ?  (parser-stream-next stream)))
	(set (<parser-stream>-position stream) pos)))
    (while (let ()
	     (and prompt (print prompt))
	     ($sexpression p))
      (set v (<parser>-result p))
      ;;(println v)
      (set v (eval v))
      ;;(println " => "v)
      )
    (set *parser-stream* s)
    v))

(define-function repl-stream (stream prompt)	(repl-parser-stream (parser-stream stream) prompt))
(define-function repl-file   (file prompt)	(repl-stream (input-stream file) prompt))
(define-function repl-path   (path prompt)	(repl-file (or (open path) (error "cannot open: "path)) prompt))

(repl-file *input* ())

;;;----------------------------------------------------------------

(define-function concat-symbols args
  (let ((ans (car args)))
    (while (pair? (set args (cdr args)))
      (set ans (concat-symbol ans (car args))))
    ans))

(define-function pval (x)
  (println " => " (eval (dumpln x))))

(define-structure <block> (arity expr))

(define-function new-block (arity expr)
  (let ((self (new <block>)))
    (set (<block>-arity self) arity)
    (set (<block>-expr  self) expr)
    self))

(define-method do-print <block> () (print "[:" self.arity "]"))

{
  expected	= .:what -> (error what " expected near: "(parser-stream-context self.source)) ;

##----------------

  scomment	= ";" (!eol .)* ;
  sspace	= (blank | eol | scomment)* ;
  symfirst	= [!#$%&*+-./<=>@ABCDEFGHIJKLMNOPQRSTUVWXYZ^_abcdefghijklmnopqrstuvwxyz|~] ;
  symrest	= [!#$%&*+-./0123456789<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ^_abcdefghijklmnopqrstuvwxyz|~] ;
  symbol	= (symfirst symrest*) @$$ ;
  sexpr		= symbol
		| number
		| "?".
		| "\""	(!"\""	char)* $:e "\""		-> e
		| "("  sexpression*:e sspace ")"	-> e
		| "'"  sexpr:e				-> (list 'quote e)
		| "`"  sexpr:e				-> (list 'quasiquote e)
		| ",@" sexpr:e				-> (list 'unquote-splicing e)
		| ","  sexpr:e				-> (list 'unquote e)
		| ";" (![\n\r] .)*
		;

  sexpression	= sexpr:s _				-> s ;

##----------------

  blank		= [\t ] ;
  eol		= "\n""\r"* | "\r""\n"* ;
  comment	= "\""(&.!"\"".)*"\""? ;
  _		= (blank | eol | comment)* ;

  digit		= [0123456789] ;
  letter	= [ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz] ;
  binchar	= [!%&*+,-/<=>?@\\^`|~] ;

  number	= digit+ $#:x _							-> x ;

  string	= "'" (&."''"->?' | !"'".)* @$:x "'" _				-> x ;

  idpart	= (letter (letter | digit)*) @ $$ ;
  identifier	= idpart:x !":" _						-> x ;

  unypart	= (letter (letter | digit)*) @ $$ ;
  unysel	= unypart:x !":" _						-> x ;

  binpart	= binchar+ @ $$ ;
  binsel	= binpart:x _							-> x ;

  keypart	= (unypart":") @ $$ ;
  keysel	= keypart:x _							-> x ;

  blockargs	= (":"identifier)+:a "|"_					-> a
		|								-> ()
		;

  block		= "["_ blockargs:a statements:s "]"_				-> `(new-block ,(list-length a) (lambda ,a ,@s)) ;

  primary	= number | string | identifier | block ;

  unysend	= primary:r (unysel:s -> `(send ,s ,r):r)*			-> r ;

  binsend	= unysend:r (binsel:s unysend:a -> `(send ,s ,r ,a):r)*	-> r ;

  keysend	= binsend:r ( (keysel: s binsend:a -> `(,s ,a))+:k		-> `(send ,(apply concat-symbols (map car k)) ,r ,@(map cadr k))
			    |							-> r
			    ) ;

  assignment	= identifier:i ":="_ expression:e				-> `(set ,i ,e) ;

  expression	= assignment | keysend ;

  statements	= "|"_ identifier*:i "|"_ statements:s				-> `((let ,i ,@s))
		| expression?:e (("."_)* expression)*:f				-> `(,@e ,@f) ;

  methodbody	= "["_ statements:s "]"_					-> s
		| "{"_ sexpression*:s "}"_					-> s
		;

  typename	= identifier
		| "<" identifier:i ">"_ -> (concat-symbols '< i '>)
		;

  pattern	= unysel:s							-> (list s)
		| binsel:s identifier:i						-> (list s i)
		| (keysel:s identifier:i -> (list s i))+:k 			-> (cons (apply concat-symbols (map car k)) (map cadr k))
		;

  definition	= identifier:i ":="_ expression:e "."_				-> (pval `(define ,i ,e))
		| typename:t pattern:p methodbody:b				-> (pval `(%define-method ,t ',(car p) (lambda (self ,@(cdr p)) ,@b)))
		| expression:e "."_						-> (pval e)
		| { expected "definition or expression" }
		;

  program	= _ (!"." definition)* "." ;

  program
}

one := 2.
two := 21.
three := one * two.

<long> zero			[ 0 ]
<long> one			[ 1 ]
<long> + aNumber		{ (+ self aNumber) }
<long> <= aNumber		{ (<= self aNumber) }
<long> doubled			[ self + self ]

<long>   println		{ (println self) }
<string> println		{ (println self) }

<block> value			{ ((<block>-expr self)) }
<block> value: a		{ ((<block>-expr self) a) }
<block> value: a value: b	{ ((<block>-expr self) a b) }
<block> valueWithArguments: a	{ (apply (<block>-expr self) a) }

<block> whileTrue: b		{ (while (send value self) (send value b)) }

42 zero.
42 one.
21 doubled.

[ :a :b | a + b ].
[ :a :b | a + b ] value: 3 value: 4.

<long> to: a do: b		[ | i | i := self.  [i <= a] whileTrue: [b value.  i := i + 1] ]
<long> to: a withIndexDo: b	[ | i | i := self.  [i <= a] whileTrue: [b value: i.  i := i + 1] ]

1 to: 10 do: ['hello' println].
1 to: 10 withIndexDo: [:i | i println].

"'this is a string' toUpperCase 3 + 4 + 5 negated - 9 printOn: stdout"
.

"(map-with repl-path *arguments* ())"

"(exit 0)"
