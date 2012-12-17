(load "nile-resolve-env.l")

(define-method resolve <nile-typeref> (env)
  (let ((typedef (_get env <nile-typedef> self.name)))
    (if (not typedef)
      (nile-fatal-error "Type "self.name" undefined"))
    (if (abstract? self)
      (type typedef)
      typedef)))

(define-method resolve-with-intype <nile-processref> (env _intype)
  (let ((vardecl (_get env <nile-vardecl> self.var)))
    (if (not vardecl)
      (nile-fatal-error "Variable "self.var" undefined"))
    (if (not (intype (type vardecl)))
      (nile-fatal-error "Variable(s) "self.var" should be a process"))
    (nile-processref vardecl)))

(define-method resolve <nile-condcase> (env)
  (let* ((value_     (resolve self.value env))
         (condition_ (resolve self.condition env))
         (n          (list-length (inner-types (type value_)))))
    (if (and (inner-types (type value_)) (not (inner-types (type condition_))))
      (nile-condcase value_ (nile-tupleexpr (replicate n condition_)))
      (nile-condcase value_ condition_))))

(define-method resolve <nile-varexpr> (env)
  (let* ((vardecl (_get env <nile-vardecl> self.var))
         (vars    (if (not vardecl) (split-vars self))))
    (cond (vardecl (nile-varexpr vardecl))
          (vars    (resolve vars env))
          (else    (nile-fatal-error "Variable(s) "self.var" undefined")))))

(define-method resolve <nile-fieldexpr> (env)
  (let* ((record_ (resolve self.record env))
         (field_  (get-field-by-name (type record_) self.field)))
    (if (not field_)
      (nile-fatal-error "No field "self.field" in type: "record_))
    (nile-fieldexpr record_ field_)))

(define-method resolve <nile-opexpr> (env)
  (if (pair? self.arg)
    (set self.arg (nile-tupleexpr self.arg)))
  (let* ((arg_ (resolve self.arg env))
         (op_  (get-opdef env self.op self.fixity (type arg_))))
    (if (is-chained-relational? self)
      (resolve (unchain-relational self) env)
      (if (not op_)
        (nile-op-lookup-error self.op self.fixity (type arg_))
        (nile-opexpr op_ self.fixity arg_)))))

(define-method resolve-primed <nile-vardecl> (env)
  (let ((unprimed-vardecl (_get env <nile-vardecl> (unprimed-name self))))
    (if (not unprimed-vardecl)
      (nile-fatal-error "Primed variable "self.name" has no unprimed counterpart"))
    (if (and self.type (not (equal? (resolve self.type env) (type unprimed-vardecl))))
      (nile-fatal-error "Primed variable must have same type as unprimed counterpart"))
    (add env (nile-vardecl self.name (type unprimed-vardecl)))))

(define-method resolve <nile-vardecl> (env)
  (if (not self.type)
    (nile-fatal-error "Variable "self.name" must be explicitly typed."))
  (if (is-primed? self)
    (resolve-primed self env)
    (add env (nile-vardecl self.name (resolve self.type env)))))

(define-method resolve-with-type <nile-vardecl> (env inferred-type)
  (if (is-primed? self)
    (resolve-primed self env)
    (let ((type_ (if self.type (resolve self.type env) inferred-type)))
      (add env (nile-vardecl self.name type_)))))

(define-method resolve-with-type <nile-tuplepat> (env inferred-type)
  (if (!= (list-length (inner-types inferred-type)) (list-length self.elements))
    (nile-fatal-error "Tuple pattern has wrong shape."))
  (let* ((envs      (replicate (list-length self.elements) env))
         (itypes    (inner-types inferred-type))
         (elements_ (map resolve-with-type self.elements envs itypes)))
    (nile-tuplepat elements_)))

(define-method resolve <nile-vardef> (env)
  (let* ((rvalue_ (resolve self.rvalue env))
         (lvalue_ (resolve-with-type self.lvalue env (type rvalue_))))
    (nile-vardef lvalue_ rvalue_)))

