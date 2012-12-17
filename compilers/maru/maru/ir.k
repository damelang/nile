;;; TODO
;;;
;;; emitter trie: ir-insn x operands... -> (lambda (ir operands) ...)

(require "scope.k")
(require "trie.k")

(define-structure <ir-type> (name size alignment pointer))

(define-function ir-type-size (self)		(<ir-type>-size	     self))
(define-function ir-type-alignment (self)	(<ir-type>-alignment self))

(define-method do-print <ir-type> ()	(print "<ir-type "self.name">")
					;;(print self.name)
					)

(define-class <ir-void-type> <ir-type> ())
(define-class <ir-scalar-type> <ir-type> ())				(define-function ir-scalar-type? (x)	(inherits-from (type-of x) <ir-scalar-type>))
(define-class <ir-pointer-type> <ir-scalar-type> (referent))		(define-function ir-pointer-type? (x)	(inherits-from (type-of x) <ir-pointer-type>))
(define-class <ir-numeric-type> <ir-scalar-type> ())			(define-function ir-numeric-type? (x)	(inherits-from (type-of x) <ir-numeric-type>))
(define-class <ir-integral-type> <ir-numeric-type> ())			(define-function ir-integral-type? (x)	(inherits-from (type-of x) <ir-integral-type>))
(define-class <ir-floating-type> <ir-numeric-type> ())			(define-function ir-floating-type? (x)	(inherits-from (type-of x) <ir-floating-type>))
(define-class <ir-varargs-type> <ir-type> ())

