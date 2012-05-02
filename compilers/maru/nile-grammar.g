<nile-parser> : <parser> (indentation)

# Lexical rules
CRLF          = "\n""\r"* | "\r""\n"* ;
_             = " "* ;
LPAREN        = _"("_ ;
RPAREN        = _")"_ ;
COMMA         = _","_ EOL* ;
COLON         = _":"_ ;
RARROW        = _("→" | "->")_ EOL* ;
FOREACH       = _("∀" | "for"_"each" | "for"_"all")_ ;
DQUOTE        = "\"" ;
comment       = "--" (!CRLF .)* ;
opsym1        = [∧∨] ;
opsym2        = [<>≤≥≠=] ;
opsym3        = !opsym1 !opsym2 !opsym4
                [-~!@#$%^&*+|¬²³‖⌈⌉⌊⌋▷◁⟂\u2201-\u221D\u221F-\u22FF\x3F\x5B\x5D] ;
opsym4        = [/∙×] ;
opsym         = opsym1 | opsym2 | opsym3 | opsym4 ;
alpha         = [A-Za-z\u0370-\u03FF] ;
digit         = [0-9] ;
alphanum      = alpha | digit ;
intliteral    = digit+$ | "∞" ;
realliteral   = (digit+ "." digit+)@$ ;
typename      = alphanum+$ ;
processname   = alphanum+$ ;
opname        = !"--" !"<<" !">>"
                (opsym+ | "\\"alphanum+)$ ;
varname       = (alpha alphanum* "'"?)@$ ;
null          = -> '() ;

# Indentation rules
EOL           = _ comment? CRLF _:spaces -> (set self.indentation (list-length spaces)) ;
indentation   =                          -> self.indentation ;
atIndent      = .:i EOL+                &-> (= i self.indentation) ;
pastIndent    = .:i EOL+                &-> (< i self.indentation) ;

# Types
simpletype    = tupletype | recordtype
              | typename:n                                     -> (nile-typeref n) ;
type          = processtype | simpletype ;
typedvar      = varname:n COLON type:t                         -> (nile-vardecl n t) ;
tupletype     = LPAREN     type:t1 (COMMA     type)+:ts RPAREN -> (nile-tupletype  (cons t1 ts)) ;
recordtype    = LPAREN typedvar:f1 (COMMA typedvar)+:fs RPAREN -> (nile-recordtype (cons f1 fs)) ;
processtype   = simpletype:intype _">>"_ simpletype:outtype    -> (nile-processtype intype outtype) ;

# Argument and parameter lists
args          = exprlist ;
params        = "("_ typedvar:p1 (COMMA typedvar)*:ps _")" -> (cons p1 ps) ;
emptylist     = LPAREN RPAREN                              -> '() ;

# Primary expressions
realexpr      = realliteral:v                           -> (nile-realexpr v) ;
intexpr       = intliteral:v                            -> (nile-intexpr v) ;
varexpr       = varname:n                               -> (nile-varexpr n) ;
parenexpr     = "("_ expr:e _")"                        -> e ;
tupleexpr     = exprlist:es                             -> (nile-tupleexpr es) ;
condcase      = expr:v COMMA "if "_ expr:c (EOL+|_";"_) -> (nile-condcase v c) ;
condexpr      = "{"_ condcase+:cs
                     expr:d (COMMA "otherwise")? _"}"   -> (nile-condexpr cs d) ;
primaryexpr   = realexpr | intexpr | varexpr | parenexpr | tupleexpr | condexpr ;

recfieldexpr  = recfieldexpr:r "." varname:f -> (nile-recfieldexpr r f)
              | primaryexpr ;

# Operation expressions
opexpr6       = opname:n1 recfieldexpr:a  opname:n2 -> (nile-opexpr (++ n1 n2) `(,a))
              | opname:n          args:as           -> (nile-opexpr n             as)
              | opname:n  recfieldexpr:a            -> (nile-opexpr n          `(,a))
              |           recfieldexpr:a  opname:n  -> (nile-opexpr n          `(,a))
              |           recfieldexpr ;
opexpr5       = opexpr5:a " "*           null:n      opexpr6:b -> (nile-opexpr n `(,a ,b)) | opexpr6 ;
opexpr4       = opexpr4:a " "+ &opsym4 opname:n " "+ opexpr5:b -> (nile-opexpr n `(,a ,b)) | opexpr5 ;
opexpr3       = opexpr3:a " "+ &opsym3 opname:n " "+ opexpr4:b -> (nile-opexpr n `(,a ,b)) | opexpr4 ;
opexpr2       = opexpr2:a " "+ &opsym2 opname:n " "+ opexpr3:b -> (nile-opexpr n `(,a ,b)) | opexpr3 ;
opexpr1       = opexpr1:a " "+ &opsym1 opname:n " "+ opexpr2:b -> (nile-opexpr n `(,a ,b)) | opexpr2 ;

# Process pipelines
processinst   = processname:n _(args|emptylist):as  -> (nile-processinst n as) ;
process       = processinst | varname ;
pipeline      = RARROW process:p (pipeline|null):c  -> (nile-pipeline p c) ;

expr          = pipeline | opexpr1 ;
exprlist      = "("_ expr:e1 (COMMA expr)*:es _")" -> (cons e1 es) ;

# Variable definitions
vardecl       = typedvar | varpat
              | (varname|"_"):n                              -> (nile-vardecl n (nile-anytype)) ;
varpat        = LPAREN vardecl:d1 (COMMA vardecl)+:ds RPAREN -> (nile-varpat (cons d1 ds)) ;
vardef        = vardecl:d _"="_ expr:v                       -> (nile-vardef d v) ;

block         = .:i ({pastIndent i} vardef)*:defs
                    ({pastIndent i}   stmt)*:stmts -> (nile-block defs stmts) ;

# In/out statements
instmt        = "<<"_ expr:v1 (_"<<"_ expr)*:vs -> (nile-instmt  (cons v1 vs)) ;
outstmt       = ">>"_ expr:v1 (_">>"_ expr)*:vs -> (nile-outstmt (cons v1 vs)) ;

# If statements
elseif        = .:i {atIndent i} "else "_"if "_ {ifbody i} ;
else          = .:i {atIndent i} "else"         {block  i}
              | .:i                             {block  i} ;
ifbody        = .:i expr:c {block i}:t ({elseif i} | {else i}):f -> (nile-ifstmt c t f) ;
ifstmt        = indentation:i "if "_ {ifbody i} ;

substmt       = pipeline:p -> (nile-substmt p) ;
stmt          = instmt | outstmt | ifstmt | substmt ;

# Type definitions
typedef       = "type "_ typename:n _"="_ type:t               -> (nile-typedef n t  )
              | "type "_ typename:n                            -> (nile-typedef n (nile-primtype n)) ;

# Operation definitions

infixsig      =           LPAREN typedvar:p1 _(opname|null):n _
                                 typedvar:p2 RPAREN           COLON type:t -> (nile-opsig n          `(,p1 ,p2) t) ;
outfixsig     = opname:n1 LPAREN typedvar:p  RPAREN opname:n2 COLON type:t -> (nile-opsig (++ n1 n2)      `(,p) t) ;
prefixsig     = opname:n  LPAREN typedvar:p  RPAREN           COLON type:t -> (nile-opsig n               `(,p) t)
              | opname:n           params:ps                  COLON type:t -> (nile-opsig n                  ps t) ;
postfixsig    =           LPAREN typedvar:p  RPAREN opname:n  COLON type:t -> (nile-opsig n               `(,p) t) ;
opsig         = infixsig | outfixsig | prefixsig | postfixsig ;

opbody        = ({pastIndent 0} vardef)*:defs
                 {pastIndent 0}     expr:v    -> (nile-opbody defs v)
              |                               -> '() ;
opdef         = opsig:sig opbody:body         -> (nile-opdef sig body) ;

# Process definitions
processsig    = processname:n _(params|emptylist):ps COLON type:t      -> (nile-processsig n ps t) ;
prologue      = {block 0} ;
processbody   = indentation:i FOREACH vardecl:d {block i}:s            -> (nile-processbody d s) ;
epilogue      = {block 0} ;
processdef    = processsig:s prologue:p EOL+ processbody?:b epilogue:e -> (nile-processdef s p (car b) e) ;

# Top level
definition    = typedef | opdef | processdef ;
error         = -> (error "error in Nile program near: "(parser-stream-context self.source)) ;
start         = (EOL* definition)*:defs EOL* (!. | error) -> defs ;
