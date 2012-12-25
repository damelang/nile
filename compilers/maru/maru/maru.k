(define-structure <extern> (name type))

(define-method do-print <extern> ()
  (print "<extern "self.name" : "self.type">"))

(define *maru-exports* ())
(define *maru-types* ())

(define maru->ir-type-map
  `((void    . ,IR-VOID)
    (char    . ,IR-INT8)	    (int8    . ,IR-INT8)
    (short   . ,IR-INT16)	    (int16   . ,IR-INT16)
    (int     . ,IR-INT)		    (int32   . ,IR-INT32)
    (long    . ,IR-LONG)	    (int64   . ,IR-INT64)
    (float   . ,IR-FLOAT)	    (float32 . ,IR-FLOAT32)
    (double  . ,IR-DOUBLE)	    (float64 . ,IR-FLOAT64)
    (struct  .  struct)
    (...     . ,IR-VARARGS)
    ))

(define-form define-type (name . decl)	(push *maru-types* (cons name decl)) ())

(define-function maru-struct (name ir)
  (if (symbol? name)
      (ir-struct ir name)
    (error "illegal struct name: "name)))

(define maru->ir-type) ;; forward

(define-function maru-defined-type (exp ir)
  (let ((spec (assq exp *maru-types*)))
    (if spec
	(let ((type (cdr spec)))
	  (or (ir-type? type)
	      (set type (set (cdr spec) (maru->ir-type type ir))))
	  type))))

(define-function maru->ir-type (exp ir)
  (cond
    ((symbol? exp)	(or (cdr (assq exp maru->ir-type-map))
			    (maru-defined-type exp ir)
			    (error "illegal type name: "exp)))
    ((pair? exp)	(let ((type (maru->ir-type (car exp) ir)))
			  (and (= 'struct type) (set type (maru-struct (car (set exp (cdr exp))) ir)))
			  (while (and (set exp (cdr exp))
				      (= (car exp) '*))
			    (set type (ir-pointer-to type)))
			  (when (pair? exp)
			    (let ((args (array)))
			      (while (pair? exp)
				(if (car exp)
				    (let ((argt (maru->ir-type (car exp) ir)))
				      (and (= 'struct argt) (set argt (maru-struct (car (set exp (cdr exp))) ir)))
				      (while (and (set exp (cdr exp))
						  (= (car exp) '*))
					(set argt (ir-pointer-to argt)))
				      (array-append args argt))
				  (set exp (cdr exp))))
			      (set type (ir-function-of type (array->list args)))))
			  type))
    (else		(error "illegal type expression: "exp))))

(define-function maru-declaration-name (decl)
  (cond
    ((symbol? decl)		decl)
    ((symbol? (car decl))	(car decl))
    (else			(error "illegal variable name in declaration: "decl))))

(define-function maru-declaration-type (decl ir)
  (and (pair? (cdr decl))
       (maru->ir-type (cdr decl) ir)))

(define-method maru-compile <undefined> (ir)	(ir-nop))
(define-method maru-compile <long>   	(ir)	(ir-lit self IR-INT))
(define-method maru-compile <double> 	(ir)	(ir-lit self IR-DOUBLE))
(define-method maru-compile <string> 	(ir)	(ir-lit self IR-STRING))
(define-method maru-compile <symbol> 	(ir)	(ir-get-var self))
(define-method maru-compile <extern> 	(ir)	(ir-extern self.name))

(define-function maru-compile-define (exp ir)
  (let* ((decl (cadr exp))
	 (name (maru-declaration-name decl))
	 (type (maru-declaration-type decl ir))
	 (init (maru-compile (caddr exp) ir)))
    (ir-define name type init)))

(define-function maru-compile-opt (exp ir)	(if exp (maru-compile exp ir) (ir-nop)))

(define-function maru-compile-let (exp ir)
  (let* ((bindings (cadr exp))
	 (decls    (map car bindings))
	 (inits    (map cadr bindings))
	 (names    (map maru-declaration-name decls))
	 (types    (map-with maru-declaration-type decls ir))
	 (body     (cddr exp)))
    (ir-let names types
	    (map-with maru-compile-opt inits ir)
	    (map-with maru-compile body ir))))

(define-function maru-compile-set (exp ir)
  (let* ((name (cadr exp))
	 (init (maru-compile (caddr exp) ir))
	 (insn (ir-set-var name init)))
    (set (<ir-insn>-source insn) (<pair>-source exp))
    insn))

(define-function maru-compile-while (exp ir)
  (let ((test (maru-compile (cadr exp) ir))
	(body (map-with maru-compile (cddr exp) ir)))
    (cond
      ((not body)		(ir-while test (ir-nop)))
      ((not (cdr body))		(ir-while test (car body)))
      (else			(ir-while test (ir-let () () () body))))))

(define-function maru-compile-if (exp ir)
  (let ((insn (ir-if (maru-compile (cadr exp) ir)
		     (maru-compile (caddr exp) ir)
		     (let ((body (cdddr exp)))
		       (if body
			   (if (cdr body)
			       (ir-let () () () (map-with maru-compile body ir))
			     (maru-compile (car body) ir))
			 (ir-nop))))))
    (set (<ir-insn>-source insn) (<pair>-source exp))
    insn))

(define-function maru-compile-sizeof (exp ir)
  (let ((type (maru->ir-type (cdr exp) ir)))
    (ir-sizeof type)))

(define-function maru-compile-member (exp ir)
  (let ((value (maru-compile (cadr exp) ir))
	(field (caddr exp)))
    (or (symbol? field) (error "illegal field name: "exp))
    (ir-member field value)))

(define-function maru-compile-set-member (exp ir)
  (let ((value (maru-compile (cadr exp) ir))
	(field (caddr exp))
	(init  (maru-compile (cadddr exp) ir)))
    (or (symbol? field) (error "illegal field name: "exp))
    (ir-set-member field value init)))

(define-function maru-compile-indir (exp ir)
  (ir-indir (maru-compile (cadr  exp) ir)
	    (if (caddr  exp) (maru-compile (caddr  exp) ir) (ir-lit 0))))

(define-function maru-compile-set-indir (exp ir)
  (let ((base  (maru-compile (cadr exp) ir))
	(a     (and (caddr   exp) (maru-compile (caddr   exp) ir)))
	(b     (and (cadddr  exp) (maru-compile (cadddr  exp) ir))))
    (cond
      (b	(ir-set-indir base         a  b))
      (a	(ir-set-indir base (ir-lit 0) a))
      (else	(error "incomplete expression: "exp)))))

(define-function maru-compile-return (exp ir)
  (ir-return (if (cadr exp) (maru-compile (cadr exp) ir) (ir-nop))))

(define-function maru-compile-and (exp ir)	(ir-logand (map-with maru-compile (cdr exp) ir)))
(define-function maru-compile-or  (exp ir)	(ir-logor  (map-with maru-compile (cdr exp) ir)))

(define-function maru-compile-cast (exp ir)
  (let ((value (maru-compile (cadr exp) ir))
	(type  (maru->ir-type (cddr exp) ir)))
    (ir-cast type value)))

(define maru-compile-form-map
  `((let	. ,maru-compile-let)
    (set	. ,maru-compile-set)
    (while	. ,maru-compile-while)
    (if		. ,maru-compile-if)
    (sizeof	. ,maru-compile-sizeof)
    (member	. ,maru-compile-member)
    (set-member	. ,maru-compile-set-member)
    (indir	. ,maru-compile-indir)
    (set-indir	. ,maru-compile-set-indir)
    (return	. ,maru-compile-return)
    (and	. ,maru-compile-and)
    (or		. ,maru-compile-or)
    (cast	. ,maru-compile-cast)
    ))

