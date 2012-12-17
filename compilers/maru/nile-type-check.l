(define-method type-check <nile-condcase> (_)
  (type-check self.condition _)
  (type-check self.value _)
  (let* ((bool  (nile-typedef "Boolean" (nile-primtype "Boolean")))
         (n     (list-length (inner-types (type self.value))))
         (_type (if (> n 0) (nile-tupletype (replicate n bool)) bool)))
    (if (not (equal? (type self.condition) _type))
      (nile-fatal-error "Condition value has wrong type"))))

(define-method type-check <nile-condexpr> (_)
  (map-with type-check self.cases _)
  (map-with type-check self.otherwise _)
  (let ((first-type (type (car self.cases))))
    (list-do value (cons self.otherwise self.cases)
      (if (not (nile-types-compatible? (type value) first-type))
        (nile-fatal-error "Cases of conditional expression have incompatible type")))))
    
(define-method type-check <nile-vardecl> (_type)
  (if (not (nile-types-compatible? self.type _type))
    (nile-fatal-error "Variable "self.name" has incompatible type")))

(define-method type-check <nile-tuplepat> (_type)
  (map type-check self.elements (inner-types _type)))

(define-method type-check <nile-vardef> (_)
  (type-check self.rvalue _)
  (type-check self.lvalue (type self.rvalue)))

(define-method type-check <nile-opbody> (_type)
  (map-with type-check self.vardefs '())
  (type-check self.result _type)
  (if (not (nile-types-compatible? (type self.result) _type))
    (nile-fatal-error "Return value of operation has incompatible type")))

(define-method type-check <nile-opdef> (_)
  (print "Type checking operation: ") (print-structure self 2) (println "")
  (if self.body (type-check self.body (type self.sig))))

(define-method type-check <nile-ifstmt> (_type)
  (type-check self.condition '())
  (let ((booltype (nile-typedef "Boolean" (nile-primtype "Boolean"))))
    (if (not (equal? (type self.condition) booltype))
      (nile-fatal-error "Condition value of \"if\" statement must have Boolean type")))
  (type-check self.tblock _type)
  (type-check self.fblock _type))

(define-method type-check <nile-instmt> (_type)
  (list-do value self.values
    (type-check value '())
    (if (not (nile-types-compatible? (type value) (intype _type)))
      (nile-fatal-error "Stream element has incompatible type"))))

(define-method type-check <nile-outstmt> (_type)
  (list-do value self.values
    (type-check value '())
    (if (not (nile-types-compatible? (type value) (outtype _type)))
      (nile-fatal-error "Stream element has incompatible type"))))

(define-method type-check <nile-pipeline> (_type)
  (type-check self.process _type)
  (if (not (equal? (intype (type self.process)) (intype _type)))
    (nile-fatal-error "Process consumes the wrong type of element"))
  (if self.downstream
    (let ((_type_ (nile-processtype (outtype (type self.process)) (outtype _type))))
      (type-check self.downstream _type_))))

(define-method type-check <nile-processinst> (_type)
  (let* ((_params (params self.process))
         (ptypes  (map type _params))
         (atypes  (map type self.args)))
    (map type-check self.args ptypes)   ; forward through the pipelines
    (map type-check _params   atypes))) ; param-arg check

(define-method type-check <nile-processbody> (_type)
  (type-check self.forpat (intype _type))
  (type-check self.block _type))

(define-method type-check <nile-processdef> (_)
  (println "Type checking process definition for "(name self))
  (let ((_type (type self.sig)))
    (type-check self.prologue _type)
    (if self.body (type-check self.body _type))
    (type-check self.epilogue _type)))

(define-method type-check <nile-substmt> (_type)
  (type-check self.pipeline _type)
  (if (not (equal? (outtype _type) (outtype (type self.pipeline))))
    (nile-fatal-error "Pipeline in substmt produces the wrong type of element")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-method type-check <nile-block> (_type) (map-with type-check self.stmts _type))
(define-method type-check <nile-tupleexpr> (_) (map-with type-check self.elements _))
(define-method type-check <nile-fieldexpr> (_) (type-check self.record _))
(define-method type-check <nile-opexpr>    (_) (type-check self.arg _))
(define-method type-check <nile-numexpr>   (_))
(define-method type-check <nile-varexpr>   (_))
(define-method type-check <nile-processref> (_))
(define-method type-check <nile-typedef>   (_))
