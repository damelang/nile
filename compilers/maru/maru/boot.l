(define unit-testing? '(t))

(define list (lambda args args))

(define %print print)
(define %dump  dump)

(define error)

(define %error
  (lambda args
    (set error abort)
    (%print "\nERROR: ")
    (apply %print args)
    (%print "\n")
    (abort)))

(set error
  (lambda args
    (set error %error)
    (%print "\n[31;1merror: ")
    (apply print args)
    (%print "[m\n")
    (abort)))

(define caar (lambda (x) (car (car x))))
(define cadr (lambda (x) (car (cdr x))))
(define cdar (lambda (x) (cdr (car x))))
(define cddr (lambda (x) (cdr (cdr x))))
(define cadar (lambda (x) (car (cdr (car x)))))
(define caadr (lambda (x) (car (car (cdr x)))))
(define cdadr (lambda (x) (cdr (car (cdr x)))))
(define caddr (lambda (x) (car (cdr (cdr x)))))
(define cdddr (lambda (x) (cdr (cdr (cdr x)))))
(define caddar (lambda (x) (car (cdr (cdr (car x))))))
(define caaddr (lambda (x) (car (car (cdr (cdr x))))))
(define cadddr (lambda (x) (car (cdr (cdr (cdr x))))))
(define cddddr (lambda (x) (cdr (cdr (cdr (cdr x))))))

(define memq
  (lambda (object list)
    (let ((result ()))
      (while (pair? list)
	(if (= object (car list))
	    (let ()
	      (set result list)
	      (set list ()))
	  (set list (cdr list))))
      result)))

(define assq
  (lambda (object list)
    (let ((result ()))
      (while (pair? list)
	(if (= object (caar list))
	    (let ()
	      (set result (car list))
	      (set list ())))
	(set list (cdr list)))
      result)))

(define concat-list
  (lambda (x y)
    (if (pair? x)
	(cons (car x) (concat-list (cdr x) y))
      y)))

(define concat-string
  (lambda (x y)
    (let ((a (string-length x))
	  (b (string-length y)))
      (let ((s (string (+ a b)))
	    (i 0)
	    (j 0))
	(while (< i a)
	  (set-string-at s j (string-at x i))
	  (set i (+ i 1))
	  (set j (+ j 1)))
	(set i 0)
	(while (< i b)
	  (set-string-at s j (string-at y i))
	  (set i (+ i 1))
	  (set j (+ j 1)))
	s))))

(define concat-symbol
  (lambda (x y)
    (string->symbol (concat-string (symbol->string x) (symbol->string y)))))

(define quasiquote
  (form
    (let ((qq-list) (qq-element) (qq-object))
      (set qq-list (lambda (l)
		     (if (pair? l)
			 (let ((obj (car l)))
			   (if (and (pair? obj) (= (car obj) 'unquote-splicing))
			       (if (cdr l)
				   (list 'concat-list (cadr obj) (qq-list (cdr l)))
				 (cadr obj))
			     (list 'cons (qq-object obj) (qq-list (cdr l)))))
		       (list 'quote l))))
      (set qq-element (lambda (l)
			(let ((head (car l)))
			  (if (= head 'unquote)
			      (cadr l)
			    (qq-list l)))))
      (set qq-object (lambda (object)
		       (if (pair? object)
			   (qq-element object)
			 (list 'quote object))))
      (lambda (env expr)
	(qq-object expr)))))

(define define-form (form (lambda (env name args . body)
			    `(define ,name (form (lambda (*env* ,@args) ,@body))))))

(define-form define-function (name args . body)
  `(define ,name (lambda ,args ,@body)))

(define-form define-macro (name args . body)
  `(define-form ,name ,args (cons 'let (cons () (macro-expand (list-zip-assocs ',args (list ,@args)) ',body)))))

(define-function macro-expand (bindings exp)
  (if (pair? exp)
      (cons (macro-expand bindings (car exp))
	    (macro-expand bindings (cdr exp)))
    (if (symbol? exp)
	(let ((a (assq exp bindings)))
	  (if a (cdr a) exp))
      exp)))

(define-form define-constant (name value)
  `(define ,name (form () (lambda args ',value))))

(define-function list-length (list)
  (if (pair? list)
      (+ 1 (list-length (cdr list)))
    0))

(define %list->array
  (lambda (list index)
    (if (pair? list)
	(let ((a (%list->array (cdr list) (+ 1 index))))
	  (set-array-at a index (car list))
	  a)
      (array index))))

(define-function list->array (list)
  (%list->array list 0))

(define-function array-append (arr val)
  (set-array-at arr (array-length arr) val))

(define-function map (function list)
  (let ((head (cons)))
    (let ((tail head))
      (while (pair? list)
	(set tail (set (cdr tail) (cons (function (car list)) ())))
	(set list (cdr list))))
    (cdr head)))

(define-function map-with (function list a)
  (if (pair? list)
      (let ((head (function (car list) a)))
	(cons head (map-with function (cdr list) a)))))

(define-function with-map (function a list)
  (if (pair? list)
      (let ((head (function a (car list))))
	(cons head (with-map function a (cdr list))))))

(define-function map-with2 (function list a b)
  (if (pair? list)
      (let ((head (function (car list) a b)))
	(cons head (map-with2 function (cdr list) a b)))))

(define-function with2-map (function a b list)
  (if (pair? list)
      (let ((head (function a b (car list))))
	(cons head (with2-map function a b (cdr list))))))

(define-function with-map2 (function a alist blist)
  (if (pair? alist)
      (let ((head (function a (car alist) (car blist))))
	(cons head (with-map2 function a (cdr alist) (cdr blist))))))

(define-function map2-with (function alist blist a)
  (if (pair? alist)
      (let ((head (function (car alist) (car blist) a)))
	(cons head (map2-with function (cdr alist) (cdr blist) a)))))

(define-function map* (function . lists)
  (if (pair? (car lists))
      (let ((head (apply function (map car lists))))
	(cons head (apply map* (cons function (map cdr lists)))))))

(define-function foldr (op value list)
  (if (pair? list)
      (op (car list) (foldr op value (cdr list)))
    value))

(set *expanders*   (array))	(define-form define-expand (type args . body)	`(set-array-at *expanders*   ,type (lambda ,args ,@body)))
(set *encoders*    (array))	(define-form define-encode (type args . body)	`(set-array-at *encoders*    ,type (lambda ,args ,@body)))
(set *evaluators*  (array))	(define-form define-eval   (type args . body)	`(set-array-at *evaluators*  ,type (lambda ,args ,@body)))
(set *applicators* (array))	(define-form define-apply  (type args . body)	`(set-array-at *applicators* ,type (lambda ,args ,@body)))

;;; let*

(define-function %let* (bindings body)
  (if (pair? (cdr bindings))
      `(let (,(car bindings)) ,(%let* (cdr bindings) body))
    `(let ,bindings ,@body)))

(define-form let* bindings-body
  (%let* (car bindings-body) (cdr bindings-body)))

;;; cond

(define-function %progn (prog)	(if (cdr prog) (cons 'let (cons '() prog)) (car prog)))

(define-function %cond (clauses)
  (if (pair? clauses)
      (let* ((clause (car clauses))
	     (test   (car clause))
	     (value  (cdr clause)))
	(if (= 'else test)
	    (%progn value)
	  `(if ,test ,(%progn value) ,(%cond (cdr clauses)))))))

(define-form cond clauses (%cond clauses))

;;; type information

(define %type-names	(array 16))
(define %last-type	-1)

(define %allocate-type
  (lambda (name)
    (set %last-type (+ 1 %last-type))
    (set-array-at %type-names %last-type name)
    %last-type))

(define-function name-of-type (type)	(array-at %type-names type))
(define-function type-name-of (obj)	(name-of-type (type-of obj)))

;;; structure

(define %structure-sizes	(array))
(define %structure-fields	(array))
(define %structure-bases	(array))
(define %structure-derivatives	(array))

(define-function sanity-check-structure-fields (name fields)
  (let ((f fields))
    (while (pair? f)
      (and (memq (car f) (cdr f))
	   (error "field '"(car f)"' multiply-defined in structure: "name" "fields))
      (set f (cdr f)))))

(define-function fields-of-type (type)
  (array-at %structure-fields type))

(define-function inherits-from (type base)
  (and type
       (or (= type base)
	   (inherits-from (array-at %structure-bases type) base))))

(define-function %typecheck (type object)
  (or (= type (type-of object))
      (inherits-from (type-of object) type)
      (error "type check failed for field accessor: expected "type" "(array-at %type-names type)" got "(type-of object)" "(array-at %type-names (type-of object))))
  object)

(define %make-accessor) ;; forward

(define-function %make-safe-accessor (name fields offset)
  (if fields (cons `(define-form ,(concat-symbol name (concat-symbol '- (car fields))) (self)
		      (list 'oop-at
			    (list '%typecheck ',name self)
			    ,offset))
		   (%make-accessor name (cdr fields) (+ 1 offset)))))

(define-function %make-unsafe-accessor (name fields offset)
  (if fields (cons `(define-form ,(concat-symbol name (concat-symbol '- (car fields))) (self)
		      (list 'oop-at
			    self
			    ,offset))
		   (%make-accessor name (cdr fields) (+ 1 offset)))))

(define %make-accessor %make-safe-accessor)

(define-function %make-accessors (name fields)
  (%make-accessor name fields 0))

(define-form define-structure (name fields)
  (let ((type (%allocate-type name))
	(size (list-length fields)))
    (sanity-check-structure-fields name fields)
    (set-array-at %structure-sizes  type size)
    (set-array-at %structure-fields type fields)
    `(let ()
       (define ,name ,type)
       ,@(%make-accessors name fields)
       ,type)))

(define-form new (type . inits)
  (let ((i -1))
    `(let* ((_type_ ,type)
	    (_self_ (allocate _type_ (array-at %structure-sizes _type_))))
       ,@(map (lambda (_init_) (list 'set-oop-at '_self_ (set i (+ i 1)) _init_)) inits)
       _self_)))

(define-form define-class (name basis fields)
  (let ((base (eval basis)))
    (set fields (concat-list (array-at %structure-fields base) fields))
    (sanity-check-structure-fields name fields)
    (let ((type   (%allocate-type name))
;	  (offset (list-length (array-at %structure-fields base)))
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

;;; built-in types

(define-structure <undefined>	())
(define-structure <data>	())
(define-structure <long>	(_bits))				(define-function long? (self) (= <long> (type-of self)))
(define-structure <double>	(_bits))				(define-function double? (self) (= <double> (type-of self)))
(define-structure <string>	(size _bits))
(define-structure <symbol>	(_bits))
(define-structure <pair>	(head tail source))
(define-structure <_array>	())
(define-structure <array>	(size _array))
(define-structure <expr>	(name defn ctx profile))		(define-function expr? (obj) (= <expr> (type-of obj)))
(define-structure <form>	(function symbol))
(define-structure <fixed>	(function))
(define-structure <subr>	(_imp _name _profile))
(define-structure <variable>	(name value env index))			(define-function variable? (obj) (= <variable> (type-of obj)))
(define-structure <env>		(parent level offset bindings stable))
(define-structure <context>	(home env bindings callee pc))

(define-function fixed (fun)
  (let ((self (new <fixed>)))
    (set (<fixed>-function self) fun)
    self))

(define-function variable (name value env index)
  (let ((self (new <variable>)))
    (set (<variable>-name  self) name)
    (set (<variable>-value self) value)
    (set (<variable>-env   self) env)
    (set (<variable>-index self) index)
    self))

(define-function environment (parent)
  (let ((self (new <env>)))
    (set (<env>-parent 	 self) parent)
    (set (<env>-level  	 self) (<env>-level  parent))
    (set (<env>-offset 	 self) (<env>-offset parent))
    (set (<env>-bindings self) (array))
    self))

(define-function environment-define (env name value)
  (let ((bindings (<env>-bindings env))
	(offset   (<env>-offset   env))
	(var      (variable name value env offset)))
    (set (<env>-offset env) (+ offset 1))
    (array-append bindings var)))

;;; local syntax

(define-function make-with-form (args-body)
  (and args-body `(lambda (*env* ,@(car args-body)) ,@(cdr args-body))))

(define-form with-forms (bindings . body)
  (let ((env (environment *env*)))
    (while bindings
      (let* ((binding (car   bindings))
	     (name    (car   binding))
	     (fun     (cadr  binding))
	     (var     (caddr binding))
	     (exp     (list 'form (make-with-form fun) (make-with-form var))))
	(environment-define env (caar bindings) (eval exp *env*))
	(set bindings (cdr bindings))))
    (cons 'let (cons () (map-with expand body env)))))

;;; field accesors

(define-function make-instance-accessors (name fields i)
  (and (pair? fields)
       (cons `(,(concat-symbol 'self. (car fields)) () ((name) (list 'oop-at 'self ,i)))
	     (make-instance-accessors name (cdr fields) (+ i 1)))))
  
(define-form with-instance-accessors (type . body)
  `(with-forms ,(make-instance-accessors type (array-at %structure-fields (eval type)) 0)
    (let () ,@body)))

;;; selector

(define-structure <selector> (name methods default))

(define-function selector? (obj) (= <selector> (type-of obj)))

(define-function <selector>-inherit (methods type)
  (let ((method ()))
    (while (and (set type (array-at %structure-bases type))
		(not (set method (array-at methods type)))))
    method)) ;; xxx THIS SHOULD COPY DOWN THE METHOD FOR PERFORMANCE xxx

(define-apply <selector> (self . arguments)
  (apply (or (array-at (<selector>-methods self) (type-of (car arguments)))
	     (<selector>-inherit (<selector>-methods self) (type-of (car arguments)))
	     (<selector>-default self))
	 arguments))

(define-function selector (name default)
  (let ((self (new <selector>)))
    (set (<selector>-name    self) name)
    (set (<selector>-methods self) (array))
    (set (<selector>-default self) default)
    self))

(define-function <selector>-add-method (self type method)
  (and (expr? method)
       (or (<expr>-name method)
	   (set (<expr>-name method)
		(concat-symbol (array-at %type-names type) (concat-symbol '. (<selector>-name self))))))
  (set-array-at (<selector>-methods self) type method))

(define-form define-selector (name . default)
  (let ((def (defined? name)))
    (if def
	(if (selector? (<variable>-value def))
	    (list 'quote <variable>-value def)
	  (error name" already defined as non-selector: " (<variable>-value def)))
      (let ()
	(or default (set default `(args (error "selector "',name
					       " has no method for "(array-at %type-names (type-of (car args)))
					       ": "(cons (car args) (map name-of-type (map type-of (cdr args))))))))
	`(define ,name (selector ',name (lambda ,@default)))))))

(define-selector add-method)

(<selector>-add-method add-method <selector>
  (lambda (self type args body)
    (<selector>-add-method self type (eval `(lambda ,args (with-instance-accessors ,type ,@body))))))

(define-form define-method (selector type args . body)
  (or (defined? selector) (eval (list 'define-selector selector)))
  `(add-method ,selector ,type ',(cons 'self args) ',body))

;;; print

(define-selector do-print (arg) (%print arg))
(define-selector do-dump  (arg) (do-print arg))

(define print
  (lambda args
    (while (pair? args)
      (do-print (car args))
      (set args (cdr args)))
    (car args)))

(define dump
  (lambda args
    (while (pair? args)
      (do-dump (car args))
      (set args (cdr args)))
    (car args)))

(define println
  (lambda args
    (apply print args)
    (%print "\n")
    (car args)))

(define dumpln
  (lambda args
    (apply dump args)
    (%print "\n")
    (car args)))

(define-method do-dump  <string> ()	(%dump self))
(define-method do-dump  <array> ()	(%dump self))
(define-method do-print <selector> ()	(print "<selector "(<selector>-name self)">"))

(define-method do-print <pair> ()
  (if (= *globals* (cdr self))
      (print "*globals*")
    (let ()
      (print "(")
      (while self
	(if (pair? self)
	    (print (car self))
	  (let ()
	    (print ". ")
	    (print self)))
	(if (set self (cdr self))
	    (print " ")))
      (print ")"))))

(define-method do-dump <pair> ()
  (if (= *globals* (cdr self))
      (print "*globals*")
    (let ()
      (print "(")
      (while self
	(if (pair? self)
	    (dump (car self))
	  (let ()
	    (print ". ")
	    (print self)))
	(if (set self (cdr self))
	    (print " ")))
      (print ")"))))

(define-function dump-until (target arg)
  (let ((found (= target arg)))
    (if (pair? arg)
	(let ()
	  (print "(")
	  (while arg
	    (if (pair? arg)
		(if (dump-until target (car arg))
		    (let ()
		      (if (cdr arg) (print " ..."))
		      (set found 't)
		      (set arg ())))
	      (let ()
		(print ". ")
		(dump-until target arg)))
	    (if (set arg (cdr arg))
		(print " ")))
	  (print ")"))
      (dump arg))
    found))

(if '()
    (set *backtrace*
	 (lambda (stack depth)
	   (println "\n")
	   (let ((posn (array)))
	     (while (>= (set depth (- depth 1)) 0)
	       (let ((here (array-at stack depth)))
		 (print "  " depth "\t")
		 (dump-until posn here)
		 (print "\n")
		 (set posn here))))
	   (exit 1)))
  ;;(println "; backtrace disabled")
  )

;;; multimethod

(define-structure <generic> (name methods default))

(define-function generic (name default)
  (let ((self (new <generic>)))
    (set (<generic>-name    self) name)
    (set (<generic>-methods self) (array))
    (set (<generic>-default self) default)
    self))

(define-method do-print <generic> () (print "<multimethod:" (<generic>-name self) ">"))

(define-form define-generic (name . default)
  (or default (set default `(args (error "no method in "',name" corresponding to: "args))))
  `(define ,name (generic ',name (lambda ,@default))))

(define-function %add-multimethod (mm types method)
  (or (<expr>-name method) (set (<expr>-name method) (<generic>-name mm)))
  (if types
      (let ((methods (or (<generic>-methods mm)
			 (set (<generic>-methods mm) (array 32)))))
	(while (cdr types)
	  (let ((type (eval (car types))))
	    (set methods (or (array-at methods type)
			     (set (array-at methods type) (array 32)))))
	  (set types (cdr types)))
	(set (array-at methods (eval (car types))) method))
    (set (<generic>-methods mm) method)))

(define-form define-multimethod (method typed-args . body)
  (let ((args  (map cadr typed-args))
	(types (map car  typed-args)))
    `(%add-multimethod ,method (list ,@types) (lambda ,args ,@body))))

(define-apply <generic> (self . arguments)
  (let ((method (<generic>-methods self))
	(arg     arguments))
    (while arg
      (set method (array-at method (type-of (car arg))))
      (set arg (cdr arg)))
    (if (and method (not (array? method)))
	(apply method arguments)
      (let ((default (<generic>-default self)))
	(if default
	    (apply default arguments)
	  (error "no method in "(<generic>-name self)" corresponding to "arguments))))))

;;; list

(define-form push (list element)
  `(set ,list (cons ,element ,list)))

(define-form pop (list)
  `(let* ((_list_ ,list) (_head_ (car _list_)))
     (set ,list (cdr _list_))
     _head_))

(define-function member? (key list)
  (while (and (pair? list) (!= key (car list)))
    (set list (cdr list)))
  (car list))

(define-function list-reverse! (head)
  (let ((curr head)
	(prev ())
	(next ()))
    (while curr
      (set next (cdr curr))
      (set-cdr curr prev)
      (set prev curr)
      (set curr next))
    prev))

(define-function list-zip (a b)
  (if (and (pair? a) (pair? b))
      (cons (car a) (cons (car b) (list-zip (cdr a) (cdr b))))
    (or a b)))

(define-function list-zip-assocs (a b)
  (if (and (pair? a) (pair? b))
      (cons (cons (car a) (car b)) (list-zip-assocs (cdr a) (cdr b)))
    (or a b)))

;;; iteration

(define-form for (var-init-limit-step . body)
  (let ((var   	   (car    var-init-limit-step)	   )
	(init  	   (cadr   var-init-limit-step)	   )
	(limit 	   (caddr  var-init-limit-step)	   )
	(step  (or (cadddr var-init-limit-step) 1)))
    `(let ((,var ,init) (_limit_ ,limit))
       (while (< ,var _limit_)
	 ,@body
	 (set ,var (+ ,var ,step))))))

(define-form list-do (var list . body)
  `(let ((_list_ ,list))
     (while _list_
       (let ((,var (car _list_))) ,@body)
       (set _list_ (cdr _list_)))))

(define-function %generic-do (get len var col body)
  `(let* ((_col_ ,col)
	  (_idx_ 0)
	  (_end_ (,len _col_)))
     (while (< _idx_ _end_)
       (let ((,var (,get _col_ _idx_))) ,@body)
       (set _idx_ (+ _idx_ 1)))))

(define-form array-do (var arr . body)	(%generic-do array-at array-length var arr body))

(define-form string-do (var str . body)	(%generic-do string-at string-length var str body))

(define-method for-each <pair>   (function)	(list-do   _elt_ self (function _elt_)))
(define-method for-each <array>  (function)	(array-do  _elt_ self (function _elt_)))
(define-method for-each <string> (function)	(string-do _elt_ self (function _elt_)))

(define-function for-each-with (collection function value)
  (for-each collection (lambda (x) (function x value))))

(define-form incr (lval . options)	`(set ,lval (+ ,lval ,(or (car options) 1))))

(define-form until (condition . body)
  `(while (not ,condition) ,@body))

;;; conversion

(define-function string->number-base (str radix)
  (let ((n 0)
	(i 0)
	(l (string-length str))
	(s 1))
    (while (and (< i l) (= ?- (string-at str i)))
      (set s (- s))
      (set i (+ i 1)))
    (while (< i l)
      (let* ((c (string-at str i))
	     (d (cond
		  ((and (<= ?0 c) (<= c ?9))	      (- c ?0) )
		  ((and (<= ?A c) (<= c ?Z))	(+ 10 (- c ?A)))
		  ((and (<= ?a c) (<= c ?z))	(+ 10 (- c ?a)))
		  (else				      radix    ))))
	(if (< d radix)
	    (let ()
	      (set n (+ (* radix n) d))
	      (set i (+ i 1)))
	  (set l i))))
    (* s n)))

(define-function string->number (str)
  (string->number-base str 10))

(define-function array->string (arr)
  (let* ((ind 0)
	 (lim (array-length arr))
	 (str (string lim)))
    (while (< ind lim)
      (set-string-at str ind (array-at arr ind))
      (set ind (+ 1 ind)))
    str))

(define-function array->list (arr)
  (let* ((ind (array-length arr))
	 (lst ()))
    (while (<= 0 (set ind (- ind 1)))
      (set lst (cons (array-at arr ind) lst)))
    lst))

(define-function list->string (list)
  (let* ((len (list-length list))
	 (str (string len))
	 (idx 0))
    (while (< idx len)
      (set-string-at str idx (car list))
      (set idx (+ idx 1))
      (set list (cdr list)))
    str))

;;; sorting and searching

(define-function %partition (items at set-at compare left pivot right)
  (let ((index left)
	(value (at items pivot)))
    (set-at items pivot (at items right))
    (set-at items right value)
    (for (i left right)
      (and (compare (at items i) value)
	   (let ((item (at items i)))
	     (set-at items i (at items index))
	     (set-at items index item)
	     (set index (+ index 1)))))
    (set value (at items index))
    (set-at items index (at items right))
    (set-at items right value)
    index))

(define-function %sort (items at set-at compare left right)
  (and (< left right)
       (let* ((pivot (/ (+ left right) 2))
	      (index (%partition items at set-at compare left pivot right)))
	 (%sort items at set-at compare left (- index 1))
	 (%sort items at set-at compare (+ index 1) right))))

(define-function array-sort (items . options)
  (%sort items array-at set-array-at (or (car options) <) 0 (- (array-length items) 1))
  items)

(define-function string-sort (items . options)
  (%sort items string-at set-string-at (or (car options) <) 0 (- (string-length items) 1))
  items)

(define-function %search (items length at obj compare)
  (let ((lo 0)
	(hi (- (length items) 1))
	(ix ()))
    (while (<= lo hi)
      (let* ((m (/ (+ lo hi) 2))
	     (s (at items m))
	     (c (compare obj s)))
	(cond
	  ((< c 0)	(set hi (- m 1)))
	  ((> c 0)	(set lo (+ m 1)))
	  (else		(let () (set ix m) (set lo (+ hi 1)))))))
    ix))

(define-function array-search  (arr obj . options)	(%search arr array-length  array-at  obj (or (car options) -)))
(define-function string-search (str obj . options)	(%search str string-length string-at obj (or (car options) -)))

(define-function max (a b)	(if (> a b) a b))
(define-function min (a b)	(if (< a b) a b))

;;; structural equality

(define equal ()) ;; forward

(define-function equal-lists (a b)
  (and (equal (car a) (car b))
       (equal (cdr a) (cdr b))))

(set equal (lambda (a b)
  (or (= a b)
      (and (pair? a)
	   (pair? b)
	   (equal-lists a b)))))

;;; unit testing

(define-form unit-fail (expr)
  `(error "UNIT FAIL "unit-name": "',expr))

(define-form unit-assert (expr)
  `(or ,expr (unit-fail ,expr)))

(define-form unit-test (name . body)
  (and unit-testing?
       `(let ((unit-name ,name))
	  ,@body)))

;;; namespace

(define *global* *globals*)

(define-form define-namespace (name parent)	`(define ,name (environment ,parent)))

(define-form namespace (name)			`(set *globals* ,name))

;;; command line

(define *load-path*)

(and (= "-L" (car *arguments*))
     (let ()
       (pop *arguments*)
       (set *load-path* (pop *arguments*))))

(define-form next-argument () '(pop *arguments*))

;;; load/save

(define-function pval (expr)
  (and (> (verbose) 0) (println expr))
  (let ((result (eval expr)))
    (and (> (verbose) 1) (println "=> "result))
    result))

(define-function find-and-read (name)
  (or (and *load-path* (read (concat-string *load-path* name)))
      (read name)))

(define-function load (name)
  (let ((exps (find-and-read name)))
    (or exps (error "file not found or empty: "name))
    (list-do expr exps (pval expr))))

(define *loaded*)

(define-function require (name)
  (or (member? name *loaded*)
      (let ()
	(push *loaded* name)
	(load name))))