(define maru->ir-unary-map
  `(	(-  . ,ir-neg)  (~  . ,ir-com)  (!  . ,ir-not)  (not . ,ir-not)
	(addressof . ,ir-addressof)
	))

(define maru->ir-binary-map
  `(    (+  . ,ir-add)    (-  . ,ir-sub)    (*  . ,ir-mul)    (/  . ,ir-div)    (%  . ,ir-mod)
        (<< . ,ir-shl)    (>> . ,ir-shr)    (&  . ,ir-bitand) (|  . ,ir-bitor ) (^  . ,ir-bitxor)
        (<  . ,ir-lt )    (<= . ,ir-le )    (=  . ,ir-eq )    (!= . ,ir-ne )    (>= . ,ir-ge )    (>  . ,ir-gt)
	))

(define-function maru-compile-operator (self ir)
  ;; uncomment the following to allow (x . y) to stand for (member x y)
  ;; (if (symbol? (cdr self))
  ;;     (ir-member (cdr self) (maru-compile-value (car self) ir))
    (let* ((name (car self))
	   (args (map-with maru-compile (cdr self) ir))
	   (len  (list-length args))
	   (op   ()))
      (if (or (and (= len 1) (set op (cdr (assq name maru->ir-unary-map ))))
	      (and (= len 2) (set op (cdr (assq name maru->ir-binary-map)))))
	  (op args)
	(ir-call (maru-compile name ir) args))))
  ;;)