(define-method resolve-with-type <nile-tupletype> (env inferred-type)
  (if (!= (list-length (inner-types inferred-type)) (list-length self.types))
    (nile-fatal-error "Shape of tuple type does not match inferred type."))
  (let* ((envs   (replicate (list-length self.types) env))
         (itypes (inner-types inferred-type))
         (types_ (map resolve-with-type self.types envs itypes)))
    (nile-tuplepat types_)))

(define-method resolve-with-type <nile-processtype> (env inferred-type)
  (let ((intype_  (resolve-with-type self.intype  env (intype  inferred-type)))
        (outtype_ (resolve-with-type self.outtype env (outtype inferred-type))))
    (nile-processtype intype_ outtype_)))

(define-method resolve-with-type <nile-typeref> (env inferred-type)
  (if (abstract? self)
    (let ((typedef (_get env <nile-typedef> self.name)))
      (if (and typedef (not (equal? (type typedef) inferred-type)))
        (nile-fatal-error "Type variable "self.name" used inconsistently."))
      (type (or typedef (add env (nile-typedef self.name inferred-type)))))
    (resolve self env)))

(define-method resolve-with-intype <nile-ifstmt> (env _intype)
  (let ((condition_ (resolve self.condition env))
        (tblock_    (resolve-with-intype self.tblock (clone env) _intype))
        (fblock_    (resolve-with-intype self.fblock (clone env) _intype)))
    (nile-ifstmt condition_ tblock_ fblock_)))

(define-method resolve <nile-typedef> (env)
  (let ((type_ (resolve self.type env)))
    (add env (nile-typedef self.name type_))))

(define-method resolve <nile-opdef> (env)
  (print "Resolving operation: ") (print-structure self 2) (println "")
  (let* ((env_  (clone env))
         (sig_  (resolve self.sig env_))
         (body_ (if self.body (resolve self.body env_))))
    (add env (nile-opdef sig_ body_))))

(define-method resolve-with-intype <nile-processbody> (env _intype)
  (let* ((env_    (clone env))
         (forpat_ (resolve-with-type   self.forpat env_ _intype))
         (block_  (resolve-with-intype self.block  env_ _intype)))
    (nile-processbody forpat_ block_)))

