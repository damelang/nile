(define-structure <scope> (parent bindings))

(define-function scope-new (parent)	(new <scope> parent))

(define-function scope-find (self key)	(assq key (<scope>-bindings self)))

(define-function scope-lookup (self key)
  (and self
       (or (scope-find self key)
	   (scope-lookup (<scope>-parent self) key))))

(define-function scope-define (self key value)
  (let ((binding (scope-find self key)))
    (if binding
	(set-cdr binding value)
      (set binding (cons key value))
      (push (<scope>-bindings self) binding))
    binding))

(define-function scope-define-global (self key value)
  (while (<scope>-parent self) (set self (<scope>-parent self)))
  (scope-define self key value))
