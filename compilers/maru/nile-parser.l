(define-ast-node nile-typedident (ident type)
  (do-print () (print "[TYPEDIDENT "self.ident":"self.type"]")))

(define-ast-node nile-recordtype (fields)
  (do-print () (print "[RECORDTYPE "self.fields"]")))

(define-ast-node nile-tupletype (elements)
  (do-print () (print "[TUPLETYPE "self.elements"]")))

(define-ast-node nile-processtype (intype outtype)
  (do-print () (print "[PROCESSTYPE "self.intype" >> "self.outtype"]")))

(define-ast-node nile-typedef (name type)
  (do-print () (print "[TYPEDEF "self.name" = "self.type"]")))

(define-ast-node nile-opdef (name type args)
  (do-print () (print "[OPDEF "self.name" : "self.type" "self.args" ]")))

{ <nile-parser> : <parser> ()
  eol           = ("\n""\r"* | "\r""\n"*) ;
  comment       = "--" (!eol .)* ;
  _             = " "* ;
  alpha         = [ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz] ;
  num           = [1234567890] ;
  alphanum      = (alpha | num) ;
  typename      = (alpha alphanum*)@$ ;
  ident         = (alpha num*)@$ ;
  typedident    = ident:i _":"_ typename:t -> (nile-typedident i t) ;
  recordtype    = "("_ typedident:f1 (_","_ typedident)*:fs _")" -> (nile-recordtype (cons f1 fs)) ;
  tupletype     = "("_ typename:t1 (_","_ typename)*:ts _")" -> (nile-tupletype (cons t1 ts)) ;
  processtype   = (typename | tupletype):in _">>"_ (typename | tupletype):out -> (nile-processtype in out) ;
  typedef       = "type "_ typename:n _"="_ (processtype | recordtype):t -> (nile-typedef n t) ;
  opname        = "\\"alpha+$ ;
  infixdef      = "("_ typedident:a1 _")"_ opname:n _"(" typedident:a2 _")"_":"_ typename:t -> `(,n ,t (,a1 ,a2)) ;
  outfixdef     = opname:n1 _"("_ typedident:a _")"_ opname:n2 _":"_ typename:t -> `(,(concat-symbol n1 n2) ,t (,a)) ;
  prefixdef     = opname:n _"("_ typedident:a _")"_":"_ typename:t -> `(,n ,t (,a)) ;
  postfixdef    = "("_ typedident:a _")"_ opname:n _":"_ typename:t -> `(,n ,t (,a)) ;
  opdef         = (infixdef | outfixdef | prefixdef | postfixdef):def _ eol -> (apply nile-opdef def) ;
  toplevel      = (typedef | opdef | _):top _ comment? eol -> top ;
  program       = toplevel*:p -> p ;
}

(define nile-program
  (let ((pstream (parser-stream (string-stream (concat-files *arguments*))))
        (nparser (parser <nile-parser> pstream)))
    ($program nparser)
    (<parser>-result nparser)))
