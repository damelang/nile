(define nile-builtin-opdefs (list
  (cons "¬a:Boolean : Boolean" (lambda (env a r) (out env r" = !"a";\n")))
  (cons "-a:Number  : Number"  (lambda (env a r) (out env r" = -"a";\n")))
  (cons "√a:Number  : Number"  (lambda (env a r) (out env r" = sqrtf ("a");\n")))

  (cons "a:Boolean ∨ b:Boolean : Boolean" (lambda (env a b r) (out env r" = "a" || "b";\n")))
  (cons "a:Boolean ∧ b:Boolean : Boolean" (lambda (env a b r) (out env r" = "a" && "b";\n")))
  (cons "a:Number  = b:Number  : Boolean" (lambda (env a b r) (out env r" = "a" == "b";\n")))
  (cons "a:Number  ≠ b:Number  : Boolean" (lambda (env a b r) (out env r" = "a" != "b";\n")))
  (cons "a:Number  < b:Number  : Boolean" (lambda (env a b r) (out env r" = "a" < "b";\n")))
  (cons "a:Number  ≤ b:Number  : Boolean" (lambda (env a b r) (out env r" = "a" <= "b";\n")))
  (cons "a:Number  > b:Number  : Boolean" (lambda (env a b r) (out env r" = "a" > "b";\n")))
  (cons "a:Number  ≥ b:Number  : Boolean" (lambda (env a b r) (out env r" = "a" >= "b";\n")))
  (cons "a:Number  + b:Number  : Number"  (lambda (env a b r) (out env r" = "a" + "b";\n")))
  (cons "a:Number  - b:Number  : Number"  (lambda (env a b r) (out env r" = "a" - "b";\n")))
  (cons "a:Number    b:Number  : Number"  (lambda (env a b r) (out env r" = "a" * "b";\n")))
  (cons "a:Number  / b:Number  : Number"  (lambda (env a b r) (out env r" = "a" / "b";\n")))

  (cons "⌊a:Number⌋ : Number" (lambda (env a r)
    (out env r" = (int) "a";\n")
    (out env r" = ("r" > "a") ? "r" - 1 : "r";\n")))

  (cons "⌈a:Number⌉ : Number" (lambda (env a r)
    (out env r" = (int) "a";\n")
    (out env r" = ("r" < "a") ? "r" + 1 : "r";\n")))))

(nile-load "nile-builtins.l")
