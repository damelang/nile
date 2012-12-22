(define nile-builtins (nile-resolve-env '()))

(define nile-builtin-typedefs (list
  "type Boolean"
  "type Number"))

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
