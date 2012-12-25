; TODO mangle process names?

(nile-load "nile-gen-code-env.l")
(nile-load "nile-builtins-c.l")

(define nile-set-cvars-from-primed)

(define-function nile-set-cvars (vars vals env)
  (list-do (var val) (zip (flatten vars) (flatten vals))
    (out env var" = "val";\n")))

(define-function nile-set-cvars-if (vars vals cond-val env)
  (list-do (var val) (zip (flatten vars) (flatten vals))
    (out env var" = "cond-val" ? "val" : "var";\n")))

(define-function nile-gen-code-for-processinst (full-name arg-vals result-var env)
  (out env result-var" = "full-name" (p")
    (list-do val arg-vals (out-no-indent env ", " val))
    (out-no-indent env ");\n"))
  
(define-method alloc-cvars <nile-primtype> (env)
  (let ((type (if (= self.name "Number") "float" "int")))
    (list (alloc-cvar env type))))

(define-method alloc-cvars <nile-processtype> (env)
  (list (alloc-cvar env "nile_Process_t *")))

(define-method gen-code <nile-numexpr> (env)
  (list (string->double self.number)))

(define-method gen-code <nile-pipeline> (env)
  (let ((process-var (gen-code self.process env)))
    (if self.downstream
      (let ((downstream-var (gen-code self.downstream env)))
        (out env process-var" = nile_Process_pipe ("process-var", "downstream-var");\n")))
    process-var))

(define-method gen-code <nile-substmt> (env)
  (let ((pipeline-var (gen-code self.pipeline env)))
    (out env "return nile_Process_reroute (p, i, j, "pipeline-var");\n")))

(define-method gen-code <nile-ifstmt> (env)
  (let ((cval (car (gen-code self.condition env))))
    (out env "if ("cval")\n")
    (out env "{\n")
      (push-indent env) (gen-code self.tblock env) (pop-indent env)
    (out env "}\n")
    (out env "else\n")
    (out env "{\n")
      (push-indent env) (gen-code self.fblock env) (pop-indent env)
    (out env "}\n")))

(define-method gen-code <nile-instmt> (env)
  (list-do value self.values
    (let ((vals (gen-code value env)))
      (out env "if (i == 0) nile_Process_prefix_input (p, &in, &i, &m);\n")
      (list-do val (list-reverse (flatten vals))
        (out env "in[--i] = "val";\n"))))) ; TODO what if val is int (bool)?

(define-method gen-code <nile-outstmt> (env)
  (list-do value (list-reverse self.values)
    (let ((vals (gen-code value env)))
      (out env "if (j == n) nile_Process_advance_output (p, &out, &j, &n);\n")
      (list-do val (flatten vals)
        (out env "out[j++] = "val";\n"))))) ; TODO what if val is int (bool)?

(define-method gen-code <nile-processbody> (env)
  (out env "while (status == 0)\n")
  (out env "{\n")
  (push-indent env)
    (out env "while (i < m)\n")
    (out env "{\n")
    (push-indent env)
      (list-do var (flatten (gen-code self.forpat env))
        (out env var" = in[i++];\n"))

      (gen-code self.block env)

      (nile-set-cvars-from-primed env)
    (pop-indent env)
    (out env "}\n")
    (out env "status = nile_Process_advance_input (p, &in, &i, &m);\n")
  (pop-indent env)
  (out env "}\n"))

(define-method gen-code-for-vars-struct <nile-processdef> (cname env)
  (let* ((_vardecls (++ (params self.sig) (vardecls self.prologue)))
         (env_      (clone env (string-port)))
         (_         (map-with gen-code _vardecls env_))
         (all-cvars (list-reverse (cvars env_))))
    (if all-cvars
      (let ()
        (out env "struct "cname"_vars\n")
        (out env "{\n")
        (push-indent env)
          (list-do (name . type) all-cvars
            (out env type" "name";\n"))
        (pop-indent env)
        (out env "};\n\n")))))

(define-method gen-code-for-constructor-sig <nile-processdef> (cname env)
  (out env "nile_Process_t *\n"cname" (nile_Process_t * parent")
  (push-indent env)
    (list-do (name . type) (list-reverse (cvars env))
      (out-no-indent env ",\n")
      (out env type" "name))
  (pop-indent env)
  (out-no-indent env ")"))

