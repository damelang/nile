(define-structure <nile-resolve-env> (items))

(define-function nile-resolve-env (items)
  (let ((self (new <nile-resolve-env>)))
    (set (<nile-resolve-env>-items self) items)
    self))

(define-method clone <nile-resolve-env> ()
  (nile-resolve-env self.items))

(define-method add <nile-resolve-env> (item)
  (set self.items (cons item self.items))
  item)

(define-method _get <nile-resolve-env> (_type _name) ; TODO why is "get" a problem?
  (list-detect item self.items
    (and (is-a? item _type) (= _name (name item)))))

(define-method get-opdef <nile-resolve-env> (name fixity param-type)
  (list-detect item self.items
    (and (is-a? item <nile-opdef>)
         (match? (sig item) name fixity param-type))))
