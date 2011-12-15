(define nile-TYPE-UNKNOWN) 

(load "nile-ast.l")

(define peg-make-definition peg-make-definition-with-memo)
;(define peg-make-definition peg-make-definition-with-recursion)
;(load "nile-parser.l")

(define nile-indentation 0)

{ <nile-parser> : <parser> ()

  # Lexical rules
  CRLF          = "\n""\r"* | "\r""\n"* ;
  _             = " "* ;
  LPAREN        = _"("_ ;
  RPAREN        = _")"_ ;
  COMMA         = _","_ ;
  COLON         = _":"_ ;
  RARROW        = _"→"_ ;
  DQUOTE        = "\"" ;
  opsym         = [-!#$%&*+/<>?@^|~¬²³×‖\u2201-\u221D\u221F-\u22FF⌈⌉⌊⌋▷◁⟂] ;
  mulop         = [/∙×] ;
  ropname       = ![<>≤≥≠=∧∨] opname ;
  alpha         = [ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz] ;
  num           = [1234567890] ;
  alphanum      = alpha | num ;
  realliteral   = (num+ ("." num+)?)@$ ;
  typename      = (alpha alphanum*)@$ ;
  opname        = (opsym+ | "\\"alpha+)$ ;
  processname   = (alpha alphanum*)@$ ;
  varname       = (alpha num* "'"?)@$
                | DQUOTE (!DQUOTE .)+$:n DQUOTE -> n ;

  # Indentation rules
  EOL           = _ ("--" (!CRLF .)*)? CRLF _:spaces -> (set nile-indentation (list-length spaces)) ;
  indentation   =                                    -> nile-indentation ;

  # Expressions
  realexpr      = realliteral:r                           -> (nile-realexpr r) ;
  varexpr       = varname:v                               -> (nile-varexpr v) ;
  parenexpr     = "("_ expr:e _")"                        -> e ;
  tupleexpr     = "("_ expr:e1 (COMMA expr)+:es _")"      -> (nile-tupleexpr (cons e1 es)) ;
  condcase      = expr:v COMMA "if "_ expr:c (EOL|_";"_)+ -> (nile-condcase v c) ;
  condexpr      = "{"_ condcase*:cs
                       expr:d (COMMA "otherwise")? _"}"   -> (nile-condexpr cs d) ;
  primaryexpr   = realexpr | varexpr | parenexpr | tupleexpr | condexpr ;
  recfieldexpr  = primaryexpr:r ("." varname)+:fs -> (nile-recfieldexpr r fs)
                | primaryexpr ;
  coerceexpr    = recfieldexpr:e COLON typename:t -> (nile-coerceexpr e t)
                | recfieldexpr ;
  unaryexpr     = opname:n1 coerceexpr:a opname:n2 -> (nile-opexpr (concat-symbol n1 n2) `(,a))
                | opname:n  coerceexpr:a           -> (nile-opexpr n                     `(,a))
                |           coerceexpr:a opname:n  -> (nile-opexpr n                     `(,a))
                |           coerceexpr ;

  prodexpr      =  unaryexpr:a (" "*          ->"_":o " "*  unaryexpr:b -> (nile-opexpr o `(,a ,b)):a)* -> a ;
  mulexpr       =   prodexpr:a (" "+ &mulop ropname:o " "+   prodexpr:b -> (nile-opexpr o `(,a ,b)):a)* -> a ;
  infixexpr     =    mulexpr:a (" "+ !mulop ropname:o " "+    mulexpr:b -> (nile-opexpr o `(,a, b)):a)* -> a ;
  relateexpr    =  infixexpr:a (" "+     [<>≤≥≠=]@$:o " "+  infixexpr:b -> (nile-opexpr o `(,a ,b)):a)* -> a ;
  logicexpr     = relateexpr:a (" "+         [∧∨]@$:o " "+ relateexpr:b -> (nile-opexpr o `(,a ,b)):a)* -> a ;

  #prodexpr      =   prodexpr:a " "*          ->"_":o " "*  unaryexpr:b -> (nile-opexpr o `(,a ,b)) |  unaryexpr ;
  #mulexpr       =    mulexpr:a " "+ &mulop ropname:o " "+   prodexpr:b -> (nile-opexpr o `(,a ,b)) |   prodexpr ;
  #infixexpr     =  infixexpr:a " "+ !mulop ropname:o " "+    mulexpr:b -> (nile-opexpr o `(,a, b)) |    mulexpr ;
  #relateexpr    = relateexpr:a " "+     [<>≤≥≠=]@$:o " "+  infixexpr:b -> (nile-opexpr o `(,a ,b)) |  infixexpr ;
  #logicexpr     =  logicexpr:a " "+         [∧∨]@$:o " "+ relateexpr:b -> (nile-opexpr o `(,a ,b)) | relateexpr ;

  expr          = logicexpr ;

  # Process expressions
  processarg    = LPAREN expr:e RPAREN               -> e
                | pexpr ;
  processinst   = processname:n LPAREN processarg:a1
                  (COMMA processarg)*:as RPAREN      -> (nile-processinst n (cons a1 as))
                | processname:n (LPAREN RPAREN)?     -> (nile-processinst n ())
                | LPAREN RARROW RPAREN               -> (nile-processinst "Passthrough" ()) ;
  process       = LPAREN varname:v RPAREN            -> v
                | processinst ;
  pexpr         = process:p1 (RARROW process)*:ps    -> (nile-pexpr (cons p1 ps)) ;

  # Statements
  pattern       = LPAREN pattern:p1 (COMMA pattern)*:ps RPAREN     -> (nile-pattern (cons p1 ps))
                | "_"
                | varname ;
  vardef        = pattern:p _"="_ expr:e               -> (nile-vardef p e) ;
  instmt        = "<<"_ expr:e1 (_"<<"_ expr)*:es      -> (nile-instmt  (cons e1 es)) ;
  outstmt       = ">>"_ expr:e1 (_">>"_ expr)*:es      -> (nile-outstmt (cons e1 es)) ;
  ifstmt        = indentation:i "if "_ {ifbody i} ;
  ifbody        = .:i expr:c {indentedStmts i}:t
                  ( EOL+ &->(= i nile-indentation)
                        ( "else "_"if "_ {ifbody i}:f -> (nile-ifstmt c t `(,f))
                        | "else"  {indentedStmts i}:f -> (nile-ifstmt c t    f)
                        )
                  | -> (nile-ifstmt c t ())
                  ) ;
  substmt       = "⇒"_ pexpr:e                                     -> (nile-substmt e) ;
  stmt          = vardef | instmt | outstmt | ifstmt | substmt ;
  indentedStmts = .:i (EOL+ &->(< i nile-indentation) stmt)* ;

  # Type definitions
  typedvar      = varname:n COLON typename:t                                  -> (nile-typedvar n t) ;
  tupletype     = LPAREN typename:t1 (COMMA typename)*:ts RPAREN              -> (nile-tupletype  (cons t1 ts)) ;
  recordtype    = LPAREN typedvar:f1 (COMMA typedvar)*:fs RPAREN              -> (nile-recordtype (cons f1 fs)) ;
  processtype   = (typename | tupletype):in _">>"_ (typename | tupletype):out -> (nile-processtype in out) ;
  typedef       = "type "_ typename:n _"="_ (processtype | recordtype):t EOL  -> (nile-typedef n t) ;

  # Operator definitions
  infixsig      = LPAREN typedvar:a1 RPAREN (opname | ->"_"):n
                  LPAREN typedvar:a2 RPAREN
                  COLON typename:t                              -> (nile-opsig n `(,a1 ,a2) t) ;
  outfixsig     = opname:n1 LPAREN typedvar:a RPAREN opname:n2
                  COLON typename:t                              -> (nile-opsig (concat-symbol n1 n2) `(,a) t) ;
  prefixsig     = opname:n LPAREN typedvar:a RPAREN
                  COLON typename:t                              -> (nile-opsig n `(,a) t) ;
  postfixsig    = LPAREN typedvar:a RPAREN opname:n
                  COLON typename:t                              -> (nile-opsig n `(,a) t) ;
  opdef         = (infixsig | outfixsig | prefixsig | postfixsig):sig
                  {indentedStmts 0}:stmts EOL+
                  &->(< 0 nile-indentation) expr:result EOL     -> (nile-opdef sig stmts result) ;

  # Process definitions
  processfargs  = LPAREN typedvar:a1 (COMMA typedvar)*:as RPAREN    -> (cons a1 as)
                |                                                   -> () ;
  processsig    = processname:n processfargs:args
                  COLON (processtype | typename):t                  -> (nile-processsig n args t) ;
  prologue      = {indentedStmts 0} ;
  processbody   = EOL+ indentation:i "∀"_ pattern:p
                    {indentedStmts i}:s                             -> (nile-processbody p s) ;
  epilogue      = {indentedStmts 0} ;
  processdef    = processsig:s prologue:p processbody?:b epilogue:e -> (nile-processdef s p (car b) e) ;

  # Top level
  definition    = typedef | opdef | processdef ;
  error         = -> (error "error in Nile program near: "(parser-stream-context self.source)) ;
  program       = (EOL* definition)*:defs EOL* (!. | error) -> defs ;
}

(define nile-TYPE-UNKNOWN (nile-typedef "UNKNOWN" ()))

(define nile-prelude (list
    (nile-typedef "Real" ())
    (nile-opdef (nile-opsig "-" (list (nile-typedvar "a" "Real"))                            "Real") () ())
    (nile-opdef (nile-opsig "<" (list (nile-typedvar "a" "Real") (nile-typedvar "b" "Real")) "Real") () ())
    (nile-processdef (nile-processsig "DupZip" (list (nile-typedvar "p1" nile-TYPE-UNKNOWN)
                                                     (nile-typedvar "p2" nile-TYPE-UNKNOWN)) nile-TYPE-UNKNOWN) () () ())
    (nile-processdef (nile-processsig "Passthrough" () nile-TYPE-UNKNOWN) () () ())
    (nile-processdef (nile-processsig "SortBy" (list (nile-typedvar "e" "Real")) nile-TYPE-UNKNOWN) () () ())))

(define-function nile-compile (program)
    (let ((defs (concat-list nile-prelude program))
          (globals (map (lambda (def) (cons (name def) def)) defs))
          (_ (list-do def defs (resolve-refs def globals)))
          )
     defs))

(define-function concat-files (files)
  (foldr (lambda (file string)
    (let ((contents (input-stream-up-to (input-stream (open file) file) *end*)))
      (concat-string contents string)))
  "" files))

(define nile-program
  (let ((pstream (parser-stream (string-stream (concat-files *arguments*))))
        (nparser (parser <nile-parser> pstream)))
    (set *arguments* ())
    ($program nparser)
    (<parser>-result nparser)))

(define nile-compiled-program (nile-compile nile-program))

(map-with print-structure nile-compiled-program 0)
