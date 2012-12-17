; AST node definition form

(define-function %make-field-inits (fields offset)
  (let ((init `(set (oop-at self ,offset) ,(car fields))))
    (if fields (cons init (%make-field-inits (cdr fields) (+ offset 1))))))

(define-form define-constructor (constructor-name struct-name fields)
  `(define-function ,constructor-name ,fields
     (let ((self (new ,struct-name)))
       ,@(%make-field-inits fields 0)
       self)))

(define-form define-ast-node (constructor-name fields)
  (let ((struct-name (concat-symbol '< (concat-symbol constructor-name '>))))
    `(let ()
        (define-structure                     ,struct-name ,fields)
        (define-constructor ,constructor-name ,struct-name ,fields))))

; AST node definitions

(define-ast-node nile-primtype     (name))
(define-ast-node nile-tupletype    (types))
(define-ast-node nile-recordtype   (fields))
(define-ast-node nile-processtype  (intype outtype))
(define-ast-node nile-typeref      (name))
(define-ast-node nile-typedef      (name type))
(define-ast-node nile-vardecl      (name type))
(define-ast-node nile-tuplepat     (elements))
(define-ast-node nile-numexpr      (number))
(define-ast-node nile-varexpr      (var))
(define-ast-node nile-tupleexpr    (elements))
(define-ast-node nile-condcase     (value condition))
(define-ast-node nile-condexpr     (cases otherwise))
(define-ast-node nile-field        (name type))
(define-ast-node nile-fieldexpr    (record field))
(define-ast-node nile-opexpr       (op fixity arg))
(define-ast-node nile-processinst  (process args))
(define-ast-node nile-processref   (var))
(define-ast-node nile-pipeline     (process downstream))
(define-ast-node nile-vardef       (lvalue rvalue))
(define-ast-node nile-instmt       (values))
(define-ast-node nile-outstmt      (values))
(define-ast-node nile-ifstmt       (condition tblock fblock))
(define-ast-node nile-substmt      (pipeline))
(define-ast-node nile-block        (stmts))
(define-ast-node nile-opsig        (name fixity param type))
(define-ast-node nile-opbody       (vardefs result))
(define-ast-node nile-opdef        (sig body))
(define-ast-node nile-processsig   (name params type))
(define-ast-node nile-processbody  (forpat block))
(define-ast-node nile-processdef   (sig prologue body epilogue))

; Accessor methods
; TODO get rid of delegation, have "sig" called

(define-method name     <nile-primtype>   () self.name)
(define-method name     <nile-typedef>    () self.name)
(define-method name     <nile-processdef> () (name self.sig))
(define-method name     <nile-vardecl>    () self.name)
(define-method name     <nile-field>      () self.name)
(define-method name     <nile-processsig> () self.name)
(define-method name     <nile-opsig>      () self.name)
(define-method sig      <nile-opdef>      () self.sig)
(define-method sig      <nile-processdef> () self.sig)
(define-method param    <nile-opsig>      () self.param)
(define-method params   <nile-processsig> () self.params)
(define-method params   <nile-processdef> () (params self.sig))
(define-method body     <nile-opdef>      () self.body)
(define-method elements <nile-tupleexpr>  () self.elements)
(define-method elements <nile-tuplepat>   () self.elements)
(define-method fields   <nile-recordtype> () self.fields)
(define-method types    <nile-tupletype>  () self.types)
(define-method type     <nile-typedef>    () self.type)
(define-method fixity   <nile-opsig>      () self.fixity)

; Pretty printing

(define-method print-structure <nile-primtype>   (n) (println "<nile-primtype>"))
(define-method print-structure <nile-vardecl>    (n) (print self.name":")
                                                     (print-structure self.type n))
(define-method print-structure <nile-tupletype>  (n) (print-structure self.types n))
(define-method print-structure <nile-field>      (n) (print self.name":")
                                                     (print-structure self.type n))
(define-method print-structure <nile-recordtype> (n) (print-structure self.fields n))
(define-method print-structure <nile-typeref>    (n) (print "\""self.name"\""))
(define-method print-structure <nile-numexpr>    (n) (println self.number))
(define-method print-structure <nile-varexpr>    (n) (print-structure self.var n))
(define-method print-structure <nile-tuplepat>   (n) (print-structure self.elements n))
(define-method print-structure <nile-typedef>    (n) (if (= n 0) (default-print-structure self n)
                                                                 (print self.name)))
(define-method print-structure <nile-opsig>      (n) (if (< n 2) (default-print-structure self n)
                                                                 (print self.name " ")
                                                                 (print-structure self.param n)))
(define-method print-structure <nile-opdef>      (n) (if (= n 0) (default-print-structure self n)
                                                                 (print-structure self.sig n)))
(define-method print-structure <nile-processdef> (n) (if (= n 0) (default-print-structure self n)
                                                                 (print-structure self.sig n)))

; Selector-based structure equality (maru's "equal" is not selector-based)

(define-method equal? <undefined> (other)
  (= self other))

(define-method equal? <pair> (a)
  (and (is-a? a <pair>)
       (equal? (car self) (car a))
       (equal? (cdr self) (cdr a))))

(define-method equal? <nile-field> (a)
  (and (is-a? a <nile-field>)
       (= self.name (name a))
       (equal? self.type (type a))))

(define-method equal? <nile-primtype> (a)
  (and (is-a? self <nile-primtype>) (= self.name (name a))))

(define-method equal? <nile-recordtype> (a)
  (and (is-a? a <nile-recordtype>) (equal? self.fields (fields a))))

(define-method equal? <nile-tupletype> (a)
 (and (is-a? a <nile-tupletype>) (equal? self.types (types a))))

(define-method equal? <nile-typedef> (a)
  (and (is-a? a <nile-typedef>)
       (= self.name (name a))
       (equal? self.type (type a))))

(define-method equal? <nile-processtype> (a)
  (and (is-a? a <nile-processtype>)
       (equal? self.outtype (<nile-processtype>-outtype a))
       (equal? self.intype  (<nile-processtype>-intype  a))))

; Other methods

(define nile-relational-ops (string-sort "<>≤≥≠=≈≉"))

(define-method is-infix-relational? <nile-opexpr> ()
  (and (= self.fixity 'in)
       self.op
       (string-search nile-relational-ops (string-at self.op 0))))

(define-method is-chained-relational? <nile-opexpr> ()
  (and (is-infix-relational? self)
       (is-a? (car (elements self.arg)) <nile-opexpr>)
       (is-infix-relational? (car (elements self.arg)))))

(define-method unchain-relational <nile-opexpr> ()
  (let* (((arg1  arg2) (elements self.arg))
         ((_    aarg2) (elements (<nile-opexpr>-arg arg1)))
         (arg2_        (nile-opexpr self.op self.fixity (list aarg2 arg2))))
    (nile-opexpr "∧" 'in (list arg1 arg2_))))

(define <nile-parser>)
(define-selector $juxtavars)
(define-method split-vars <nile-varexpr> ()
  (parse-string <nile-parser> $juxtavars self.var))

(define-method is-primed? <nile-vardecl> ()
  (= ?' (string-at self.name (- (string-length self.name) 1))))

(define-method unprimed-name <nile-vardecl> ()
  (string-copy self.name 0 (- (string-length self.name) 1)))

(define-method empty? <nile-block> () (= (list-length self.stmts) 0))

; No prologue means recursive process instantiation
(define-method empty? <nile-processdef> ()
  (and self.prologue (empty? self.prologue) (not self.body)))

; TODO vardecls plural means nile-vardecl should return a list
(define-method vardecls <nile-vardecl>  () (if (!= self.name "_") self))
(define-method vardecls <nile-tuplepat> () (map vardecls self.elements))
(define-method vardecls <nile-vardef>   () (vardecls self.lvalue))
(define-method vardecls <nile-block>    ()
  (let ((is-a-vardef? (lambda (s) (is-a? s <nile-vardef>))))
    (flatten (map vardecls (filter is-a-vardef? self.stmts)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; Types ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Querying the components of types

; TODO shouldn't need default implementations as much

(define-method inner-types <nile-primtype>    () '())
(define-method inner-types <nile-processtype> () '())
(define-method inner-types <nile-tupletype>   () self.types)
(define-method inner-types <nile-recordtype>  () (map type self.fields))
(define-method inner-types <nile-typedef>     () (inner-types self.type))
(define-method inner-types <undefined> () '()) ; TODO shouldn't need this

(define-method intype <nile-primtype>    () '())
(define-method intype <nile-tupletype>   () '())
(define-method intype <nile-recordtype>  () '())
(define-method intype <nile-processtype> () self.intype)
(define-method intype <nile-typedef>     () (intype self.type))

(define-method outtype <nile-primtype>    () '())
(define-method outtype <nile-tupletype>   () '())
(define-method outtype <nile-recordtype>  () '())
(define-method outtype <nile-processtype> () self.outtype)
(define-method outtype <nile-typedef>     () (outtype self.type))

(define-method get-field-by-name <nile-primtype>    (_name) '())
(define-method get-field-by-name <nile-tupletype>   (_name) '())
(define-method get-field-by-name <nile-processtype> (_name) '())
(define-method get-field-by-name <nile-typedef>     (_name) (get-field-by-name self.type _name))
(define-method get-field-by-name <nile-recordtype>  (_name)
  (list-detect field self.fields (= _name (name field))))

(define-method get-index-of-field <nile-typedef> (field)
  (get-index-of-field self.type field))

(define-method get-index-of-field <nile-recordtype> (field)
  (let ((i 0) (index 0))
    (list-do f self.fields
      (if (= f field) (set index i))
      (set i (+ i 1)))
    index))

; Calculating the type of a node

(define-method type <nile-vardecl>      () self.type)
(define-method type <nile-tuplepat>     () (nile-tupletype (map type self.elements)))
(define-method type <nile-numexpr>      () (nile-typedef "Number" (nile-primtype "Number")))
(define-method type <nile-varexpr>      () (type self.var))
(define-method type <nile-tupleexpr>    () (nile-tupletype (map type self.elements)))
(define-method type <nile-condcase>     () (type self.value))
(define-method type <nile-condexpr>     () (type (car self.cases)))
(define-method type <nile-field>        () self.type)
(define-method type <nile-fieldexpr>    () (type self.field))
(define-method type <nile-opexpr>       () (type self.op))
(define-method type <nile-processinst>  () (type self.process))
(define-method type <nile-processref>   () (type self.var))
(define-method type <nile-opsig>        () self.type)
(define-method type <nile-opbody>       () (type self.result))
(define-method type <nile-opdef>        () (type self.sig))
(define-method type <nile-processsig>   () self.type)
(define-method type <nile-processdef>   () (type self.sig))
(define-method type <nile-pipeline>     ()
  (let ((_intype  (intype  (type self.process)))
        (_outtype (outtype (type (or self.downstream self.process)))))
  (nile-processtype _intype _outtype)))

; Type compatibility

(define nile-types-compatible?)

(define-function nile-inner-types-compatible? (a b)
  (let ((atypes (inner-types a))
        (btypes (inner-types b)))
    (and (= (list-length atypes) (list-length btypes))
      (all? (map nile-types-compatible? atypes btypes)))))

(define-function nile-types-compatible? (a b)
  (if (is-a? a <nile-typedef>)
    (nile-types-compatible? (type a) b)
    (if (is-a? b <nile-typedef>)
      (nile-types-compatible? a (type b))
      (or (nile-inner-types-compatible? a b)
          (equal? a b)))))

; Abstract types

(define-method abstract? <nile-typedef>     () '())
(define-method abstract? <nile-processtype> () (or (abstract? self.intype)
                                                   (abstract? self.outtype)))
(define-method abstract? <nile-tupletype>   () (list-detect t self.types (abstract? t)))
(define-method abstract? <nile-recordtype>  () (list-detect f self.fields (abstract? (type f))))
(define-method abstract? <nile-typeref>     ()
  (let ((c (string-at self.name 0)))
    (and (= (string-length self.name) 1)
         (<= ?α c) (<= c ?ω))))

(define-method polymorphic? <nile-processdef>  () (polymorphic? self.sig))
(define-method polymorphic? <nile-processsig>  () (or (list-detect p self.params (polymorphic? p))
                                                      (abstract? self.type)))
(define-method polymorphic? <nile-vardecl>     () (abstract? self.type))

; Type-based operation matching

(define-method match? <nile-opsig> (name fixity param-type)
  (and (= self.name name)
       (= self.fixity fixity)
       (equal? (type self.param) param-type)))

; TODO rename these
(define-method csize <nile-primtype>    () 1)
(define-method csize <nile-processtype> () 1)
(define-method csize <nile-field>       () (csize self.type))
(define-method csize <nile-recordtype>  () (foldr + 0 (map csize self.fields)))
(define-method csize <nile-tupletype>   () (foldr + 0 (map csize self.types)))
(define-method csize <nile-typedef>     () (csize self.type))