(define IR-VOID		(new <ir-void-type>	'void	 0 1))
(define IR-INT8		(new <ir-integral-type> 'uint8_t 1 1))
(define IR-INT16	(new <ir-integral-type> 'int16_t 2 2))
(define IR-INT32	(new <ir-integral-type> 'int32_t 4 4))
(define IR-INT64	(new <ir-integral-type> 'int64_t 8 8))
(define IR-FLOAT32	(new <ir-integral-type> 'float	 4 4))
(define IR-FLOAT64	(new <ir-integral-type> 'double	 8 8))
(define IR-VARARGS	(new <ir-varargs-type>  '...	 0 0))

(define IR-INT		IR-INT32)
(define IR-LONG		IR-INT32)
(define IR-FLOAT	IR-FLOAT32)

(define-function ir-pointer-type-name (type)	(concat-symbol (<ir-type>-name type) '*))

(define-function ir-pointer-to (type)
  (or (<ir-type>-pointer type)
      (set (<ir-type>-pointer type)
	   (new <ir-pointer-type> (ir-pointer-type-name type) (<ir-type>-size IR-LONG) (<ir-type>-alignment IR-LONG) () type))))

(define IR-STRING	(ir-pointer-to IR-INT8))
(define IR-BOOL		IR-INT)

(define-structure <ir-variable> (name type))

(define-method do-print <ir-variable> ()	(print "<"(type-name-of self)" "self.name" : "self.type">"))

(define-class <ir-extern>   <ir-variable> ())
(define-class <ir-function> <ir-variable> ())
(define-class <ir-global>   <ir-variable> ())
(define-class <ir-local>    <ir-variable> (offset))
(define-class <ir-param>    <ir-variable> (offset))

(define-structure <ir-insn> (parameters operands type))

(define-function ir-insn-print (self level)
  (with-instance-accessors <ir-insn>
    (for (i 0 level) (print "  "))
    (print "{ "(type-name-of self))
    (when self.parameters (print " ") (dump self.parameters))
    (when self.type (print" : "self.type))
    (list-do operand self.operands (println) (ir-insn-print operand (+ level 1)))
    (print " }")))

(define-method do-print <ir-insn> ()	(ir-insn-print self 0))

(define-function ir-param-type (self)	(<ir-param>-type self))

(define-method ir-cvt-type <ir-type> ()		self)
(define-method ir-cvt-type <ir-pointer-type> ()	<ir-pointer-type>)

;;; IR

(define *temp-name-index* 0)

(define-structure <ir> (scope globals function program cvt-table function-types structure-types))

(define-function ir-new (ir-type scope)
  (let ((self (new ir-type)))
    (with-instance-accessors <ir>
      (set self.scope		(or scope (scope-new ())))
      (set self.globals		scope)
      (set self.program		(array))
      (set self.function-types	(trie-new)))
    self))

(define-function temp-name ()		(string->symbol (concat-string "__" (format "%05d" (incr *temp-name-index*)))))

(define-function ir-dump (self)
  (with-instance-accessors <ir>
    (array-do insn self.program
      (println insn))))

(define-function ir-declare (self name type . options)
  (with-instance-accessors <ir>
    (scope-define self.scope name (new (or (car options) <ir-global>) name type))))

(define-function ir-lookup (self name)
  (with-instance-accessors <ir>
    (cdr (or (scope-lookup self.scope name)
	     (error "undefined variable: "name)))))

(define-function ir-begin-scope (self)			(with-instance-accessors <ir> (set self.scope (scope-new self.scope))))
(define-function ir-end-scope (self scope)		(with-instance-accessors <ir> (set self.scope scope)))

(define-function ir-begin-function-scope (self fn)	(with-instance-accessors <ir> (set self.function fn) (set self.scope (scope-new self.scope))))
(define-function ir-end-function-scope (self scope)	(with-instance-accessors <ir> (set self.function ()) (set self.scope scope)))

;;; fuctions

(define-class <ir-function-type> <ir-type> (ret-type arg-types))	(define-function ir-function-type? (x)	(inherits-from (type-of x) <ir-function-type>))

(define-function ir-function-type-name (ret-type arg-types)
  (let ((name "("))
    (list-do arg-type arg-types
      (set name (concat-string name (symbol->string (<ir-type>-name arg-type))))
      (set name (concat-string name " ")))
    (set name (concat-string name "-> "))
    (set name (concat-string name (symbol->string (<ir-type>-name ret-type))))
    (set name (concat-string name ")"))
    name))

(define-function ir-function-type (ir ret-type param-types)
  (let* ((proto (cons ret-type param-types)))
    (or (trie-at (<ir>-function-types ir) proto)
	(set-trie-at (<ir>-function-types ir) proto
		     (new <ir-function-type>
			  (ir-function-type-name ret-type param-types)
			  0 0 () ret-type param-types)))))

;;; structure

(define-function c-mangle (s)
  (let* ((in  (symbol->string s))
	 (len (string-length in))
	 (out (array)))
    (for (i 0 len)
      (let ((c (string-at in i)))
	(if (or (and (<= 0x61 c) (<= c 0x7a))
		(and (<= 0x40 c) (<= c 0x5a))
		(and (<= 0x30 c) (<= c 0x39)))
	    (array-append out c)
	  (if (= ?_ c)
	      (array-append-all out "__")
	    (array-append-all out (format "_%02x" c))))))
    (array->string out)))

(define-function align (offset alignment)	(& (+ offset (- alignment 1)) (- alignment)))

(define-structure <ir-struct-member> (name type offset))

(define-function ir-struct-member-type (self)	(<ir-struct-member>-type self))

(define-method do-print <ir-struct-member> ()	(print self.offset"."self.name":"self.type))

(define-class <ir-struct-type> <ir-type> (members))		(define-function ir-struct-type? (x)	(inherits-from (type-of x) <ir-struct-type>))

(define-function ir-struct-make-typed-members (type names rest)
  (if (pair? names)
      (cons (new <ir-struct-member> (car names) type 0)
	    (ir-struct-make-typed-members type (cdr names) rest))
    rest))

(define-function ir-struct-make-members (members)
  (and (pair? members)
       (ir-struct-make-typed-members (caar members) (cdar members)
				     (ir-struct-make-members (cdr members)))))

(define-function ir-struct-add-member-offsets (size members)
  (list-do member members
    (let* ((type   (<ir-struct-member>-type member))
	   (offset (align size (<ir-type>-alignment type))))
      (set (<ir-struct-member>-offset member) offset)
      (set size (+ offset (<ir-type>-size type)))))
  size)

(define-function ir-make-struct-type (name members)
  (make <ir-struct-type>
	(name      name)
	(members   (ir-struct-make-members members))
	(size      (ir-struct-add-member-offsets 0 self.members))
	(alignment (and members (apply max (map ir-type-alignment (map car members)))))))

(define-function ir-struct-type-member-named (self name)
  (list-detect member (<ir-struct-type>-members self)
	       (= name (<ir-struct-member>-name member))))

(define-function ir-def-struct (ir name members)
  (let ((type (ir-make-struct-type name members))
	(prev (assq name (<ir>-structure-types ir))))
    (if prev
	(if (<ir-struct-type>-alignment (cdr prev))
	    (error "structure already defined: "name)
	  (set-cdr prev type))
      (push (<ir>-structure-types ir) (cons name type)))))

(define-function ir-struct-type (ir name)
  (cdr (or (assq name (<ir>-structure-types ir))
	   (car (ir-def-struct ir name ())))))

(define-selector ir-gen-c-decl)

(define-method ir-gen-c-declaration <ir-struct-type> ()
  (println "struct "(c-mangle self.name)" {")
  (list-do member self.members
    (ir-gen-c-decl (<ir-struct-member>-type member) (<ir-struct-member>-name member))
    (println ";")
    ;;(println (<ir-type>-name (<ir-struct-member>-type member))" "(<ir-struct-member>-name member)";")
    )
  (println "};"))

;;; instructions

(define-function insn (type . operands)		(new type () operands))
(define-function leaf (type . parameters)	(new type parameters))

(define-method ir-gen-c <long> (ir)		(print self))
(define-method ir-gen-c <double> (ir)		(print self))
(define-method ir-gen-c <string> (ir)		(print "((unsigned char *)") (dump  self) (print ")"))
(define-method ir-gen-c <ir-extern> (ir)	(print self.name))
(define-method ir-gen-c <ir-function> (ir)	(print self.name))
(define-method ir-gen-c <ir-global> (ir)	(print self.name))
(define-method ir-gen-c <ir-local> (ir)		(print self.name))
(define-method ir-gen-c <ir-param> (ir)		(print self.name))

(define-function ir-local (self name type)
  (with-instance-accessors <ir>
    ;;(println "IR LOCAL "name" : "type)
    (scope-define self.scope name (new <ir-local> name type))))

(define ir-fun-param)	;; forward
(define ir-fun-return)	;; forward
(define ir-put)		;; forward
(define ir-typecheck)	;; forward
(define ir-gen)		;; forward

(define-function ir-param (self name type)
  (with-instance-accessors <ir>
    (let ((param (new <ir-param> name type)))
      (scope-define self.scope name param)
      (ir-fun-param self.function param))))

(define-function ir-check-return (self ret)
  (with-instance-accessors <ir>
    (or self.function (error "return outside function definition"))
    (ir-fun-return self.function ret)))

(define-function ir-gen-c-name (name)			(print name))

(define-method ir-gen-c-decl <ir-type> (name)		(print self.name" ") (ir-gen-c-name name))
(define-method ir-gen-c-decl <ir-pointer-type> (name)	(ir-gen-c-decl self.referent (concat-symbol '* name)))

(define-method ir-gen-c-decl <ir-function-type> (name)
  (print (<ir-type>-name self.ret-type)"("name")(")
  (and self.arg-types (print (<ir-type>-name (car self.arg-types))))
  (list-do arg-type (cdr self.arg-types) (print ", "(<ir-type>-name arg-type)))
  (print")"))

(define-method ir-gen-c-decl <ir-struct-type> (name)	(print "struct "(c-mangle self.name)" "name))

(define-method ir-gen-c-parameter <ir-variable> ()	)
(define-method ir-gen-c-parameter <ir-param> ()		(ir-gen-c-decl self.type (symbol->string self.name)))

(define-method ir-gen-c-definition <ir-param> ()	)
(define-method ir-gen-c-definition <ir-extern> ()	)
(define-method ir-gen-c-definition <ir-function> ()	)
(define-method ir-gen-c-definition <ir-variable> ()	(ir-gen-c-decl self.type (symbol->string self.name)) (println ";"))


(define-method ir-check-type <long> (ir)	IR-INT)
(define-method ir-check-type <double> (ir)	IR-FLOAT)
(define-method ir-check-type <string> (ir)	IR-STRING)


(define-class <ir-lit> <ir-insn> ())		(define-function ir-lit (value . opt-type) (leaf <ir-lit> value (car opt-type)))

(define-function ir-lit? (x)			(inherits-from (type-of x) <ir-lit>))
(define-function ir-zero? (x)			(and (ir-lit? x) (= 0 (car (<ir-lit>-parameters x)))))

(define-method ir-check-type <ir-lit> (ir)	(set self.type (or (cadr self.parameters) (ir-check-type (car self.parameters) ir))))

(define-method ir-gen-c <ir-lit> (ir)		(ir-gen-c (car self.parameters) ir))


(define-class <ir-get-var> <ir-insn> ())

(define-method ir-check-type <ir-get-var> (ir)	(set self.parameters (ir-lookup ir self.parameters))
						(set self.type (<ir-variable>-type self.parameters))
						(and (ir-function-type? self.type) (set self.type (ir-pointer-to self.type)))
						self.type)

(define-method ir-gen-c <ir-get-var> (ir)	(ir-gen-c self.parameters ir))


(define-class <ir-get-ptr> <ir-insn> ())

(define-method ir-check-type <ir-get-ptr> (ir)	(let ((type (ir-check-type (car self.operands) ir)))
						  (or (ir-pointer-type? type) (error "dereferencing a non-pointer: "self))
						  (set self.type (<ir-pointer-type>-referent type)))
						(cond
						  ((and (ir-integral-type? self.type)
							(!= IR-INT64 self.type))	(set self.type IR-INT))
						  ((ir-function-type? self.type)	(error "cannot derefernce a pointer to function: "self)))
						self.type)

(define-method ir-gen-c <ir-get-ptr> (ir)	(print "*")  (ir-gen-c (car self.operands) ir))


(define-function ir-get (exp)			(if (symbol? exp) (new <ir-get-var> exp) (new <ir-get-ptr> () (list exp))))


(define-class <ir-set-var> <ir-insn> ())

(define-method ir-check-type <ir-set-var> (ir)	(set self.parameters (ir-lookup ir self.parameters))
						(let ((type (ir-check-type (car self.operands) ir)))
						  (or (<ir-variable>-type self.parameters)
						      (set (<ir-variable>-type self.parameters) type))
						  (set self.type (<ir-variable>-type self.parameters))
						  (or (= self.type type)
						      (and (ir-pointer-type? self.type)
							   (ir-zero? (car self.operands)))
						      (error "type mismatch in assignment: "self)))
						self.type)

(define-method ir-gen-c <ir-set-var> (ir)	(print "(")  (ir-gen-c self.parameters ir)  (print "=")  (ir-gen-c (car self.operands) ir)  (print ")"))


(define-class <ir-set-ptr> <ir-insn> ())

(define-method ir-check-type <ir-set-ptr> (ir)	(let ((type (ir-check-type (car self.operands) ir)))
						  (set self.type (ir-check-type (cadr self.operands) ir))
						  (or (ir-pointer-type? type) (error "storing through a non-pointer: "self))
						  (set type (<ir-pointer-type>-referent type))
						  (or (and (ir-integral-type? self.type) (ir-integral-type? type))
						      (=                      self.type                     type )
						      (error "type mismatch in assignment: "self)))
						self.type)

(define-method ir-gen-c <ir-set-ptr> (ir)	(print "(*")  (ir-gen-c (car self.operands) ir)  (print "=")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-function ir-set (exp val)		(if (symbol? exp) (new <ir-set-var> exp (list val)) (new <ir-set-ptr> () (list exp val))))


(define-class <ir-neg> <ir-insn> ())		(define-function ir-neg (a) (insn <ir-neg> a))

(define-method ir-check-type <ir-neg> (ir)	(set self.type (ir-check-type (car self.operands) ir))
						(or (ir-numeric-type? self.type) (error "non-numeric operand: "self))
						self.type)

(define-method ir-gen-c <ir-neg> (ir)		(print "-")  (ir-gen-c (car self.operands) ir))


(define-class <ir-com> <ir-insn> ())		(define-function ir-com (a) (insn <ir-com> a))

(define-method ir-check-type <ir-com> (ir)	(set self.type (ir-check-type (car self.operands) ir))
						(or (ir-integral-type? self.type) (error "non-integral operand: "self))
						self.type)

(define-method ir-gen-c <ir-com> (ir)		(print "~")  (ir-gen-c (car self.operands) ir))


(define-class <ir-not> <ir-insn> ())		(define-function ir-not (a) (insn <ir-not> a))

(define-method ir-check-type <ir-not> (ir)	(set self.type (ir-check-type (car self.operands) ir))
						(or (ir-integral-type? self.type) (error "non-integral operand: "self))
						self.type)

(define-method ir-gen-c <ir-not> (ir)		(print "!")  (ir-gen-c (car self.operands) ir))


(define-class <ir-add> <ir-insn> ())		(define-function ir-add (a b) (insn <ir-add> a b))

(define-method ir-check-type <ir-add> (ir)	(let ((lhs (ir-check-type (car  self.operands) ir))
						      (rhs (ir-check-type (cadr self.operands) ir)))
						  (or (and (ir-numeric-type? lhs) (= rhs lhs))
						      (and (ir-pointer-type? lhs) (= rhs IR-LONG))
						      (error "type mismatch: "self))
						  (set self.type lhs)))

(define-method ir-gen-c <ir-add> (ir)		(print "(")  (ir-gen-c (car self.operands) ir)  (print "+")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-class <ir-sub> <ir-insn> ())		(define-function ir-sub (a b)	(insn <ir-sub> a b))

(define-method ir-check-type <ir-sub> (ir)	(let ((lhs (ir-check-type (car  self.operands) ir))
						      (rhs (ir-check-type (cadr self.operands) ir)))
						  (or (and (ir-numeric-type? lhs) (= rhs lhs))
						      (and (ir-pointer-type? lhs) (= rhs lhs))
						      (and (ir-pointer-type? lhs) (= rhs IR-LONG))
						      (error "type mismatch: "self))
						  (set self.type lhs)))

(define-method ir-gen-c <ir-sub> (ir)		(print "(")  (ir-gen-c (car self.operands) ir)  (print "-")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-function ir-check-binary-arithmetic-type (self ir)
  (with-instance-accessors <ir-insn>
    (let ((lhs (ir-check-type (car  self.operands) ir))
	  (rhs (ir-check-type (cadr self.operands) ir)))
      (or (and (ir-numeric-type? lhs) (= rhs lhs))
	  (error "type mismatch: "self))
      (set self.type lhs))))


(define-class <ir-mul> <ir-insn> ())		(define-function ir-mul (a b) (insn <ir-mul> a b))
(define-method ir-check-type <ir-mul> (ir)	(ir-check-binary-arithmetic-type self ir))
(define-method ir-gen-c <ir-mul> (ir)		(print "(")  (ir-gen-c (car self.operands) ir)  (print "*")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-class <ir-div> <ir-insn> ())		(define-function ir-div (a b) (insn <ir-div> a b))
(define-method ir-check-type <ir-div> (ir)	(ir-check-binary-arithmetic-type self ir))
(define-method ir-gen-c <ir-div> (ir)		(print "(")  (ir-gen-c (car self.operands) ir)  (print "/")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-class <ir-mod> <ir-insn> ())		(define-function ir-mod (a b) (insn <ir-mod> a b))
(define-method ir-check-type <ir-mod> (ir)	(ir-check-binary-arithmetic-type self ir))
(define-method ir-gen-c <ir-mod> (ir)		(print "(")  (ir-gen-c (car self.operands) ir)  (print "%")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-function ir-check-shift-type (self ir)
  (with-instance-accessors <ir-insn>
    (let ((lhs (ir-check-type (car  self.operands) ir))
	  (rhs (ir-check-type (cadr self.operands) ir)))
      (or (ir-integral-type? lhs)	(error "shifted value is not an integer: "self))
      (or (= rhs IR-INT)		(error "shift amount is not an integer: "self))
      (set self.type lhs))))


(define-class <ir-shl> <ir-insn> ())		(define-function ir-shl (a b) (insn <ir-shl> a b))
(define-method ir-check-type <ir-shl> (ir)	(ir-check-shift-type self ir))
(define-method ir-gen-c <ir-shl> (ir)		(print "(")  (ir-gen-c (car self.operands) ir)  (print "<<")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-class <ir-shr> <ir-insn> ())		(define-function ir-shr (a b) (insn <ir-shr> a b))
(define-method ir-check-type <ir-shr> (ir)	(ir-check-shift-type self ir))
(define-method ir-gen-c <ir-shr> (ir)		(print "(")  (ir-gen-c (car self.operands) ir)  (print ">>")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-function ir-check-bitwise-type (self ir)
  (with-instance-accessors <ir-insn>
    (let ((lhs (ir-check-type (car  self.operands) ir))
	  (rhs (ir-check-type (cadr self.operands) ir)))
      (or (and (ir-integral-type? lhs) (= rhs lhs))
	  (error "type mismatch: "self))
      (set self.type lhs))))


(define-class <ir-bitand> <ir-insn> ())		(define-function ir-bitand (a b) (insn <ir-bitand> a b))
(define-method ir-check-type <ir-bitand> (ir)	(ir-check-bitwise-type self ir))
(define-method ir-gen-c <ir-bitand> (ir)	(print "(")  (ir-gen-c (car self.operands) ir)  (print "&")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-class <ir-bitor> <ir-insn> ())		(define-function ir-bitor (a b) (insn <ir-bitor> a b))
(define-method ir-check-type <ir-bitor> (ir)	(ir-check-bitwise-type self ir))
(define-method ir-gen-c <ir-bitor> (ir)		(print "(")  (ir-gen-c (car self.operands) ir)  (print "|")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-class <ir-bitxor> <ir-insn> ())		(define-function ir-bitxor (a b) (insn <ir-bitxor> a b))
(define-method ir-check-type <ir-bitxor> (ir)	(ir-check-bitwise-type self ir))
(define-method ir-gen-c <ir-bitxor> (ir)	(print "(")  (ir-gen-c (car self.operands) ir)  (print "^")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-function ir-check-relation-type (self ir)
  (with-instance-accessors <ir-insn>
    (let ((lhs (ir-check-type (car  self.operands) ir))
	  (rhs (ir-check-type (cadr self.operands) ir)))
      (or (and (ir-numeric-type? lhs) (= rhs lhs))
	  (and (ir-pointer-type? lhs) (= rhs lhs))
	  (error "type mismatch: "self))
      (set self.type IR-BOOL))))


(define-class <ir-lt> <ir-insn> ())		(define-function ir-lt (a b)	(insn <ir-lt> a b))
(define-method ir-check-type <ir-lt> (ir)	(ir-check-relation-type self ir))
(define-method ir-gen-c <ir-lt> (ir)		(print "(")  (ir-gen-c (car self.operands) ir)  (print "<")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-class <ir-le> <ir-insn> ())		(define-function ir-le (a b) (insn <ir-le> a b))
(define-method ir-check-type <ir-le> (ir)	(ir-check-relation-type self ir))
(define-method ir-gen-c <ir-le> (ir)		(print "(")  (ir-gen-c (car self.operands) ir)  (print "<=")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-class <ir-eq> <ir-insn> ())		(define-function ir-eq (a b) (insn <ir-eq> a b))
(define-method ir-check-type <ir-eq> (ir)	(ir-check-relation-type self ir))
(define-method ir-gen-c <ir-eq> (ir)		(print "(")  (ir-gen-c (car self.operands) ir)  (print "==")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-class <ir-ne> <ir-insn> ())		(define-function ir-ne (a b) (insn <ir-ne> a b))
(define-method ir-check-type <ir-ne> (ir)	(ir-check-relation-type self ir))
(define-method ir-gen-c <ir-ne> (ir)		(print "(")  (ir-gen-c (car self.operands) ir)  (print "!=")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-class <ir-ge> <ir-insn> ())		(define-function ir-ge (a b) (insn <ir-ge> a b))
(define-method ir-check-type <ir-ge> (ir)	(ir-check-relation-type self ir))
(define-method ir-gen-c <ir-ge> (ir)		(print "(")  (ir-gen-c (car self.operands) ir)  (print ">=")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-class <ir-gt> <ir-insn> ())		(define-function ir-gt (a b) (insn <ir-gt> a b))
(define-method ir-check-type <ir-gt> (ir)	(ir-check-relation-type self ir))
(define-method ir-gen-c <ir-gt> (ir)		(print "(")  (ir-gen-c (car self.operands) ir)  (print ">")  (ir-gen-c (cadr self.operands) ir)  (print ")"))


(define-function ir-check-logical-type (self ir)
  (with-instance-accessors <ir-insn>
    (list-do operand self.operands
      (or (= IR-BOOL (ir-check-type operand ir))
	  (error "non-bool type in logical operator: "self))
      (set self.type IR-BOOL))))


(define-class <ir-logand> <ir-insn> ())		(define-function ir-logand (a b) (insn <ir-logand> a b))
(define-method ir-check-type <ir-logand> (ir)	(ir-check-logical-type self ir))
(define-method ir-gen-c <ir-logand> (ir)	(print "(")  (ir-gen-c (car self.operands) ir)
						(list-do operand (cdr self.operands) (print "&&")  (ir-gen-c operand ir))
						(print ")"))


(define-class <ir-logor> <ir-insn> ())		(define-function ir-logor (a b) (insn <ir-logor> a b))
(define-method ir-check-type <ir-logor> (ir)	(ir-check-logical-type self ir))
(define-method ir-gen-c <ir-logor> (ir)		(print "(")  (ir-gen-c (car self.operands) ir)
						(list-do operand (cdr self.operands) (print "||")  (ir-gen-c operand ir))
						(print ")"))


(define-class <ir-seq> <ir-insn> ())		(define-function ir-seq exprs (new <ir-seq> () exprs))

(define-method ir-check-type <ir-seq> (ir)	(or self.operands (set self.operands (list (leaf <ir-lit> 0))))
						(set self.parameters (ir-begin-scope ir))
						(list-do operand self.operands (set self.type (ir-check-type operand ir)))
						(ir-end-scope ir self.parameters)
						self.type)

(define-method ir-gen-c <ir-seq> (ir)		(println "({")
						(list-do var (<scope>-bindings self.parameters) (ir-gen-c-definition (cdr var)))
						(list-do operand self.operands
						  (ir-gen-c operand ir)
						  (println ";"))
						(print "})"))


(define-class <ir-ret> <ir-insn> ())		(define-function ir-ret (val) (insn <ir-ret> val))

(define-method ir-check-type <ir-ret> (ir)	(set self.type
						     (if self.operands
							 (ir-check-type (car self.operands) ir)
						       IR-VOID))
						(ir-check-return ir self)
						self.type)

(define-method ir-gen-c <ir-ret> (ir)		(if self.operands
						    (let ()
						      (print "return ")
						      (ir-gen-c (car self.operands) ir))
						  (print "return")))


(define-class <ir-imp> <ir-insn> (name scope ret-type))

(define-function ir-imp (name type body) (make <ir-imp> (name name) (operands body) (type type)))

(define-method ir-check-type <ir-imp> (ir)	(set self.scope (ir-begin-function-scope ir self))
						(map-with ir-check-type self.operands ir)
						(ir-end-function-scope ir self.scope)
						(or self.ret-type (set self.ret-type IR-VOID))
						(set self.parameters (list-reverse! self.parameters))
						(let ((arg-types (map ir-param-type self.parameters)))
						  (if self.type
						      (let ()
							(or (equal self.ret-type (<ir-function-type>-ret-type self.type))
							    (error "return type mismatch: "self.ret-type" in: "self))
							(or (equal arg-types (<ir-function-type>-arg-types self.type))
							    (error "argument type mismatch: "self)))
						    (set self.type (ir-function-type ir self.ret-type arg-types))))
						self.type)

(define-function ir-fun-param (self param)	(push (<ir-imp>-parameters self) param))

(define-function ir-fun-return (self ret)	(with-instance-accessors <ir-imp>
						  (if self.ret-type
						      (or (= self.ret-type (<ir-ret>-type ret))
							  (error "return type mismatch: "(<ir-ret>-type ret)" in: "self))
						    (set self.ret-type (<ir-ret>-type ret)))))

(define-method ir-gen-c <ir-imp> (ir)		(let ((params self.parameters))
						  (print (<ir-type>-name (<ir-function-type>-ret-type self.type)))
						  (print " "self.name"(")
						  (and params (ir-gen-c-parameter (car params)))
						  (list-do param (cdr params) (print ", ") (ir-gen-c-parameter param))
						  (println ") {")
						  (alist-do var (<scope>-bindings self.scope) (ir-gen-c-definition var))
						  (list-do operand self.operands (ir-gen-c operand ir) (println ";"))
						  (println "}")))


(define-class <ir-fun> <ir-insn> ())		(define-function ir-fun (name type body) (new <ir-fun> name (list (ir-imp (or name (temp-name)) type body))))

(define-method ir-check-type <ir-fun> (ir)	(let* ((imp (car self.operands))
						       (var (and self.parameters (ir-declare ir self.parameters (<ir-insn>-type imp) <ir-function>)))
						       (fir (ir-new (type-of ir) (<ir>-scope ir))))
						  (ir-put fir imp)
						  ;; recursive generation of function implementation
						  (ir-typecheck fir)
						  (alist-do var (<scope>-bindings (<ir>-scope fir)) (ir-gen-c-definition var))
						  (array-do insn (<ir>-program fir)
						    (ir-gen-c insn fir)
						    (println ";"))
						  ;; back in enclosing
						  (let ((type (<ir-insn>-type imp)))
						    (and var (set (<ir-variable>-type (cdr var)) type))
						    (set self.type (ir-pointer-to type)))))

(define-method ir-gen-c <ir-fun> (ir)		(print "&"(<ir-imp>-name (car self.operands))))


(define-class <ir-arg> <ir-insn> ())		(define-function ir-arg (name type) (new <ir-arg> (list name type)))

(define-method ir-check-type <ir-arg> (ir)	(let ((name (car  self.parameters))
						      (type (cadr self.parameters)))
						  (ir-param ir name type)
						  (set self.type type)))

(define-method ir-gen-c <ir-arg> (ir)		)


(define-class <ir-var> <ir-insn> ())		(define-function ir-var (name type value) (new <ir-var> (list name type) (list value)))

(define-method ir-check-type <ir-var> (ir)	(let ((name (car  self.parameters))
						      (type (cadr self.parameters))
						      (init (car  self.operands)))
						  (ir-local ir name type)
						  (set-car self.operands (ir-set name init))
						  (set self.type (ir-check-type (car self.operands) ir))))

(define-method ir-gen-c <ir-var> (ir)		(ir-gen-c (car self.operands) ir))


(define-class <ir-ife> <ir-insn> ())		(define-function ir-ife (test consequent alternate)	(insn <ir-ife> test consequent alternate))

(define-method ir-check-type <ir-ife> (ir)	(or (= IR-BOOL   (ir-check-type (car   self.operands) ir))	(error "non-integral condition: "self))
						(set   self.type (ir-check-type (cadr  self.operands) ir))
						(or (= self.type (ir-check-type (caddr self.operands) ir))	(error "type mismatch: "self))
						self.type)

(define-method ir-gen-c <ir-ife> (ir)		(print "(")  (ir-gen-c (car   self.operands) ir)
						(print "?")  (ir-gen-c (cadr  self.operands) ir)
						(print ":")  (ir-gen-c (caddr self.operands) ir)  (print ")"))


(define-class <ir-ifs> <ir-insn> ())		(define-function ir-ifs (test consequent . alternate)	(insn <ir-ifs> test consequent (car alternate)))

(define-method ir-check-type <ir-ifs> (ir)	(or (= IR-BOOL   (ir-check-type (car   self.operands) ir))	(error "non-integral condition: "self))
						(ir-check-type (cadr  self.operands) ir)
						(and (caddr self.operands) (ir-check-type (caddr self.operands) ir))
						(set self.type IR-VOID))

(define-method ir-gen-c <ir-ifs> (ir)		(print "if (")      (ir-gen-c (car   self.operands) ir)  (println ")")
						(print "{ ")        (ir-gen-c (cadr  self.operands) ir)  (println ";}")
						(when (caddr self.operands)
						  (print "else {")  (ir-gen-c (caddr self.operands) ir)  (println ";}")))


(define-class <ir-while> <ir-insn> ())		(define-function ir-while test-exprs (new <ir-while> () test-exprs))

(define-method ir-check-type <ir-while> (ir)	(or (= IR-BOOL (ir-check-type (car self.operands) ir)) (error "non-integral condition: "self))
						(map-with ir-check-type (cdr self.operands) ir)
						(set self.type IR-VOID))

(define-method ir-gen-c <ir-while> (ir)		(print "while (")  (ir-gen-c (car self.operands) ir)  (println ") {")
						(list-do stmt (cdr self.operands)
						  (ir-gen-c stmt ir)
						  (println ";"))
						(println "}"))


(define-class <ir-cvt> <ir-insn> ())		(define-function ir-cvt (type value) (new <ir-cvt> type (list value)))

(define-method ir-check-type <ir-cvt> (ir)	(set self.type (ir-check-type (car self.operands) ir)))

(define-method ir-gen-c <ir-cvt> (ir)		(let* ((src self.type)		(s   (ir-cvt-type src))
						       (dst self.parameters)	(d   (ir-cvt-type dst)))
						  (if (or (and (= s IR-INT32  	     ) (= d IR-INT64  	     ))
							  (and (= s IR-INT64  	     ) (= d IR-INT32  	     ))
							  (and (= s <ir-pointer-type>) (= d IR-LONG   	     ))
							  (and (= s IR-LONG   	     ) (= d <ir-pointer-type>))
							  (and (= s IR-FLOAT32	     ) (= d IR-FLOAT64	     ))
							  (and (= s IR-FLOAT64	     ) (= d IR-FLOAT32	     ))
							  (and (= s IR-FLOAT32	     ) (= d IR-INT32  	     ))
							  (and (= s IR-FLOAT64	     ) (= d IR-INT64  	     ))
							  (and (= s IR-INT32  	     ) (= d IR-FLOAT32	     ))
							  (and (= s IR-INT64  	     ) (= d IR-FLOAT64	     )))
						      (let ()
							(print "("dst")(")
							(ir-gen-c (car self.operands) ir)
							(print ")"))
						    (error "cannot convert: "self))))


(define-class <ir-def> <ir-insn> ())		(define-function ir-def (name type value) (new <ir-def> (list name type) (ir-set name value)))

(define-method ir-check-type <ir-def> (ir)	(let* ((name (car  self.parameters))
						       (type (cadr self.parameters))
						       (init self.operands)
						       (decl (ir-declare ir name type)))
						  (set self.type (ir-check-type init ir))
						  (or (= self.type (<ir-variable>-type (cdr decl)))
						      (error "ir-set failed to propagate the initial type of a definition"))
						  self.type))

(define-method ir-gen-c <ir-def> (ir)		(ir-gen-c self.operands ir))


(define-class <ir-ext> <ir-insn> (header))	(define-function ir-ext (name type . header)
						  (make <ir-ext>
							(parameters (list name type))
							(header (car header))))

(define-method ir-check-type <ir-ext> (ir)	(let ((name (car  self.parameters))
						      (type (cadr self.parameters)))
						  (ir-declare ir name type <ir-extern>)
						  (if self.header
						      (println "#include <"self.header">")
						    (print "extern ")
						    (ir-gen-c-decl type name)
						    (println ";"))
						  (set self.type type)))

(define-method ir-gen-c <ir-ext> (ir)		)


(define-function check-proto-args (a b)
  (or (= (car a) IR-VARARGS)
      (and (not a) (not b))
      (and (= (car a) (car b))
	   (check-proto-args (cdr a) (cdr b)))))


(define-class <ir-call> <ir-insn> ())		(define-function ir-call (dest args)	(new <ir-call> () (cons dest args)))

(define-method ir-check-type <ir-call> (ir)	(let* ((call-sig  (map-with ir-check-type self.operands ir))
						       (dest-type (car call-sig))
						       (fun-type  (if (ir-pointer-type? dest-type) (<ir-pointer-type>-referent dest-type) dest-type))
						       (fun-args  (<ir-function-type>-arg-types fun-type))
						       (arg-types (cdr call-sig)))
						  (or (ir-function-type? fun-type)
						      (error "called value is not a function: "self))
						  (and fun-args (or (check-proto-args fun-args arg-types)
								    (error "expected argument types "(<ir-function-type>-arg-types fun-type)" in call: "self)))
						  (set self.type (<ir-function-type>-ret-type fun-type))))

(define-method ir-gen-c <ir-call> (ir)		(let ((func (car self.operands))
						      (args (cdr self.operands)))
						  (ir-gen-c func ir)
						  (print "(")
						  (and args (ir-gen-c (car args) ir))
						  (list-do arg (cdr args) (print ", ") (ir-gen-c arg ir))
						  (print ")")))


(define-class <ir-struct> <ir-insn> ())		(define-function ir-struct (name members)	(new <ir-struct> name members))

(define-method ir-check-type <ir-struct> (ir)	(let* ((type  (ir-struct-type ir self.parameters))
						       (specs (map ir-struct-member-type (<ir-struct-type>-members type)))
						       (types (map-with ir-check-type self.operands ir)))
						  (or (equal specs types) (error "member type mismatch: ")self)
						  (set self.type type)))

(define-method ir-gen-c <ir-struct> (ir)	(print "(struct "(c-mangle (<ir-struct-type>-name self.type))"){")
						(and self.operands (ir-gen-c (car self.operands) ir))
						(list-do operand (cdr self.operands)
						  (print ", ")
						  (ir-gen-c operand ir))
						(print "}"))


(define-class <ir-member> <ir-insn> ())		(define-function ir-member (name . value) (new <ir-member> name value))

(define-method ir-check-type <ir-member> (ir)	(let* ((type (ir-check-type (car self.operands) ir)))
						  (or (and (ir-pointer-type? type)
							   (ir-struct-type? (<ir-pointer-type>-referent type)))
						      (error "value is not a pointer to a structure: "self))
						  (let ((member (ir-struct-type-member-named (<ir-pointer-type>-referent type) self.parameters)))
						    (or member "no such structure member: "self)
						    (set self.type (<ir-struct-member>-type member)))))

(define-method ir-gen-c <ir-member> (ir)	(print "(")  (ir-gen-c (car self.operands) ir)  (print "->"self.parameters")"))


(define-class <ir-addr> <ir-insn> ())		(define-function ir-addr (name) (new <ir-addr> name))

(define-method ir-check-type <ir-addr> (ir)	(let* ((var (ir-lookup ir self.parameters)))
						  (set self.type (ir-pointer-to (<ir-variable>-type var)))))

(define-method ir-gen-c <ir-addr> (ir)		(print "(&"self.parameters")"))

;;; pseudo

(define-function ir-put (self . insns)
  (with-instance-accessors <ir>
    (list-do insn insns
      (array-append self.program insn))))

;;; generation

(define-function ir-typecheck (self)
  (with-instance-accessors <ir>
    (array-do insn self.program (ir-check-type insn self))))

(define-function ir-gen-main (self)
  (with-instance-accessors <ir>
    ;;(ir-dump self)
    (println "#include <stdint.h>")
    (alist-do def self.structure-types
	      ;;(print "// ") (dumpln def)
	      (ir-gen-c-declaration def))
    (ir-typecheck self)
    ;;(ir-dump self)
    (alist-do var (<scope>-bindings (<ir>-scope self))
	      ;;(print "// ")  (dumpln var)
	      (ir-gen-c-definition var))
    (println "int main() {")
    (array-do insn self.program
      ;;(print "// ")  (dumpln insn)
      (ir-gen-c insn self)
      (println ";")
      )
    (println "return 0;")
    (println "}")
    ))