(define-method gen-code-for-constructor <nile-processdef> (cname env)
  (gen-code-for-constructor-sig self cname env)
  (out env "\n{\n")
  (push-indent env)
    (out env "nile_Process_t *p = nile_Process (parent, "
             (csize (intype (type self)))", "(csize (outtype (type self)))", "
             (if (empty? self.prologue) "0, " (++ cname "_prologue, "))
             (if (not self.body)        "0, " (++ cname "_body, "))
             (if (empty? self.epilogue) "0"   (++ cname "_epilogue"))");\n")
    (if (cvars env)
      (let ()
        (out env "struct "cname"_vars *vars = nile_Process_memory (p);\n")
        (out env "if (p)\n")
        (out env "{\n")
        (push-indent env)
          (list-do (name . _) (list-reverse (cvars env))
            (out env "vars->"name" = "name";\n"))
        (pop-indent env)
        (out env "}\n")))
    (out env "return p;\n")
  (pop-indent env)
  (out env "}\n\n"))

; TODO maru format %s doesn't seem to work
(define-function nile-gen-work-function-sig (name)
  (++ (++ "static int\n" name) " (nile_Process_t *p, float *in, int i, int m, float *out, int j, int n)"))

(define-function nile-gen-work-function-decl (function-name)
  (++ (nile-gen-work-function-sig function-name) ";\n\n"))

; Used to compile process prologues, bodies and epilogues
(define-function nile-gen-code-for-work-function (ast-node cname suffix _env)
  (let* ((env       (clone _env (out-port _env)))
         (env_      (clone  env (string-port)))
         (_         (gen-code ast-node env_))
         (all-cvars (list-reverse (cvars env_))))
    (println "Compiling work function: " cname suffix)
    (out env (nile-gen-work-function-sig (++ cname suffix))"\n")
    (out env "{\n")
    (push-indent env)
      (out env "int status = 0;\n")
      (if (cvars env)
        (out env "struct "cname"_vars *vars = nile_Process_memory (p);\n"))
      (list-do (name . type) all-cvars
        (out env type" "name";\n"))
      (list-do (name . _) (list-reverse (cvars env))
        (out env name" = vars->"name";\n"))

        (gen-code ast-node env)

      (list-do (vardecl . cvars) (list-reverse (bindings _env))
        (list-do (cvar val) (zip (flatten cvars) (flatten (lookup env (name vardecl))))
          (out env "vars->"cvar" = "val";\n")))
      (out env "return nile_Process_return (p, i, j, status);\n")
    (pop-indent env)
    (out env "}\n\n")))

(define-function nile-gen-code-for-header-file (ast module-name)
  (let ((header-file-name (++ module-name ".h"))
        (env              (nile-gen-code-env module-name)))
    (println "Header file name: "header-file-name)
    (out env "#ifndef "(to-upper-case module-name)"_H\n"
             "#define "(to-upper-case module-name)"_H\n"
             "#include \"nile.h\"\n"
             "#ifdef __cplusplus\n"
             "extern \"C\" {\n"
             "#endif\n\n")
    (list-do def ast
      (if (and (is-a? def <nile-processdef>) (not (empty? def)) (not (polymorphic? def)))
        (let ((env_ (clone env (out-port env))))
          (map-with gen-code (params (sig def)) env_)
          (gen-code-for-constructor-sig def (++ (++ module-name "_") (name def)) env_)
          (out env ";\n\n"))))
    (out env "#ifdef __cplusplus\n"
             "}\n"
             "#endif\n"
             "\n#endif\n")
    (contents-to-file-named (port-contents (out-port env)) header-file-name)))

(define-function nile-gen-code-for-source-file (ast module-name)
  (let ((source-file-name (++ module-name ".c"))
        (env              (nile-gen-code-env module-name)))
    (println "Source file name: "source-file-name)
    (out env "#define NILE_INCLUDE_PROCESS_API\n")
    (out env "#include \"nile.h\"\n")
    (out env "#include <math.h>\n\n")
    (map-with gen-code ast env)
    (contents-to-file-named (port-contents (out-port env)) source-file-name)))

(nile-load "nile-gen-code.l")
