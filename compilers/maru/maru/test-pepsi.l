;;; A Smalltalk-like language that compiles to Maru s-expressions
;;; 
;;; ./eval repl.l test-pepsi.l

;; Some utility functions for dealing with class and selector names

(define-function type-name (x)
  (concat-symbol '< (concat-symbol x '>)))

(define-function concat-symbols args
  (let ((ans (car args)))
    (while (pair? (set args (cdr args)))
      (set ans (concat-symbol ans (car args))))
    ans))

;; A Maru structure for representing Smalltalk block closures

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

;; Mechanisms for managing the class hierarchy and for defining methods

(define %pepsi-classes (array))
(define %pepsi-topclasses)
(define %pepsi-subclasses (array))

(define-function make-message-accessors (name fields i)
  (and (pair? fields)
       (cons `(,(car fields) () ((name) (list 'oop-at 'self ,i)))
             (make-message-accessors name (cdr fields) (+ i 1)))))

(define-form with-message-accessors (type . body)
  `(with-forms ,(make-message-accessors type (array-at %structure-fields (eval type)) 0)
    (let () ,@body)))

(define %pepsi-methods)

(define-form define-message (src type selector args . body)
  (set type (type-name type))
  (set selector (concat-symbol '# selector))
  (or (defined? selector) (eval (list 'define-selector selector)))
  (or (assq selector %pepsi-methods) (push %pepsi-methods (cons selector (eval selector))))
  `(set (<expr>-name (<selector>-add-method ,selector ,type
			(lambda ,(cons 'self args)
			  (with-message-accessors ,type ,@body)))) ,src))

(define-form send (selector receiver . args)
  `(,(concat-symbol '# selector) ,receiver ,@args))

(define-form define-class (name basis fields)
  (let ((base (eval basis)))
    (set fields (concat-list (array-at %structure-fields base) fields))
    (sanity-check-structure-fields name fields)
    (let ((type   (%allocate-type name))
          (size   (list-length fields)))
      (set-array-at %structure-sizes  type size)
      (set-array-at %structure-fields type fields)
      (set-array-at %structure-bases  type base)
      (let ((derived (or (array-at %structure-derivatives base)
                         (set-array-at %structure-derivatives base (array)))))
        (array-append derived type))
      `(let ()
         (define ,name ,type)
         ,@(%make-accessors name fields)
         ,type))))

(define-function define-topclass (name fields)		;; the root of a hierarchy
  (println "topclass "name" "fields)
  (let ((type (type-name name)))
    (eval `(define-structure ,type ,fields))
    (eval `(define ,name (new ,type)))
    (eval `(push %pepsi-topclasses ,name))
    (eval `(set-array-at %pepsi-subclasses ,type (array)))
    (eval `(set-array-at %pepsi-classes ,type ,name))))

(define-function define-subclass (name base fields)	;; a subclass in a hierarchy
  (println "subclass "name" "base" "fields)
  (let ((type  (type-name name))
        (super (type-name base)))
    (eval `(define-class ,type ,super ,fields))
    (eval `(define ,name (new ,type)))
    (eval `(push (array-at %pepsi-subclasses ,super) ,name))
    (eval `(set-array-at %pepsi-classes ,type ,name))))

(define-function make-inits (args index)
  (and (pair? args)
       (cons `(set-oop-at self ,index ,(car args))
              (make-inits (cdr args) (+ index 1)))))

(define-function define-sysclass (field name base)	;; a subclass based on a Maru structure
  (println "subclass "name" "base" ("field")")
  (let ((type  (type-name name))
        (super (type-name base)))
    (eval `(define ,type ,field))
    (eval `(set-array-at %structure-bases ,field ,super))
    (eval `(set-array-at %type-names ,field ',type))
    (eval `(define ,name (new ,type)))
    (eval `(push (array-at %pepsi-subclasses ,super) ,name))
    (eval `(set-array-at %pepsi-classes ,type ,name))))

;;; Define the syntax of Smalltalk programs

{
  expected      = .:what -> (error what " expected near: "(parser-stream-context self.source)) ;

  pos           =      -> (<parser-stream>-position self.source) ;
  src           = .:s  -> (group->string (group-from-to s (<parser-stream>-position self.source))) ;

# ---------------- the syntax of embedded s-expressions (for primitives)

  higit         = [0-9A-Fa-f] ;
  char          = "\\"  ( "t"                                   ->  9
                        | "n"                                   -> 10
                        | "r"                                   -> 13
                        | "x" (higit higit) @$#16
                        | "u" (higit higit higit higit) @$#16
                        | .
                        )
                | . ;
  sstring       = "\""  (!"\""  char)* $:s "\""         -> s ;
  scomment      = ";" (!eol .)* ;
  sspace        = (blank | eol | scomment)* ;
  symchar       = [-!#$%&*+./:<=>@A-Z^_a-z|~] ;
  symrest       = symchar | [0-9] ;
  ssymbol       = (symchar symrest*) @$$ ;
  sexpr         = ssymbol
                | number
                | sstring
                | "?".
                | "\""  (!"\""  char)* $:e "\""         -> e
                | "("  (sspace sexpr)*:e sspace ")"     -> e
                | "'"  sexpr:e                          -> (list 'quote e)
                | "`"  sexpr:e                          -> (list 'quasiquote e)
                | ",@" sexpr:e                          -> (list 'unquote-splicing e)
                | ","  sexpr:e                          -> (list 'unquote e)
                | "["_ expression:e "]"                 -> e
                | ";" (![\n\r] .)*
                ;

  sexpression   = sexpr:s _                             -> s ;

# ---------------- the syntax of Smalltalk programs

  blank         = [\t ] ;
  eol           = "\n""\r"* | "\r""\n"* ;
  comment       = "\""(&.!"\"".)*"\""? ;
  _             = (blank | eol | comment)* ;

  digit         = [0123456789] ;
  letter        = [ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz] ;
  binchar       = [-!%&*+,/<=>?@\\^`|~] ;

  uinteger      = digit+ $#:x _                                                 -> x ;
  integer       = "-"uinteger:x                                                 -> (- x)
                |    uinteger
                ;

  ufloat        = (digit+ "."digit+ ("e"digit+)?)@$:s _                         -> (string->double s) ;
  float         = "-"ufloat:x                                                   -> (- x)
                |    ufloat
                ;

  number        = float | integer ;

  string        = "'" ("''"->?' | !"'" char)* $:x "'" _                         -> x ;

  symbol        = "#"(idpart | binchar | ":")+ @ $$:x _                         -> `',x ;

  idpart        = (letter (letter | digit)*) @ $$ ;
  identifier    = idpart:x !":" _                                               -> x ;

  unypart       = (letter (letter | digit)*) @ $$ ;
  unysel        = unypart:x !":" _                                              -> x ;

  binpart       = binchar+ @ $$ ;
  binsel        = binpart:x _                                                   -> x ;

  keypart       = (unypart":") @ $$ ;
  keysel        = keypart:x _                                                   -> x ;

  blockargs     = (":"identifier)+:a "\|"_                                      -> a
                |                                                               -> ()
                ;

  block         = "["_ blockargs:a statements:s ("."_)* "]"_
                                    -> `(new-block ,(list-length a) (lambda ,a ,@s)) ;

  primary       = number | string | identifier | block | symbol
                | "("_ expression:e ")"_                                        -> e
                | "$".:e _                                                      -> e
                | "{"_ sexpression:e "}"_                                       -> e
                ;

  unysend       = primary:r (unysel:s -> `(send ,s ,r):r)*                      -> r ;

  binsend       = unysend:r (binsel:s unysend:a -> `(send ,s ,r ,a):r)* -> r ;

  keysend       = binsend:r ( (keysel: s binsend:a -> `(,s ,a))+:k
                                    -> `(send ,(apply concat-symbols (map car k)) ,r ,@(map cadr k))
                            |       -> r
                            ) ;

  assignment    = identifier:i ":="_ expression:e                               -> `(set ,i ,e) ;

  expression    = assignment | keysend ;

  statements    = "|"_ identifier*:i "|"_ statements:s                          -> `((let ,i ,@s))
                | expression?:e (("."_)* expression)*:f                         -> `(,@e ,@f) ;

  methodbody    = "["_ statements:s ("."_)* "]"_                                -> s
                | "{"_ sexpression*:s "}"_                                      -> s
                ;

  typename      = identifier
                | "<" identifier:i ">"_ -> (concat-symbols '< i '>)
                ;

  pattern       = unysel:s                                                      -> (list s)
                | binsel:s identifier:i                                         -> (list s i)
                | (keysel:s identifier:i -> (list s i))+:k
                                    -> (cons (apply concat-symbols (map car k)) (map cadr k))
                ;

  definition    = identifier:i ":="_
                    ( expression:e "."_                         -> (eval `(define ,i ,e))
                    | { expected "initialiser expression" }
                                     )
                | identifier:i ":"_
                    ( "("_ identifier*:f ")"_                   -> (define-topclass   i   f)
                    | identifier:b "("_ identifier*:f ")"_      -> (define-subclass   i b f)
                    | identifier:b "("_ typename:t    ")"_      -> (define-sysclass t i b  )
                    | { expected "class description" }
                    )
                | pos:s typename:t pattern:p methodbody:b {src s}:s
                                        -> (eval `(define-message ,s ,t ,(car p) ,(cdr p) ,@b))
                | expression:e "."_     -> (eval e)
                ;

  program       = _ definition* (!. | {expected "definition or expression"}) ;

# ending a grammar with an expression matches the rest of the input against that expression

  program
}

" The rest of the file is read as a Smalltalk program (see last line of grammar). "

" Enough of a class hierarchy to support BlockClosure, SmallInteger, Float, Array and String. "

Object : ()
  UndefinedObject : Object (<undefined>)
  BlockClosure : Object (<block>)
  CompiledMethod : Object (<expr>)
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

" Kernel methods for logic and evaluation of blocks "

Pepsi : Object ()

Pepsi error: message    { (error message) }

Object          yourself        [ self ]
UndefinedObject yourself        [ {()} ]

nil := UndefinedObject yourself.
false := nil.
true := #true.

Object new                      { (new (type-of self)) }

Object print                    { (print self) }
Pepsi  newline                  [ '\n' print ]
Object println                  [ self print.  Pepsi newline.  self ]

Object = other                  { (= self other) }
Object ~= other                 { (not (= self other)) }

Object          not             [ false ]
UndefinedObject not             [ true ]

Object subclassResponsibility   [ Pepsi error: 'a subclass should have overridden this message' ]

BlockClosure value                      { (block-arity self 0) ((<block>-expr self)) }
BlockClosure value: a                   { (block-arity self 1) ((<block>-expr self) a) }
BlockClosure value: a value: b          { (block-arity self 2) ((<block>-expr self) a b) }
BlockClosure value: a value: b value: c { (block-arity self 3) ((<block>-expr self) a b c) }
BlockClosure valueWithArguments: a      { (block-arity self (array-length a)) (apply (<block>-expr self) (array->list a)) }

Object          or:  aBlock             [ self ]
UndefinedObject or:  aBlock             [ aBlock value ]

Object          and: aBlock             [ aBlock value ]
UndefinedObject and: aBlock             [ self ]

BlockClosure whileTrue: b               { (while [self value] [b value]) }

Object          ifTrue: aBlock          [ aBlock value ]
UndefinedObject ifTrue: aBlock          [ self ]

Object          ifFalse: aBlock         [ self ]
UndefinedObject ifFalse: aBlock         [ aBlock value ]

Object          ifTrue: aBlock ifFalse: bBlock  [ aBlock value ]
UndefinedObject ifTrue: aBlock ifFalse: bBlock  [ bBlock value ]

Object          ifFalse: aBlock ifTrue: bBlock  [ bBlock value ]
UndefinedObject ifFalse: aBlock ifTrue: bBlock  [ aBlock value ]

" Kernel methods for numbers "

Magnitude <   other             [ self subclassResponsibility ]
Magnitude =   other             [ self subclassResponsibility ]
Magnitude <=  other             [ (other < self ) not ]
Magnitude ~=  other             [ (self = other) not ]
Magnitude >   other             [ (other < self )     ]
Magnitude >=  other             [ (self  < other) not ]

SmallInteger +  aNumber         { (+ self aNumber) }
SmallInteger -  aNumber         { (- self aNumber) }
SmallInteger *  aNumber         { (* self aNumber) }
SmallInteger // aNumber         { (/ self aNumber) }
SmallInteger \\ aNumber         { (% self aNumber) }

SmallInteger << aNumber         { (<< self aNumber) }
SmallInteger >> aNumber         { (>> self aNumber) }

SmallInteger bitAnd: aNumber    { (& self aNumber) }
SmallInteger bitOr:  aNumber    { (| self aNumber) }

SmallInteger <  aNumber         { (< self aNumber) }
SmallInteger =  aNumber         { (= self aNumber) }

SmallInteger asFloat            { (long->double self) }

Integer negated                 [ 0 - self ]

Float   asFloat                 [ self ]

Number pi                       [ 3.14159265358979323846264338327950288419716939937510820974944592 ]

Number squared                  [ self * self ]

Number sin                      [ self asFloat sin ]
Number cos                      [ self asFloat cos ]
Number log                      [ self asFloat log ]

Float sin                       { (sin self) }
Float cos                       { (cos self) }
Float log                       { (log self) }

Float +  aNumber                { (+ self aNumber) }
Float -  aNumber                { (- self aNumber) }
Float *  aNumber                { (* self aNumber) }
Float /  aNumber                { (/ self aNumber) }
Float \  aNumber                { (% self aNumber) }

Float <  aNumber                { (< self aNumber) }
Float =  aNumber                { (= self aNumber) }

Float negated                   [ 0.0 - self ]

Float truncated                 { (double->long self) }
Float rounded                   [ (self + 0.5) truncated ]

Number between: x and: y        [ x <= self and: [self <= y] ]

Number timesRepeat: aBlock
[
    [self > 0]
        whileTrue:
           [aBlock value.
            self := self - 1]
]

Number to: a do: b              [ | i | i := self.  [i <= a] whileTrue: [b value: i.  i := i + 1] ]
Number by: d to: a do: b        [ | i | i := self.  [i <= a] whileTrue: [b value: i.  i := i + d] ]
Number downTo: a do: b          [ | i | i := self.  [i >= a] whileTrue: [b value: i.  i := i - 1] ]
Number by: d downTo: a do: b    [ | i | i := self.  [i >= a] whileTrue: [b value: i.  i := i - d] ]

" Kernel methods for collections "

String size                     { (string-length self) }
String new: n                   { (string n) }
String at: n                    { (string-at self n) }
String at: n put: c             { (set-string-at self n c) }

Collection append: anObject     [ self subclassResponsibility ]

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

String toUpperCase              [ self collect: [:c | c toUpperCase] ]
String toLowerCase              [ self collect: [:c | c toLowerCase] ]

Array new: n                    { (array n) }
Array size                      { (array-length self) }
Array at: n                     { (array-at self n) }
Array at: n put: e              { (set-array-at self n e) }

Array print
[
    '#(' print.
    self do: [:elt | elt print] separatedBy: [' ' print].
    ')' print.
]

Array append: e                 [ self at: self size put: e ]


ArrayedCollection copyFrom: start to: stop
[
    | end new newSize |
    end := (stop < 0) ifTrue: [self size + stop] ifFalse: [stop].
    newSize := end - start + 1.
    new := self new: newSize.
    start to: end do: [:i | new at: i - start put: (self at: i)].
    new
]

" Kernel methods for accessing classes and methods "

Symbol asString                 { (symbol->string self) }
String asSymbol                 { (string->symbol self) }

Symbol copyFrom: start to: stop [ (self asString copyFrom: start to: stop) asSymbol ]



Object class                    { (type-of self) }
Object typeName                 { (name-of-type (type-of self)) }
Object className                [ self typeName copyFrom: 1 to: -2 ]
Object subclasses               { (list->array (array-at %pepsi-subclasses (type-of self))) }
Object instanceVariableNames    { (list->array (array-at %structure-fields (type-of self))) }

MessageSelector allSelectors    { (list->array (map cdr %pepsi-methods)) }

MessageSelector selector        [ name ]
MessageSelector methods         [ methods ]

MessageSelector isImplementedFor: anObject
[
    nil ~= (methods at: anObject class)
]

Object methodNames
[
    (MessageSelector allSelectors
        select:  [:m | m isImplementedFor: self])
        collect: [:m | m selector]
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

MessageSelector selectorNamed: sel      { (cdr (assq (concat-symbol '# sel) %pepsi-methods)) }

MessageSelector methodFor: class        { (array-at methods class) }

CompiledMethod source                   [ name ]

Object methodAt: selector
[
    | tmp |
    tmp := MessageSelector selectorNamed: selector.
    tmp methodFor: self class
]

'\nSource code for Number.timesRepeat:\n' println.
(Number methodAt: #timesRepeat:) source println.

" A non-trivial demonstration program that creates an Array of floating-point samples of a signal
  containing mixed sine waves, runs a fourier transform on the signal to extract the sine and cosine
  components at discrete frequencies, then prints a graph of the signal power at each frequency.

  [1] J. W. Cooley and J. W. Tukey, 'An algorithm for the machine calculation of complex Fourier series.'
      Mathematics of Computation, 19:297–301, 1965

  [2] G. C. Danielson and C. Lanczos, 'Some improvements in practical Fourier analysis and their
      application to X-ray scattering from liquids.'  J. Franklin Institute, 233:365–380 and 435–452, 1942
"
Array fftForwardReal
[
    | n nm1 nd2 imag pi m j |
    n     := self size.
    (n bitAnd: n - 1) = 0 ifFalse: [Pepsi error: 'FFT size is not a power of 2'].
    imag  := Array new: n withAll: 0.0.
    nm1   := n - 1.
    nd2   := n // 2.
    j     := nd2.
    " reorder input samples for an in-place FFT [1] "
    1 to: nm1 - 1 do: [ :i |
        | k |
        i < j ifTrue: [
            | tr "ti" |                         "the imaginary parts are all zero: ignore them"
            tr := self at: j.                   "ti := imag at: j."
            self at: j put: (self at: i).       "imag at: j put: (imag at: i)."
            self at: i put: tr.                 "imag at: i put: ti."
        ].
        k := nd2.
        [k <= j] whileTrue: [
            j := j - k.
            k := k // 2.
        ].
        j := j + k.
    ].
    " recombine N 1-point spectra into a single N-point spectrum [2] "
    pi := Float pi.
    m  := (n asFloat log / 2.0 log) rounded.
    1 to: m do: [ :l |                          "for each power-of-two recombination stage"
        | le le2 ur ui sr si |
        le    := 1 << l.
        le2   := le // 2.
        ur := 1.0.
        ui := 0.0.
        sr := (pi / le2 asFloat) cos.
        si := (pi / le2 asFloat) sin negated.
        1 to: le2 do: [ :j |                    "for each sub-DFT in the stage"
            | jm1 tr |
            jm1 := j - 1.
            jm1 by: le to: nm1 do: [ :i |       "for each recombined pair"
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
    " receiver contains the cosine correlations; answer the sine correlations "
    imag
]

Array fftForwardRealPowerNormalised: n
[
    | imag |
    imag := self fftForwardReal.
    0 to: self size - 1 do: [ :k |
        | r i |
        r := self at: k.
        i := imag at: k.
        self at: k put: n * (r squared + i squared).	"linear power = magnitude squared"
    ]
]

Array fftForwardRealPower
[
    self fftForwardRealPowerNormalised: (2.0 / self size asFloat) squared
]

" Plot the contents of the receiver between start and stop, with vertical scale between lo and hi.
  For each value run aBlock with three arguments: the value, and min and max limits of the current
  vertical bin in the plot.  A point is plotted in each bin for which aBlock answers true.
"
Array from: start to: stop graphFrom: lo to: hi by: aBlock labeled: label
[
    | dy dyd2 |
    lo   := lo asFloat.
    hi   := hi asFloat.
    dy   := hi - lo / 16.0.
    dyd2 := dy / 2.0.
    hi by: dy downTo: lo do: [:y |
        | z c |
        ' ' print.  y < 0 ifFalse: [' ' print].  y print.  ' |' print.
        z := 0.0 between: y - dyd2 and: y + dyd2.
        c := z ifTrue: ['-'] ifFalse: [' '].
        self from: start to: stop do: [:v |
            ((aBlock value: v value: y - dyd2 value: y + dyd2) ifTrue: ['*'] ifFalse: [c]) print].
        z ifTrue: [' ' print.  stop print.  label print].
        '' println.
    ]
]

Array from: start to: stop graphFrom: lo to: hi labeled: label
[
    self from: start to: stop graphFrom: lo to: hi
         by: [:x :l :h | x between: l and: h] labeled: label
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
          + ((twopi *  6.0 * i asFloat / fsize) sin * 0.75)
    ].
    '\ninput signal:\n' println.
    self graphFrom: -2 to: 2 labeled: ''.
    self fftForwardRealPower.
    '\ncorrelated power spectrum:\n' println.
    self from: 0 to: isize // 2 graphFrom: 0 to: 1.2
         by: [:x :l :h | x > l] labeled: ' \u0192s/N Hz'.
]

Pepsi statistics.

Array testFFT.

'\nThat''s all, folks' println.

" It may seem surprising that the basic ideas of the FFT existed so long unexploited when they could
  have been used to very great advantage.  One explanation becomes apparent when reading the works
  of Cornelius Lanczos, who described the doubling algorithm in 1942 not only for its efficiency,
  but also as a method for checking accuracy during calculation.  He later published two books on
  Fourier analysis mentioning the doubling algorithm only once (in a footnote).  The explanation
  seems to be that for the sizes of N used in those days, many other algorithms, usually using the
  symmetries and trigonometric relations of the sinusoids, were more efficient. It was only when
  electronic computers made computing with large Ws possible that the FFT became more efficient.
  Then, perhaps by chance, the 'method of subseries' went unnoticed while speeds and capacities of
  computers grew well beyond the point where the FFT could first be of value.  It makes one wonder
  if there are more gems of ideas in those old volumes left by the masters of computing in the days
  of hand calculations.
        -- Cooley & Tukey, Citation Classic Commentary, Current Contents (51-52):8-9, December 1993
"
