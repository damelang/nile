<nile-parser> : <text-parser> (indentation)

# Lexical rules
NULL         = -> '() ;
_            = " "* ;
LPAREN       = "("_ ;
RPAREN       = _")" ;
COMMA        = _","_ EOL* ;
COLON        = _":"_ ;
RARROW       = _("→" | "->")_ EOL* ;
FOREACH      = ("∀" | "for"_"each" | "for"_"all")_ ;
PRIME        = "′" | "'" ;
CRLF         = "\n""\r"* | "\r""\n"* ;
comment      = "--" (!CRLF .)* ;
digit        = [0-9] ;
number       = (digit+ ("." digit+)?)@$ | "∞" ;
alpha        = [A-Za-z\u0370-\u03FF] ;
ident        = (alpha (alpha | digit)*)@$;
varname      = (ident        PRIME?)@$ ;
juxtavarname = (alpha digit* PRIME?)@$ ;
opname1      = [∧∨]@$ ;
opname2      = [<>≤≥≠=≈≉]@$ ;
opname3      = !opname1 !opname2 !opname4
               [-~!@#$^&*+|¬²³‖⌈⌉⌊⌋▷◁⟂\u2201-\u221D\u221F-\u22FF\x3F\x5B\x5D]@$
             | "\\"ident ;
opname4      = [/∙×%]@$ ;
opname       = (opname1 | opname2 | opname3 | opname4) ;

# Indentation rules
EOL                = _ comment? CRLF _:spaces -> (set self.indentation (list-length spaces)) ;
indentation        =                          -> self.indentation ;
atIndentation   :i = EOL+                    &-> (= i self.indentation) ;
pastIndentation :i = EOL+                    &-> (< i self.indentation) ;

# Simple types
stype      = tupletype | recordtype
           | ident:n                                  -> (nile-typeref n) ;
tupletype  = LPAREN stype:t1 (COMMA stype)+:ts RPAREN -> (nile-tupletype  (cons t1 ts)) ;
field      = ident:n COLON stype:t                    -> (nile-field n t) ;
recordtype = LPAREN field:f1 (COMMA field)+:fs RPAREN -> (nile-recordtype (cons f1 fs)) ;

# Primary expressions
numexpr     = number:n                                -> (nile-numexpr n) ;
varexpr     = varname:v                               -> (nile-varexpr v) ;
parenexpr   = LPAREN expr:e RPAREN                    -> e ;
tupleexpr   = LPAREN expr?:e1 (COMMA expr)*:es RPAREN -> (nile-tupleexpr (++ e1 es)) ;
condcase    = expr:v COMMA "if "_ expr:c EOL+         -> (nile-condcase v c) ;
condexpr    = "{"_ condcase+:cs
                   expr:o COMMA "otherwise" _"}"      -> (nile-condexpr cs o) ;
primaryexpr = numexpr | varexpr | parenexpr | tupleexpr | condexpr ;

# Record field expressions
fieldexpr = fieldexpr:r "." ident:f -> (nile-fieldexpr r f)
          | primaryexpr ;

# Operation expressions
opexpr6 = opname:n1 fieldexpr:a opname:n2 -> (nile-opexpr (++ n1 n2) 'out  a)
        | opname:n  fieldexpr:a           -> (nile-opexpr n          'pre  a)
        |           fieldexpr:a opname:n  -> (nile-opexpr n          'post a)
        |           fieldexpr ;
opexpr5 = opexpr5:a " "*    NULL:n      opexpr6:b -> (nile-opexpr n 'in `(,a ,b)) | opexpr6 ;
opexpr4 = opexpr4:a " "+ opname4:n " "+ opexpr5:b -> (nile-opexpr n 'in `(,a ,b)) | opexpr5 ;
opexpr3 = opexpr3:a " "+ opname3:n " "+ opexpr4:b -> (nile-opexpr n 'in `(,a ,b)) | opexpr4 ;
opexpr2 = opexpr2:a " "+ opname2:n " "+ opexpr3:b -> (nile-opexpr n 'in `(,a ,b)) | opexpr3 ;
opexpr1 = opexpr1:a " "+ opname1:n " "+ opexpr2:b -> (nile-opexpr n 'in `(,a ,b)) | opexpr2 ;
expr    = opexpr1 ;

# Variable juxtaposition
juxtavar  = juxtavarname:n                   -> (nile-varexpr n) ;
juxtavars = juxtavars:a    NULL:n juxtavar:b -> (nile-opexpr n 'in `(,a ,b))
          | juxtavar:a     NULL:n juxtavar:b -> (nile-opexpr n 'in `(,a ,b)) ;

# Variable declarations, definitions, and patterns
vardecl  = varname:n COLON stype:t                       -> (nile-vardecl n  t)
         | (varname | "_"):n                             -> (nile-vardecl n '())
         | LPAREN vardecl:p RPAREN                       -> p ;
tuplepat = LPAREN pattern?:e1 (COMMA pattern)*:es RPAREN -> (nile-tuplepat (++ e1 es)) ;
pattern  = vardecl | tuplepat ;
vardef   = pattern:p _"="_ expr:v                        -> (nile-vardef p v) ;

# Operation definitions
outfixsig  = opname:n1 pattern:p opname:n2 COLON stype:t -> (nile-opsig (++ n1 n2) 'out  p t) ;
prefixsig  = opname:n  pattern:p           COLON stype:t -> (nile-opsig n          'pre  p t) ;
postfixsig =           pattern:p opname:n  COLON stype:t -> (nile-opsig n          'post p t) ;
infixsig   = pattern:p1 (" "+ opname | NULL):n " "+ pattern:p2
                                           COLON stype:t -> (nile-opsig n 'in (nile-tuplepat `(,p1 ,p2)) t) ;
opsig      = outfixsig | prefixsig | postfixsig | infixsig ;
opbody     = ({pastIndentation 0} vardef)*:vars
              {pastIndentation 0}     expr:r             -> (nile-opbody vars r)
           |                                             -> '() ;
opdef      = opsig:sig opbody:body                       -> (nile-opdef sig body) ;

# Process pipelines
parg        = pipeline | expr ;
pargs       = LPAREN parg?:a1 (COMMA parg)*:as RPAREN -> (++ a1 as) ;
processinst = ident:p _ pargs:args                    -> (nile-processinst p args) ;
process     = processinst
            | varname:v                               -> (nile-processref v) ;
pipeline    = RARROW process:p (pipeline | NULL):d    -> (nile-pipeline p d) ;

# Statements
instmt    = "<<"_ expr:v1 (_"<<"_ expr)*:vs   -> (nile-instmt  (cons v1 vs)) ;
outstmt   = ">>"_ expr:v1 (_">>"_ expr)*:vs   -> (nile-outstmt (cons v1 vs)) ;
ifstmt    = indentation:i "if "_                 {ifbody i} ;
ifbody :i = expr:condition
            {block i}:tblock
            ({elseif i} | {else i}):fblock    -> (nile-ifstmt condition tblock fblock) ;
elseif :i = {atIndentation i} "else "_"if "_     {ifbody i} ;
else   :i = {atIndentation i} "else"             {block  i}
          |                                      {block  i} ;
substmt   = pipeline:p                        -> (nile-substmt p) ;
stmt      = vardef | instmt | outstmt | ifstmt | substmt ;
block  :i = ({pastIndentation i} stmt)*:stmts -> (nile-block stmts) ;

# Process types
processtype = stype:intype _">>"_ stype:outtype -> (nile-processtype intype outtype)
            | ident:n                           -> (nile-typeref n)
            | LPAREN processtype:t RPAREN       -> t ;
type        = processtype | stype ;

# Type definitions
typedef = "type "_ ident:n _"="_ type:t -> (nile-typedef n t)
        | "type "_ ident:n              -> (nile-typedef n (nile-primtype n)) ;

# Process definitions
pparam      = varname:n COLON type:t                      -> (nile-vardecl n t) ;
pparams     = LPAREN pparam?:p1 (COMMA pparam)*:ps RPAREN -> (++ p1 ps) ;
processsig  = ident:n _ pparams:p COLON processtype:t     -> (and (println "Parsing "n"...")
                                                                  (nile-processsig n p t))   ;
processbody = indentation:i FOREACH pattern:p {block i}:b -> (nile-processbody p b) ;
processdef  = processsig:s
                {block 0}:p EOL+
                processbody?:b
                {block 0}:e                               -> (nile-processdef s p (car b) e) ;

# Top level
definition = typedef | processdef | opdef ;
error      = -> (error "error in Nile program near: "(parser-context self)) ;
start      = (EOL* definition)*:defs EOL* (!. | error) -> defs ;
