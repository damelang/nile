(define-function make-class-printers (fields index)
  (and fields
       (cons `(let () (print " " ',(car fields) "=") (dump (oop-at self ,index)))
	     (make-class-printers (cdr fields) (+ index 1)))))

(define-function make-class-printer (tname fields)
  `(define-method do-print ,tname ()
      (print "{" ',tname)
      ,@(make-class-printers fields 0)
      (print "}")))

(define-function make-class-method (name spec)
  `(define-method ,(car spec) ,name ,(cadr spec) ,@(cddr spec)))

(define-function make-class-init (name field init)
  `(set (,(concat-symbol name (concat-symbol '- field)) self) ,init))

(define-function make-class-ctor (name ctor args body)
  `(define-function ,ctor ,args
     (let ((self (new ,name)))
       (with-instance-accessors ,name ,@body)
       self)))

(define-function make-class-ctor-from (name vars ctor)
  (cond
   ((symbol? ctor)	(make-class-ctor name ctor vars (with-map2 make-class-init name vars vars)))
   ((pair? ctor)	(let ((cname (car  ctor))
			      (cargs (cadr ctor))
			      (cbody (cddr ctor)))
			  (if (pair? cbody)
			      (make-class-ctor name cname cargs cbody)
			    (make-class-ctor name cname cargs (with-map2 make-class-init name cargs cargs)))))
   (else		(error "illegal method specification: "ctor))))

(define-function make-class-functions (name vars fields specs)
  (and (pair? specs)
       (let ((func (let ((spec (car specs)))
		     (cond
		       ((= spec '=)	(set specs (cdr specs))		(make-class-ctor-from name vars   (car specs)))
		       ((= spec '-)	(set specs (cdr specs))		(make-class-ctor-from name fields (car specs)))
		       ((= spec '@)	(make-class-printer name vars))
		       ((pair? spec)	(make-class-method name spec))
		       (else		(error "illegal method specification: "specs))))))
	 (cons func (make-class-functions name vars fields (cdr specs))))))

;; (define-class name base (fields...) ctor methods...)
;;
;; defines <name> as a subclass of <base> with fields from <base> + the given 'fields...'
;;
;; 'ctor' =
;;    - name			constructor 'name' takes 'fields...' as parameters
;;    = name			'name' takes base fields + 'fields...' as parameters
;;    (name (fields2...))	'name' takes 'fields2...' as parameters, init each field2 with argument
;;    (name (parms...) body...)	'name' takes 'parms...' as parameters, executes 'body' with self.fields bound
;;
;; 'method' =
;;    @				define do-print to print 'field=value' for each field
;;    (selector (args) body...)	define method 'selector <name> (args...) body...'

(define-form define-class (name base fields . functions)
  (set base (eval base))
  (let* ((type  (%allocate-type name))
	 (vars  (concat-list (array-at %structure-fields base) fields))
	 (size  (list-length vars)))
    (sanity-check-structure-fields name vars)
    (set-array-at %structure-sizes  type size)
    (set-array-at %structure-fields type vars)
    (set-array-at %structure-bases  type base)
    (let ((derived (or (array-at %structure-derivatives base)
		       (set-array-at %structure-derivatives base (array)))))
      (array-append derived type))
    (    eval `(define ,name ,type))
    (map eval (%make-accessors name vars))
    (map eval (make-class-functions name vars fields functions))
    type))

;;; ----------------------------------------------------------------

;; (define-structure <object> (n))

;; (define-class <foo> <object> (x y z) = (foo (x y) (set self.x x) (set self.y (* 2 y)) (set self.z 3))
;;   (done-print () (print "foo:"self.n"."self.x","self.y","self.z))
;;   @)

;; (println (foo 101 202))
