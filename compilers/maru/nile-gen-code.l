(define-function nile-set-cvars-from-primed (env)
  (list-do (vardecl . primed-vals) (list-reverse (bindings env))
    (if (is-primed? vardecl)
      (let ((vars (lookup env (unprimed-name vardecl))))
        (nile-set-cvars vars primed-vals env)))))

(define-method alloc-cvars <nile-tupletype>  (env) (map-with alloc-cvars self.types env))
(define-method alloc-cvars <nile-recordtype> (env) (map-with alloc-cvars (map type self.fields) env))
(define-method alloc-cvars <nile-typedef>    (env) (alloc-cvars self.type env))

(define-method gen-code <nile-varexpr> (env)
  (lookup env (name self.var)))

(define-method gen-code <nile-tupleexpr> (env)
  (map-with gen-code self.elements env))

(define-method gen-code <nile-fieldexpr> (env)
  (let ((vals  (gen-code self.record env))
        (index (get-index-of-field (type self.record) self.field)))
    (list-at vals index)))

(define-method gen-code <nile-condcase> (vars&env)
  (let* (((vars env) vars&env)
         (vals       (gen-code self.value env))
         (cond-vals  (gen-code self.condition env)))
    (list-do (vars_ vals_ cond-vals_) (zip vars vals cond-vals) ; one level down
      (nile-set-cvars-if vars_ vals_ (car (flatten cond-vals_)) env)))) ; cond-vals could be single val

(define-method gen-code <nile-condexpr> (env)
  (let ((vars (alloc-cvars (type self) env))
        (vals (gen-code self.otherwise env)))
    (nile-set-cvars vars vals env)
    (reverse-map-with gen-code self.cases (list vars env))
    vars))

(define-method gen-code <nile-vardecl> (env)
  (let ((cvars (alloc-cvars self.type env)))
    (if (!= self.name "_")
      (bind env self cvars)
      cvars)))

(define-method gen-code-with-vals <nile-vardecl> (env vals)
  (if (!= self.name "_")
    (if (not (is-primed? self))
      (bind env self vals)
      (let ((vars (gen-code self env)))
        (nile-set-cvars vars vals env)))))

(define-method gen-code <nile-tuplepat> (env)
  (map-with gen-code self.elements env))

(define-method gen-code-with-vals <nile-tuplepat> (env vals)
  (list-do (element vals_) (zip self.elements vals)
    (gen-code-with-vals element env vals_)))

(define-method gen-code <nile-vardef> (env)
  (let ((vals (gen-code self.rvalue env)))
    (gen-code-with-vals self.lvalue env vals)))

(define-method gen-code <nile-opbody> (env)
  (map-with gen-code self.vardefs env)
  (gen-code self.result env))

(define-method gen-code <nile-opexpr> (env)
  (let ((arg-vals (gen-code self.arg env)))
    (if (not (body self.op))
      (gen-code-for-builtin self env arg-vals (alloc-cvars (type self.op) env))
      (let* ((_bindings (bindings env))
             (_param    (param (sig self.op)))
             (_         (gen-code-with-vals _param env arg-vals))
             (result    (gen-code (body self.op) env)))
          (set-bindings env _bindings)
          result))))

(define-method gen-code <nile-processref> (env)
  (car (lookup env (name self.var))))

(define-method gen-code <nile-processinst> (env)
  (let* ((prefix     (if (empty? self.process) "nile" (module-name env)))
         (full-name  (++ (++ prefix "_") (name self.process)))
         (arg-vals   (flatten (map-with gen-code self.args env)))
         (iquantum   (csize (intype (type self))))
         (arg-vals_  (if (empty? self.process) (cons iquantum arg-vals) arg-vals))
         (result-var (car (alloc-cvars (type self) env))))
      (nile-gen-code-for-processinst full-name arg-vals_ result-var env)
      result-var))

(define-method gen-code <nile-block> (env)
  (list-do stmt self.stmts (gen-code stmt env)))

(define-method gen-code <nile-typedef> (env))
(define-method gen-code <nile-opdef>   (env))

(define-method gen-code <nile-processdef> (_env)
  (if (and (not (empty? self)) (not (polymorphic? self)))
    (let* ((_      (println "Generating code for "(name self)"..."))
           (env    (clone _env (out-port _env)))
           (cname  (++ (++ (module-name env) "_") (name self))))
      (gen-code-for-vars-struct self cname env)
      (if (not (empty? self.prologue))
        (out env (nile-gen-work-function-decl (++ cname "_prologue"))))
      (if self.body
        (out env (nile-gen-work-function-decl (++ cname "_body"))))
      (if (not (empty? self.epilogue))
        (out env (nile-gen-work-function-decl (++ cname "_epilogue"))))
      (map-with gen-code (params self.sig) env)
      (gen-code-for-constructor self cname env)
      (map-with gen-code (vardecls self.prologue) env)
      (if (not (empty? self.prologue))
        (nile-gen-code-for-work-function self.prologue cname "_prologue" env))
      (if self.body
        (nile-gen-code-for-work-function self.body cname "_body" env))
      (if (not (empty? self.epilogue))
        (nile-gen-code-for-work-function self.epilogue cname "_epilogue" env)))))
