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

(nile-load "nile-builtins.l")