(define-method finish-resolve <nile-processdef> (env)
  (println "Resolving "(name self))
  (let* ((env_      (clone env))
         (sig_      (resolve self.sig env_))
         (_intype   (intype (type sig_))) ; what if _intype is nil (from a bad typedef)?
         (tmpdef    (nile-processdef sig_ '() '() '()))
         (_         (add env_ tmpdef)) ; for process recursion
         (prologue_ (resolve-with-intype self.prologue env_ _intype))
         (body_     (if self.body (resolve-with-intype self.body env_ _intype)))
         (epilogue_ (resolve-with-intype self.epilogue env_ _intype)))
    (nile-processdef sig_ prologue_ body_ epilogue_)))

(define-method resolve <nile-processdef> (env)
  (if (polymorphic? self)
    (add env self) ; don't resolve until used
    (add env (finish-resolve self env))))

; TODO what if arg type doesn't match the param -- as in process type vs. not a process type
(define-method resolve-abstract-types <nile-vardecl> (arg env)
  (if (abstract? self.type)
    (if (and (is-a? self.type <nile-processtype>)
             (is-a? arg       <nile-pipeline>))
      (let* ((_intype_ (resolve (intype self.type) env))
             (arg_     (resolve-with-intype arg env _intype_)))
        (resolve-with-type self.type env (type arg_)))
      (let ((arg_ (resolve arg env)))
        (resolve-with-type self.type env (type arg_))))))

(define-method resolve-process-arg <nile-vardecl> (arg env)
  (if (is-a? arg <nile-pipeline>)
    (resolve-with-intype arg env (intype (resolve self.type env)))
    (resolve arg env)))

(define-method resolve-polymorphic <nile-processinst> (env _intype)
  (let* ((env_    (clone env))
         (process (_get env_ <nile-processdef> self.process)))
    (if (is-a? (type process) <nile-processtype>)
      (resolve-with-type (intype (type process)) env_ _intype)) ; set type vars in intype
    (list-do (param arg) (zip (params process) self.args)
      (resolve-abstract-types param arg env_))
    ; all type vars should have values now in env_
    (let* ((envs_    (replicate (list-length self.args) env_))
           (args_    (map resolve-process-arg (params process) self.args envs_))
           (process_ (finish-resolve process env_)))
      (nile-processinst process_ args_))))

(define-method resolve-with-intype <nile-processinst> (env _intype)
  (let ((process (_get env <nile-processdef> self.process)))
    (if (not process)
      (nile-fatal-error "Process definition for "self.process" not found"))
    (if (!= (list-length self.args) (list-length (params (sig process))))
      (nile-fatal-error "Wrong number of arguments for "self.process))
    (if (polymorphic? process)
      (resolve-polymorphic self env _intype)
      (nile-processinst process (map-with resolve self.args env)))))

(define-method resolve-with-intype <nile-pipeline> (env _intype)
  (let* ((process_    (resolve-with-intype self.process env _intype))
         (_intype_    (outtype (type process_)))
         (downstream_ (if self.downstream (resolve-with-intype self.downstream env _intype_))))
    (nile-pipeline process_ downstream_)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Nothing interesting in these; they should be autogenerated.
; For each member of object, if nil or string then do nothing,
; if list then map-with resolve, otherwise just resolve.

(define-method resolve <nile-primtype> (env) self)

(define-method resolve <nile-processtype> (env)
  (let ((intype_  (resolve self.intype  env))
        (outtype_ (resolve self.outtype env)))
    (nile-processtype intype_ outtype_)))

(define-method resolve <nile-tupletype> (env)
  (let ((types_ (map-with resolve self.types env)))
    (nile-tupletype types_)))

(define-method resolve <nile-field> (env)
  (let ((type_ (resolve self.type env)))
    (nile-field self.name type_)))

(define-method resolve <nile-recordtype> (env)
  (let ((fields_ (map-with resolve self.fields env)))
    (nile-recordtype fields_)))

(define-method resolve <nile-numexpr> (env) self)

(define-method resolve <nile-tupleexpr> (env)
  (let ((elements_ (map-with resolve self.elements env)))
    (nile-tupleexpr elements_)))

(define-method resolve <nile-condexpr> (env)
  (let ((cases_     (map-with resolve self.cases env))
        (otherwise_ (resolve self.otherwise env)))
    (nile-condexpr cases_ otherwise_)))

(define-method resolve-with-intype <nile-outstmt> (env _)
  (let ((values_ (map-with resolve self.values env)))
    (nile-outstmt values_)))

(define-method resolve-with-intype <nile-instmt> (env _)
  (let ((values_ (map-with resolve self.values env)))
    (nile-instmt values_)))

(define-method resolve-with-intype <nile-substmt> (env _intype)
  (let ((pipeline_ (resolve-with-intype self.pipeline env _intype)))
    (nile-substmt pipeline_)))

(define-method resolve-with-intype <nile-block> (env _intype)
  (let ((stmts_ (map-with2 resolve-with-intype self.stmts env _intype)))
    (nile-block stmts_)))

(define-method resolve <nile-opsig> (env)
  (let ((param_ (resolve self.param env))
        (type_  (resolve self.type  env)))
    (nile-opsig self.name self.fixity param_ type_)))

(define-method resolve <nile-opbody> (env)
  (let ((vardefs_ (map-with resolve self.vardefs env))
        (result_  (resolve self.result env)))
    (nile-opbody vardefs_ result_)))

(define-method resolve <nile-processsig> (env)
  (let ((params_ (map-with resolve self.params env))
        (type_   (resolve self.type env)))
    (nile-processsig self.name params_ type_)))

(define-method resolve <nile-tuplepat> (env)
  (nile-tuplepat (map-with resolve self.elements env)))

(define-method resolve-with-intype <nile-vardef> (env _)
  (resolve self env))
