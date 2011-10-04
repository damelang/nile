(define-form match-save (exp)	`(let ((pos (<parser-stream>-position self.source))) ,exp))
(define-form match-ok ()	`(set (<parser-stream>-position self.source) pos))
(define-form match-ko ()	`(let () (set (<parser-stream>-position self.source) pos) ()))

(define-form match-rule (name . args)
  (if args
      `(match-save
	 (let ()
	   ,@(map (lambda (arg) (list 'parser-stream-push 'self.source arg)) args)
	   (or (,(concat-symbol '$ name) self)
	       (match-ko))))
    `(,(concat-symbol '$ name) self)))

(define-form match-rule-in (type name . args)
  (let ((tname (concat-symbol '< (concat-symbol type '>)))
	(rname (concat-symbol '$ name)))
    (if args
     `(match-save
        (let ((_p (parser ,tname self.source)))
	  ,@(map (lambda (arg) (list 'parser-stream-push 'self.source arg)) args)
	  (if (,rname _p)
	      (let () (set self.result (<parser>-result _p)) 1)
	    (match-ko))))
     `(let ((_p (parser ,tname self.source)))
	,@(map (lambda (arg) (list 'parser-stream-push 'self.source arg)) args)
	(and (,rname _p)
	     (let () (set self.result (<parser>-result _p)) 1))))))

(define-form match-first exprs		`(or ,@exprs))
(define-form match-all exprs		`(match-save (or (and ,@exprs) (match-ko))))

(define-form match-zero-one (exp)
  `(let ((_list_ (group)))
     (and ,exp (group-append _list_ self.result))
     (set self.result (group->list! _list_))
     1))

(define-form match-zero-more (exp)
  `(let ((_list_ (group)))
     (while ,exp (group-append _list_ self.result))
     (set self.result (group->list! _list_))
     1))

(define-form match-one-more (exp)
  `(let ((_list_ (group)))
     (while ,exp (group-append _list_ self.result))
     (and (not (group-empty? _list_))
	  (let ()
	    (set self.result (group->list! _list_))
	    1))))

(define-form peek-for  (exp)	`(match-save (and ,exp (match-ok))))
(define-form peek-expr (exp)	exp)
(define-form peek-not  (exp)	`(not (peek-for ,exp)))

(define-form match-list (exp)
  `(and (pair? (parser-stream-peek self.source))
	(let ((src self.source))
	  (set self.source (parser-stream (list-stream (parser-stream-peek src))))
	  (let ((ok ,exp))
	    (set self.source src)
	    (and ok (parser-stream-next src))))))

(define-form match-class (str)	`(set self.result (parser-stream-match-class self.source ,(make-class str))))
(define-form match-string (str)	`(set self.result (parser-stream-match-string self.source ,str)))
(define-form match-object (obj)	`(and (= ',obj (parser-stream-peek self.source)) (set self.result (parser-stream-next self.source))))
(define-form match-any ()	'(and (!= *end* (parser-stream-peek self.source)) (let () (set self.result (parser-stream-next self.source)) 1)))

(define-form make-span (exp)
  `(let ((pos (<parser-stream>-position self.source)))
     (and ,exp
	  (let ()
	    (set self.result (list-from-to pos (<parser-stream>-position self.source)))
	    1))))

(define-form make-string	(exp)		`(and ,exp (set self.result (list->string self.result))))
(define-form make-symbol	(exp)		`(and ,exp (set self.result (string->symbol (list->string self.result)))))
(define-form make-number	(base exp)	`(and ,exp (set self.result (string->number-base (list->string self.result) ,base))))

(define-form assign-result (name exp)	`(and ,exp (let () (set ,name self.result) 1)))
(define-form result-expr (exp)		`(let () (set self.result ,exp) 1))

(define-function peg-find-variables (tree vars)
  (and (pair? tree)
       (if (= (car tree) 'assign-result)
	   (or (assq (cadr tree) vars)
	       (set vars (peg-find-variables (caddr tree) (cons (cons (cadr tree)) vars))))
	 (and (!= (car tree) 'result-expr)
	      (map (lambda (exp) (set vars (peg-find-variables exp vars))) (cdr tree)))))
  vars)

(define-function peg-make-declaration (type rule)
  `(define-selector ,(concat-symbol '$ (car rule))))

(define-function peg-make-definition (type rule)
  `(define-method ,(concat-symbol '$ (car rule)) ,type ()
     (let ,(peg-find-variables (cadr rule) ())
       ,(expand (cadr rule)))))

;; (define-function pval (expr)
;;   (dumpln expr)
;;   (eval expr))

(define-function peg-compile-grammar (grammar)
  (let ((class (list 'define-class (<grammar>-name grammar) (<grammar>-base grammar) (<grammar>-fields grammar)))
	(decls (with-map peg-make-declaration (<grammar>-name grammar) (<grammar>-rules grammar)))
	(defns (with-map peg-make-definition  (<grammar>-name grammar) (<grammar>-rules grammar))))
    (set (<grammar>-type grammar) (eval class))
    (list-do decl decls (eval decl))
    (list-do defn defns (eval defn))
    (cons class (concat-list decls defns))))

(define-function peg-compile-rules (name rules)
  (let ((decls (with-map peg-make-declaration name rules))
	(defns (with-map peg-make-definition  name rules)))
    (list-do decl decls (eval decl))
    (list-do defn defns (eval defn))
    (concat-list decls defns)))
