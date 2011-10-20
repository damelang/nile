(define-ast-node nile-typedvar (name type)
  (do-print () (print self.name":"self.type)))

(define-ast-node nile-pattern (elements)
  (do-print () (print self.elements)))

(define-ast-node nile-realexpr (real)
  (do-print () (print self.real)))

(define-ast-node nile-varexpr (var)
  (do-print () (print self.var)))

(define-ast-node nile-tupleexpr (elements)
  (do-print () (print self.elements)))

(define-ast-node nile-condcase (value condition)
  (do-print () (print self.value" if "self.condition"; ")))

(define-ast-node nile-condexpr (cases default)
  (do-print () (print "{ "self.cases" "self.default", otherwise }")))

(define-ast-node nile-recfieldexpr (rec fields)
  (do-print () (print self.rec"."self.fields)))

(define-ast-node nile-coerceexpr (value type)
  (do-print () (print "("self.value":"self.type")")))

(define-ast-node nile-opexpr (op args)
  (do-print () (print self.op self.args)))

(define-ast-node nile-vardef (pattern value)
  (do-print () (print self.pattern" = "self.value"\n")))

(define-ast-node nile-instmt (values)
  (do-print () (print "<< "self.values"\n")))

(define-ast-node nile-outstmt (values)
  (do-print () (print ">> "self.values"\n")))

(define-ast-node nile-ifstmt (condition iftrue iffalse)
  (do-print () (print "IF "self.condition"\n"self.iftrue"\nELSE\n"self.iffalse"ENDIF\n")))

(define-ast-node nile-tupletype (elements)
  (do-print () (print self.elements)))

(define-ast-node nile-recordtype (fields)
  (do-print () (print self.fields)))

(define-ast-node nile-processtype (intype outtype)
  (do-print () (print self.intype" >> "self.outtype)))

(define-ast-node nile-typedef (name type)
  (do-print () (print "type "self.name" = "self.type))
  (name     () self.name))

(define-ast-node nile-opsig (name args type)
  (do-print () (print self.name" "self.args" : "self.type))
  (name     () self.name))

(define-ast-node nile-opdef (sig vars result)
  (do-print () (print self.sig"\n"self.vars"\n"self.result))
  (name     () (name self.sig)))

(define-ast-node nile-processsig (name args type)
  (do-print () (print self.name" "self.args" : "self.type))
  (name     () self.name))

(define-ast-node nile-processbody (pattern stmts)
  (do-print () (print "∀ "self.pattern"\n"self.stmts)))

(define-ast-node nile-processdef (sig prologue body epilogue)
  (do-print () (print self.sig"\n\n"self.prologue"\n\n"self.body"\n\n"self.epilogue))
  (name     () (name self.sig)))

(define-ast-node nile-processinst (name args)
  (do-print () (print self.name self.args)))

(define-ast-node nile-pexpr (processes)
  (do-print () (print self.processes)))

(define-ast-node nile-substmt (pexpr)
  (do-print () (print "⇒ "self.pexpr)))

(define nile-indentation 0)

(define peg-make-definition peg-make-definition-with-memo)

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
  prodexpr      =  unaryexpr:a (   _          ->"_":o    _  unaryexpr:b -> (nile-opexpr o `(,a ,b)):a)* -> a ;
  mulexpr       =   prodexpr:a (" "_ &mulop ropname:o " "_   prodexpr:b -> (nile-opexpr o `(,a ,b)):a)* -> a ;
  infixexpr     =    mulexpr:a (" "_ !mulop ropname:o " "_    mulexpr:b -> (nile-opexpr o `(,a, b)):a)* -> a ;
  relateexpr    =  infixexpr:a (" "_     [<>≤≥≠=]@$:o " "_  infixexpr:b -> (nile-opexpr o `(,a ,b)):a)* -> a ;
  logicexpr     = relateexpr:a (" "_         [∧∨]@$:o " "_ relateexpr:b -> (nile-opexpr o `(,a ,b)):a)* -> a ;
  expr          = logicexpr ;

  # Process expressions
  processarg    = LPAREN expr:e RPAREN               -> e
                | pexpr ;
  processinst   = processname:n LPAREN processarg:a1
                  (COMMA processarg)*:as RPAREN      -> (nile-processinst n (cons a1 as))
                | processname:n (LPAREN RPAREN)?     -> (nile-processinst n '())
                | LPAREN RARROW RPAREN               -> (nile-processinst "Passthrough" '()) ;
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
                        ( "else "_"if "_ {ifbody i}:f -> (nile-ifstmt c t f)
                        | "else" {indentedStmts i}:f -> (nile-ifstmt c t f)
                        )
                  | -> (nile-ifstmt c t '())
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
  processdef    = processsig:s prologue:p processbody?:b epilogue:e -> (nile-processdef s p b e) ;

  # Top level
  definition    = typedef | opdef | processdef ;
  error         = -> (error "error in Nile program near: "(parser-stream-context self.source)) ;
  program       = (EOL* definition)*:defs EOL* (!. | error) -> defs ;
}

(define nile-program
  (let ((pstream (parser-stream (string-stream (concat-files *arguments*))))
        (nparser (parser <nile-parser> pstream)))
    ($program nparser)
    (<parser>-result nparser)))

"\n\n\n\n"

(list-do top nile-program
  (println "\n\n" top))