(define-method maru-compile <pair> (ir)
  (let* ((name (car self))
	 (args (cdr self))
	 (op   (cdr (assq name maru-compile-form-map))))
    (if op (op self ir)
      (maru-compile-operator self ir))))

(define-function maru-argument-name (exp)		(cond
							  ((= exp '...)		'...)
							  ((= exp 'void)	())
							  (else			(maru-declaration-name exp))))

(define-function maru-argument-type (exp ir)		(cond
							  ((= exp '...)		IR-VARARGS)
							  ((= exp 'void)	IR-VOID)
							  (else			(maru-declaration-type exp ir))))

(define-method maru-compile <expr> (ir)
  (let ((name      (maru-declaration-name self.name))
	(ret-type  (maru->ir-type (car self.definition) ir))
	(arg-names (map maru-argument-name (cadr self.definition)))
	(arg-types (map-with maru-argument-type (cadr self.definition) ir))
	(body      (map-with maru-compile (cddr self.definition) ir)))
    (ir-function name (ir-function-of ret-type arg-types) arg-names body)))

(define *maru-structs* (array))

(define-function maru-struct-member (decl ir)
  (let ((name (maru-declaration-name decl))
	(type (maru-declaration-type decl ir)))
    (cons name type)))

(define-function compile-namespace (ns)
  (let ((ir  (ir-new ()))
	(gen (ir-gen-new)))
    (list-do int-ext *maru-exports* (ir-export-symbol-as ir (car int-ext) (cdr int-ext)))
    (array-do s *maru-structs*
      (ir-declare-struct-type ir (car s) (map-with maru-struct-member (cdr s) ir)))
    (list-do name-type *maru-types*
      (or (ir-type? (cdr name-type))
	  (maru->ir-type (cdr name-type) ir)))
    (namespace-do binding ns
      (let* ((decl (car binding))
	     (name (maru-declaration-name decl))
	     (type (maru-declaration-type decl ir))
	     (init (cdr binding)))
	(when (not (form? init))
	  (ir-append ir (ir-define name type (maru-compile (cdr binding) ir))))))
    (ir-generate ir gen)
    ))

(define *compilation*)

(define-form compile-begin ()
  '(let ()
     (set *compilation* (new-namespace '*compilation*))
     (set *globals* *compilation*)))

(define-form compile-end ()
  '(let ()
     (set *globals* *global-namespace*)
     (compile-namespace *compilation*)))

(define-form extern (name . type)	`(new <extern> ',name ',type))

(define-form define-struct (name members)
  (array-append *maru-structs* (cons name members))
  ())

(define-form export names
  (list-do name names
    (cond
      ((symbol? name)	(push *maru-exports* (cons name name)))
      ((pair? name)	(push *maru-exports* (cons (car name) (cadr name)))))
    ()))

(define-form make-symbol (str) (string->symbol str))

(define-form (make-symbol ".") (value field) `(member ,value ,field))

;; Remove the multiple-value reception facility from LET* since that would interfere with types.

(define-form let* (bindings . body)
  (if bindings
      `(let (,(car bindings)) (let* ,(cdr bindings) ,@body))
    `(let () ,@body)))

(compile-begin)

(while *arguments*
  (load (next-argument)))

(compile-end)
