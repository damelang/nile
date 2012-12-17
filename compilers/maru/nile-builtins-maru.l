(define nile-builtins (nile-resolve-env '()))

(define nile-builtin-typedefs (list
  "type Boolean"
  "type Number"))

(define nile-builtin-opdefs (list
  (cons "¬a:Boolean : Boolean" (lambda (env a r) (out env "(set "r" (! "a"))\n")))
  (cons "-a:Number  : Number"  (lambda (env a r) (out env "(set "r" (- "a"))\n")))
  (cons "√a:Number  : Number"  (lambda (env a r) (out env "(set "r" (sqrtf "a"))\n")))

  (cons "a:Boolean ∨ b:Boolean : Boolean" (lambda (env a b r) (out env "(set "r" (or  "a" "b"))\n")))
  (cons "a:Boolean ∧ b:Boolean : Boolean" (lambda (env a b r) (out env "(set "r" (and "a" "b"))\n")))
  (cons "a:Number  = b:Number  : Boolean" (lambda (env a b r) (out env "(set "r" (=   "a" "b"))\n")))
  (cons "a:Number  ≠ b:Number  : Boolean" (lambda (env a b r) (out env "(set "r" (!=  "a" "b"))\n")))
  (cons "a:Number  < b:Number  : Boolean" (lambda (env a b r) (out env "(set "r" (<   "a" "b"))\n")))
  (cons "a:Number  ≤ b:Number  : Boolean" (lambda (env a b r) (out env "(set "r" (<=  "a" "b"))\n")))
  (cons "a:Number  > b:Number  : Boolean" (lambda (env a b r) (out env "(set "r" (>   "a" "b"))\n")))
  (cons "a:Number  ≥ b:Number  : Boolean" (lambda (env a b r) (out env "(set "r" (>=  "a" "b"))\n")))
  (cons "a:Number  + b:Number  : Number"  (lambda (env a b r) (out env "(set "r" (+   "a" "b"))\n")))
  (cons "a:Number  - b:Number  : Number"  (lambda (env a b r) (out env "(set "r" (-   "a" "b"))\n")))
  (cons "a:Number    b:Number  : Number"  (lambda (env a b r) (out env "(set "r" (*   "a" "b"))\n")))
  (cons "a:Number  / b:Number  : Number"  (lambda (env a b r) (out env "(set "r" (/   "a" "b"))\n")))

  (cons "⌊a:Number⌋ : Number" (lambda (env a r)
    (out env "(set "r" (cast (cast "a" int32) float32))\n")
    (out env "(set "r" (if (> "r" "a") (- "r" 1.0) "r"))\n")))

  (cons "⌈a:Number⌉ : Number" (lambda (env a r)
    (out env "(set "r" (cast (cast "a" int32) float32))\n")
    (out env "(set "r" (if (< "r" "a") (+ "r" 1.0) "r"))\n")))))

(define-method gen-code-for-builtin <nile-opexpr> (env arg-vals result-var)
  (let* ((_sig       (sig self.op))
         (param-type (type (param _sig)))
         (opdef      (get-opdef nile-builtins (name _sig) (fixity _sig) param-type)))
    (if opdef
      (apply (body opdef) (flatten (list env arg-vals result-var)))
      (println "When looking for the implementation of a builtin operator...\n")
      (nile-op-lookup-error (name self.op) (fixity self.op) param-type))
    result-var))

(list-do t nile-builtin-typedefs
  (let ((ast (parse-string <nile-parser> $typedef t)))
    (resolve ast nile-builtins)))

(list-do o nile-builtin-opdefs
  (let* ((ast   (parse-string <nile-parser> $opsig (car o)))
         (sig   (resolve ast nile-builtins))
         (opdef (nile-opdef sig (cdr o))))
    (add nile-builtins opdef)))
