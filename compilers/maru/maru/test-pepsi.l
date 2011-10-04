;;;----------------------------------------------------------------

(define-function type-name (x)
  (concat-symbol '< (concat-symbol x '>)))

(define-function concat-symbols args
  (let ((ans (car args)))
    (while (pair? (set args (cdr args)))
      (set ans (concat-symbol ans (car args))))
    ans))

(define-structure <block> (arity expr))

(define-function new-block (arity expr)
  (let ((self (new <block>)))
    (set (<block>-arity self) arity)
    (set (<block>-expr  self) expr)
    self))

(define-method do-print <block> () (print "[:" self.arity "]"))

(define-form block-arity (b n)
  `(or (= (<block>-arity ,b) ,n)
       (error "this block expects ",n" argument(s)")))

(define-function make-message-accessors (name fields i)
  (and (pair? fields)
       (cons `(,(car fields) () ((name) (list 'oop-at 'self ,i)))
	     (make-message-accessors name (cdr fields) (+ i 1)))))

(define-form with-message-accessors (type . body)
  `(with-forms ,(make-message-accessors type (array-at %structure-fields (eval type)) 0)
    (let () ,@body)))

(define %pepsi-methods)

(define-form define-message (type selector args . body)
  (set type (type-name type))
  (set selector (concat-symbol '# selector))
  (or (defined? selector) (eval (list 'define-selector selector)))
  (or (assq selector %pepsi-methods) (push %pepsi-methods (cons selector (eval selector))))
  `(<selector>-add-method ,selector ,type (lambda ,(cons 'self args) (with-message-accessors ,type ,@body))))

(define-form send (selector receiver . args)
  `(,(concat-symbol '# selector) ,receiver ,@args))

(define-function pval (x)
  ;;(println "; "x)
  (eval x))

(define %pepsi-classes (array))
(define %pepsi-topclasses)
(define %pepsi-subclasses (array))

(define-function define-topclass (name fields)
  (println "topclass "name" "fields)
  (let ((type (type-name name)))
    (pval `(define-structure ,type ,fields))
    (pval `(define ,name (new ,type)))
    (pval `(push %pepsi-topclasses ,name))
    (pval `(set-array-at %pepsi-subclasses ,type (array)))
    (pval `(set-array-at %pepsi-classes ,type ,name))))

(define-function define-subclass (name base fields)
  (println "subclass "name" "base" "fields)
  (let ((type  (type-name name))
	(super (type-name base)))
    (pval `(define-class ,type ,super ,fields))
    (pval `(define ,name (new ,type)))
    (pval `(push (array-at %pepsi-subclasses ,super) ,name))
    (pval `(set-array-at %pepsi-classes ,type ,name))))

(define-function make-inits (args index)
  (and (pair? args)
       (cons `(set-oop-at self ,index ,(car args))
	      (make-inits (cdr args) (+ index 1)))))

(define-function define-sysclass (field name base)
  (println "subclass "name" "base" ("field")")
  (let ((type  (type-name name))
	(super (type-name base)))
    (pval `(define ,type ,field))
    (pval `(set-array-at %structure-bases ,field ,super))
    (pval `(set-array-at %type-names ,field ',type))
    (pval `(define ,name (new ,type)))
    (pval `(push (array-at %pepsi-subclasses ,super) ,name))
    (pval `(set-array-at %pepsi-classes ,type ,name))))

{
  expected	= .:what -> (error what " expected near: "(parser-stream-context self.source)) ;

##----------------

  higit		= [0-9A-Fa-f] ;
  char		= "\\"	( "t"					->  9
			| "n"					-> 10
			| "r"					-> 13
			| "x" (higit higit) @$#16
			| "u" (higit higit higit higit) @$#16
			| .
                        )
		| . ;
  sstring	= "\""  (!"\""  char)* $:s "\""  	-> s ;
  scomment	= ";" (!eol .)* ;
  sspace	= (blank | eol | scomment)* ;
  symchar	= [-!#$%&*+./:<=>@A-Z^_a-z|~] ;
  symrest	= symchar | [0-9] ;
  ssymbol	= (symchar symrest*) @$$ ;
  sexpr		= ssymbol
		| number
		| sstring
		| "?".
		| "\""	(!"\""	char)* $:e "\""		-> e
		| "("  (sspace sexpr)*:e sspace ")"	-> e
		| "'"  sexpr:e				-> (list 'quote e)
		| "`"  sexpr:e				-> (list 'quasiquote e)
		| ",@" sexpr:e				-> (list 'unquote-splicing e)
		| ","  sexpr:e				-> (list 'unquote e)
		| "["_ expression:e "]"			-> e
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
  binchar	= [-!%&*+,/<=>?@\\^`|~] ;

  uinteger	= digit+ $#:x _							-> x ;
  integer	= "-"uinteger:x							-> (- x)
		|    uinteger
		;

  ufloat	= (digit+ "."digit+ ("e"digit+)?)@$:s _				-> (string->double s) ;
  float		= "-"ufloat:x							-> (- x)
		|    ufloat
		;

  number	= float | integer ;

  string	= "'" ("''"->?' | !"'" char)* $:x "'" _				-> x ;

  symbol	= "#"(idpart | binchar | ":")+ @ $$:x _				-> `',x ;

  idpart	= (letter (letter | digit)*) @ $$ ;
  identifier	= idpart:x !":" _						-> x ;

  unypart	= (letter (letter | digit)*) @ $$ ;
  unysel	= unypart:x !":" _						-> x ;

  binpart	= binchar+ @ $$ ;
  binsel	= binpart:x _							-> x ;

  keypart	= (unypart":") @ $$ ;
  keysel	= keypart:x _							-> x ;

  blockargs	= (":"identifier)+:a "\|"_					-> a
		|								-> ()
		;

  block		= "["_ blockargs:a statements:s ("."_)* "]"_			-> `(new-block ,(list-length a) (lambda ,a ,@s)) ;

  primary	= number | string | identifier | block | symbol
		| "("_ expression:e ")"_					-> e
		| "$".:e _							-> e
		| "{"_ sexpression:e "}"_					-> e
		;

  unysend	= primary:r (unysel:s -> `(send ,s ,r):r)*			-> r ;

  binsend	= unysend:r (binsel:s unysend:a -> `(send ,s ,r ,a):r)*	-> r ;

  keysend	= binsend:r ( (keysel: s binsend:a -> `(,s ,a))+:k		-> `(send ,(apply concat-symbols (map car k)) ,r ,@(map cadr k))
			    |							-> r
			    ) ;

  assignment	= identifier:i ":="_ expression:e				-> `(set ,i ,e) ;

  expression	= assignment | keysend ;

  statements	= "|"_ identifier*:i "|"_ statements:s				-> `((let ,i ,@s))
		| expression?:e (("."_)* expression)*:f				-> `(,@e ,@f) ;

  methodbody	= "["_ statements:s ("."_)* "]"_				-> s
		| "{"_ sexpression*:s "}"_					-> s
		;

  typename	= identifier
		| "<" identifier:i ">"_ -> (concat-symbols '< i '>)
		;

  pattern	= unysel:s							-> (list s)
		| binsel:s identifier:i						-> (list s i)
		| (keysel:s identifier:i -> (list s i))+:k 			-> (cons (apply concat-symbols (map car k)) (map cadr k))
		;

  definition	= identifier:i ":="_ ( expression:e "."_			-> (pval `(define ,i ,e))
				     | { expected "initialiser expression" }
				     )
		| identifier:i ":"_ (              "("_ identifier*:f ")"_	-> (define-topclass   i   f)
				    | identifier:b "("_ identifier*:f ")"_	-> (define-subclass   i b f)
				    | identifier:b "("_ typename:t    ")"_	-> (define-sysclass t i b  )
				    | { expected "class description" }
				    )
		| typename:t pattern:p methodbody:b				-> (pval `(define-message ,t ,(car p) ,(cdr p) ,@b))
		| expression:e "."_						-> (pval e)
		;

  program	= _ definition* (!. | {expected "definition or expression"}) ;

  program
}

"enough of a class hierarchy to support BlockClosure, SmallInteger, Float, Array and String"

Object : ()
  UndefinedObject : Object (<undefined>)
  BlockClosure : Object (<block>)
  Symbol : Object (<symbol>)
  MessageSelector : Object (<selector>)
  Magnitude : Object ()
    Number : Magnitude ()
      Float  : Number (<double>)
      Integer : Number ()
        SmallInteger : Integer (<long>)
  Collection : Object ()
    SequenceableCollection : Collection ()
      IndexableCollection : SequenceableCollection ()
        ArrayedCollection : IndexableCollection ()
          String : ArrayedCollection (<string>)
          Array  : ArrayedCollection (<array>)

"sundry utility holder"

Pepsi : Object ()

Pepsi error: message	{ (error message) }
Pepsi quit		{ (exit 0) }
Pepsi beep		{ (print "\x07") }

"Pepsi beep; quit."

Object		yourself	[ self ]
UndefinedObject yourself	[ {()} ]

nil := UndefinedObject yourself.
false := nil.
true := #true.

Object new			{ (new (type-of self)) }

Object print			{ (print self) }
Pepsi  newline			[ '\n' print ]
Object println			[ self print.  Pepsi newline.  self ]

Object = other			{ (= self other) }
Object ~= other			{ (not (= self other)) }

Object		not		[ false ]
UndefinedObject not		[ true ]

Object subclassResponsibility	[ Pepsi error: 'a subclass should have overridden this message' ]

BlockClosure value			{ (block-arity self 0) ((<block>-expr self)) }
BlockClosure value: a			{ (block-arity self 1) ((<block>-expr self) a) }
BlockClosure value: a value: b		{ (block-arity self 2) ((<block>-expr self) a b) }
BlockClosure value: a value: b value: c	{ (block-arity self 3) ((<block>-expr self) a b c) }
BlockClosure valueWithArguments: a	{ (block-arity self (array-length a)) (apply (<block>-expr self) (array->list a)) }

Object		or:  aBlock		[ self ]
UndefinedObject or:  aBlock		[ aBlock value ]

Object		and: aBlock		[ aBlock value ]
UndefinedObject and: aBlock		[ self ]

BlockClosure whileTrue: b		{ (while [self value] [b value]) }

Object		ifTrue: aBlock		[ aBlock value ]
UndefinedObject ifTrue: aBlock		[ self ]

Object		ifFalse: aBlock		[ self ]
UndefinedObject ifFalse: aBlock		[ aBlock value ]

Object		ifTrue: aBlock ifFalse: bBlock	[ aBlock value ]
UndefinedObject ifTrue: aBlock ifFalse: bBlock	[ bBlock value ]

Object		ifFalse: aBlock ifTrue: bBlock	[ bBlock value ]
UndefinedObject ifFalse: aBlock ifTrue: bBlock	[ aBlock value ]

Magnitude <   other		[ self subclassResponsibility ]
Magnitude =   other		[ self subclassResponsibility ]
Magnitude <=  other		[ (other < self ) not ]
Magnitude ~=  other		[ (self = other) not ]
Magnitude >   other		[ (other < self )     ]
Magnitude >=  other		[ (self  < other) not ]

SmallInteger +  aNumber		{ (+ self aNumber) }
SmallInteger -  aNumber		{ (- self aNumber) }
SmallInteger *  aNumber		{ (* self aNumber) }
SmallInteger // aNumber		{ (/ self aNumber) }
SmallInteger \\ aNumber		{ (% self aNumber) }

SmallInteger << aNumber		{ (<< self aNumber) }
SmallInteger >> aNumber		{ (>> self aNumber) }

SmallInteger bitAnd: aNumber	{ (& self aNumber) }
SmallInteger bitOr:  aNumber	{ (| self aNumber) }

SmallInteger <  aNumber		{ (< self aNumber) }
SmallInteger =  aNumber		{ (= self aNumber) }

SmallInteger asFloat		{ (long->double self) }

Integer negated			[ 0 - self ]

Float	asFloat			[ self ]

Number pi			[ 3.141592653589793238462643383279502884197169399375108209749445923 ]

Number squared			[ self * self ]

Number sin			[ self asFloat sin ]
Number cos			[ self asFloat cos ]
Number log			[ self asFloat log ]

Float sin			{ (sin self) }
Float cos			{ (cos self) }
Float log			{ (log self) }

Float +  aNumber		{ (+ self aNumber) }
Float -  aNumber		{ (- self aNumber) }
Float *  aNumber		{ (* self aNumber) }
Float /  aNumber		{ (/ self aNumber) }
Float \  aNumber		{ (% self aNumber) }

Float <  aNumber		{ (< self aNumber) }
Float =  aNumber		{ (= self aNumber) }

Float negated			[ 0.0 - self ]

Float truncated			{ (double->long self) }
Float rounded			[ (self + 0.5) truncated ]

one := 2.
two := 21.
three := one * two.

Integer zero			[ 0 ]
Integer one			[ 1 ]
Integer doubled			[ self + self ]

42 zero println.
42 one println.
21 doubled println.

 [ :a :b | a + b ]                    println.
([ :a :b | a + b ] value: 3 value: 4) println.

Number between: x and: y	[ x <= self and: [self <= y] ]

Number to: a do: b		[ | i | i := self.  [i <= a] whileTrue: [b value: i.  i := i + 1] ]
Number by: d to: a do: b	[ | i | i := self.  [i <= a] whileTrue: [b value: i.  i := i + d] ]
Number downTo: a do: b		[ | i | i := self.  [i >= a] whileTrue: [b value: i.  i := i - 1] ]
Number by: d downTo: a do: b	[ | i | i := self.  [i >= a] whileTrue: [b value: i.  i := i - d] ]
Number timesRepeat: aBlock	[ [self > 0] whileTrue: [aBlock value.  self := self - 1] ]

1 to: 10 do: [:i | i print].
0.10 by: 0.01 downTo: 0.01 do: [:i | ' ' print.  i print].
Pepsi println.

Object printBool [ '*' print ]
UndefinedObject printBool [ '-' print ]

SmallInteger test: valu
[
    self print.  ' ' print.
    valu print.  ' ' print.
    (self <  valu) printBool.  ' ' print.
    (self <= valu) printBool.  ' ' print.
    (self  = valu) printBool.  ' ' print.
    (self >= valu) printBool.  ' ' print.
    (self >  valu) printBool.  ' ' println.
"
    self asFloat print.  ' ' print.
    valu asFloat print.  ' ' print.
    (self asFloat <  valu asFloat) printBool.  ' ' print.
    (self asFloat <= valu asFloat) printBool.  ' ' print.
    (self asFloat  = valu asFloat) printBool.  ' ' print.
    (self asFloat >= valu asFloat) printBool.  ' ' print.
    (self asFloat >  valu asFloat) printBool.  ' ' println.
"
]

1 to: 3 do: [:i |  1 to: 3 do: [:j | i test: j]].

SmallInteger isUpperCase	[ $A <= self and: [self <= $Z] ]
SmallInteger isLowerCase	[ $a <= self and: [self <= $z] ]
SmallInteger toUpperCase	[ self isLowerCase ifTrue: [self - 32] ifFalse: [self] ]
SmallInteger toLowerCase	[ self isUpperCase ifTrue: [self + 32] ifFalse: [self] ]

String size			{ (string-length self) }
String new: n			{ (string n) }
String at: n			{ (string-at self n) }
String at: n put: c		{ (set-string-at self n c) }

Collection append: anObject	[ self subclassResponsibility ]

IndexableCollection atAllPut: element
[
    0 to: self size - 1 do: [:i | self at: i put: element]
]

IndexableCollection new: n withAll: element
[
    self := self new: n.
    self atAllPut: element.
    self
]

IndexableCollection from: start to: stop do: aBlock
[
    start to: stop do: [:i | aBlock value: (self at: i)].
]

IndexableCollection do: aBlock
[
    self from: 0 to: self size - 1 do: aBlock
]

IndexableCollection do: aBlock separatedBy: bBlock
[
    self size > 0
        ifTrue:
           [aBlock value: (self at: 0).
            self from: 1 to: self size - 1 do: [:elt | bBlock value.  aBlock value: elt]].
]

IndexableCollection select: aBlock
[
    | answer |
    answer := self new: 0.
    self do: [:e | (aBlock value: e) ifTrue: [answer append: e]].
    answer
]

IndexableCollection collect: aBlock
[
    | answer |
    answer := self new: self size.
    0 to: self size - 1 do: [:i | answer at: i put: (aBlock value: (self at: i))].
    answer
]

IndexableCollection with: other collect: aBlock
[
    | answer |
    answer := self new: self size.
    0 to: self size - 1 do: [:i | answer at: i put: (aBlock value: (self at: i) value: (other at: i))].
    answer
]

String toUpperCase		[ self collect: [:c | c toUpperCase] ]
String toLowerCase		[ self collect: [:c | c toLowerCase] ]

'This is a String' toUpperCase println.
'This is a String' toLowerCase println.

3 + 4 + 5 negated - 9 println.

Array new: n			{ (array n) }
Array size			{ (array-length self) }
Array at: n			{ (array-at self n) }
Array at: n put: e		{ (set-array-at self n e) }

Array print
[
    '#(' print.
    self do: [:elt | elt print] separatedBy: [' ' print].
    ')' print.
]

Array append: e			[ self at: self size put: e ]


ArrayedCollection copyFrom: start to: stop
[
    | end new newSize |
    end := (stop < 0) ifTrue: [self size + stop] ifFalse: [stop].
    newSize := end - start + 1.
    new := self new: newSize.
    start to: end do: [:i | new at: i - start put: (self at: i)].
    new
]

Symbol asString			{ (symbol->string self) }
String asSymbol			{ (string->symbol self) }

Symbol copyFrom: start to: stop	[ (self asString copyFrom: start to: stop) asSymbol ]



Object class			{ (type-of self) }
Object typeName			{ (name-of-type (type-of self)) }
Object className		[ self typeName copyFrom: 1 to: -2 ]
Object subclasses		{ (list->array (array-at %pepsi-subclasses (type-of self))) }
Object instanceVariableNames	{ (list->array (array-at %structure-fields (type-of self))) }

MessageSelector allSelectors	{ (list->array (map cdr %pepsi-methods)) }

MessageSelector selector	[ name ]
MessageSelector methods		[ methods ]

MessageSelector isImplementedFor: anObject
[
    nil ~= (methods at: anObject class)
]

Object methodNames
[
    (MessageSelector allSelectors select: [:m | m isImplementedFor: self]) collect: [:m | m selector]
]

Object printAllSubclasses: indent
[
    indent * 2 timesRepeat: [' ' print].
    self className print.
    ' ' print.
    self instanceVariableNames println.
    self subclasses do: [:sub | sub printAllSubclasses: indent + 1].
]

Object printAllSubclasses
[
    self printAllSubclasses: 0
]

Object withAllSubclassesDo: aBlock
[
    aBlock value: self.
    self subclasses do: [:sub | sub withAllSubclassesDo: aBlock].
]

Pepsi statistics
[
    '\nPepsi class hierarchy:\n' println.
    Object printAllSubclasses.
    '\nPepsi methods:\n' println.
    Object withAllSubclassesDo: [:sub |
	sub className print.
	24 - sub className asString size timesRepeat: [' ' print].
        sub methodNames println].
]

Array fftForwardReal
[
    | n nm1 nd2 imag pi m j |
    n     := self size.				(n bitAnd: n - 1) = 0 ifFalse: [Pepsi error: 'FFT size is not a power of 2'].
    imag  := Array new: n withAll: 0.0.
    nm1   := n - 1.
    nd2   := n // 2.
    j     := nd2.
    "interleave samples in bit-reversed order"
    1 to: nm1 - 1 do: [ :i |
        | k |
        i < j ifTrue: [
            | tr "ti" |				"ignore zero imaginary parts for real function"
            tr := self at: j.			"ti := imag at: j."
            self at: j put: (self at: i).	"imag at: j put: (imag at: i)."
            self at: i put: tr.			"imag at: i put: ti."
        ].
        k := nd2.
        [k <= j] whileTrue: [
            j := j - k.
            k := k // 2.
        ].
        j := j + k.
    ].
    "recombine N 1-point spectra into 1 N-point spectrum"
    pi := Float pi.
    m  := (n asFloat log / 2.0 log) rounded.
    1 to: m do: [ :l |		"for each power-of-two recombination stage"
        | le le2 ur ui sr si |
        le    := 1 << l.
        le2   := le // 2.
	ur := 1.0.
	ui := 0.0.
        sr := (pi / le2 asFloat) cos.
        si := (pi / le2 asFloat) sin negated.
        "for each sub-DFT in the stage"
        1 to: le2 do: [ :j |
            | jm1 tr |
	    jm1 := j - 1.
            jm1 by: le to: nm1 do: [ :i |	"for each recombined pair"
		| ip tr ti |
                ip := i + le2.
                tr := ((self at: ip) * ur) - ((imag at: ip) * ui).
                ti := ((self at: ip) * ui) + ((imag at: ip) * ur).
                self at: ip put: (self at: i) - tr.
                imag at: ip put: (imag at: i) - ti.
                self at: i  put: (self at: i) + tr.
                imag at: i  put: (imag at: i) + ti.
            ].
            tr := ur.
            ur := (tr * sr) - (ui * si).
            ui := (tr * si) + (ui * sr).
        ].
    ].
    imag	"receiver contains cosine correlations, return sine correlations"
]

Array fftForwardRealPowerNormalised: n
[
    | imag |
    imag := self fftForwardReal.
    0 to: self size - 1 do: [ :k |
	| r i |
	r := self at: k.
	i := imag at: k.
	self at: k put: n * (r squared + i squared).
    ]
]

Array fftForwardRealPower
[
    self fftForwardRealPowerNormalised: (2.0 / self size asFloat) squared
]

Array from: start to: stop graphFrom: lo to: hi by: aBlock labeled: label
[
    | dy dyd2 |
    lo 	 := lo asFloat.
    hi 	 := hi asFloat.
    dy 	 := hi - lo / 16.0.
    dyd2 := dy / 2.0.
    hi by: dy downTo: lo do: [:y |
        | z c |
	' ' print.  y < 0 ifFalse: [' ' print].  y print.  ' |' print.
        z := 0.0 between: y - dyd2 and: y + dyd2.
        c := z ifTrue: ['-'] ifFalse: [' '].
	self from: start to: stop do: [:v | ((aBlock value: v value: y - dyd2 value: y + dyd2) ifTrue: ['*'] ifFalse: [c]) print].
	z ifTrue: [' ' print.  stop print.  label print].
        '' println.
    ]
]

Array from: start to: stop graphFrom: lo to: hi labeled: label
[
    self from: start to: stop graphFrom: lo to: hi by: [:x :l :h | x between: l and: h] labeled: label
]

Array graphFrom: lo to: hi labeled: label
[
    self from: 0 to: self size - 1 graphFrom: lo to: hi labeled: label
]

Array testFFT
[
    | twopi isize fsize |
    isize := 64.
    twopi := 2.0 * Float pi.
    self := self new: isize.
    fsize := isize asFloat. 
    0 to: isize - 1 do: [ :i |
	self at: i put:
	    ((twopi *  2.0 * i asFloat / fsize) cos * 1.00)
"	  + ((twopi *  4.0 * i asFloat / fsize) cos * 0.5)"
	  + ((twopi *  6.0 * i asFloat / fsize) sin * 0.75)
    ].
    '\ninput signal:\n' println.
    self graphFrom: -2 to: 2 labeled: ''.
    self fftForwardRealPower.
    '\ncorrelated power spectrum:\n' println.
    self from: 0 to: isize // 2 graphFrom: 0 to: 1.2 by: [:x :l :h | x > l] labeled: ' \u0192s/N Hz'.
]

Pepsi statistics.

Array testFFT.

'\nThat''s all folks' println.
