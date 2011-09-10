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
  toplevel      = (typedef | _):top _ comment? eol -> top ;
  program       = toplevel*:p -> p ;
}

(define nile-program
  (let ((pstream (parser-stream (string-stream (concat-files *arguments*))))
        (nparser (parser <nile-parser> pstream)))
    ($program nparser)
    (<parser>-result nparser)))
