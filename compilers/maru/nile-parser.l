(define-structure <nile-fielddef> (label type))
(define-function nile-fielddef (label type)
  (let ((fdef (new <nile-fielddef>)))
    (set (<nile-fielddef>-label fdef) label)
    (set (<nile-fielddef>-type fdef) type)
    fdef))
(define-method do-print <nile-fielddef> ()
  (print "[FIELDDEF "self.label" : "self.type"]"))

(define-structure <nile-recordtype> (fields))
(define-function nile-recordtype (fields)
  (let ((rtype (new <nile-recordtype>)))
    (set (<nile-recordtype>-fields rtype) fields)
    rtype))
(define-method do-print <nile-recordtype> ()
  (print "[RECORDTYPE (")
  (list-do field self.fields (print " " field))
  (print ")]"))

(define-structure <nile-tupletype> (elements))
(define-function nile-tupletype (elements)
  (let ((rtype (new <nile-tupletype>)))
    (set (<nile-tupletype>-elements rtype) elements)
    rtype))
(define-method do-print <nile-tupletype> ()
  (print "[TUPLETYPE (")
  (list-do element self.elements (print " " element))
  (print ")]"))

(define-structure <nile-processtype> (intype outtype))
(define-function nile-processtype (intype outtype)
  (let ((ptype (new <nile-processtype>)))
    (set (<nile-processtype>-intype ptype) intype)
    (set (<nile-processtype>-outtype ptype) outtype)
    ptype))
(define-method do-print <nile-processtype> ()
  (print "[PROCESSTYPE "self.intype" >> "self.outtype"]"))

(define-structure <nile-typedef> (name type))
(define-function nile-typedef (name type)
  (let ((tdef (new <nile-typedef>)))
    (set (<nile-typedef>-name tdef) name)
    (set (<nile-typedef>-type tdef) type)
    tdef))
(define-method do-print <nile-typedef> ()
  (print "[TYPEDEF "self.name" = "self.type"]"))

{ <nile-parser> : <parser> ()
  eol           = ("\n""\r"* | "\r""\n"*) ;
  _             = " "* ;
  uppercase     = [ABCDEFGHIJKLMNOPQRSTUVWXYZ] ;
  lowercase     = [abcdefghijklmnopqrstuvwxyz] ;
  alpha         = (uppercase | lowercase) ;
  typename      = (uppercase alpha*)@$ ;
  fieldlabel    = alpha@$ ;
  fielddef      = fieldlabel:l _":"_ typename:t -> (nile-fielddef l t) ;
  recordtype    = "("_ fielddef:f1 (_","_ fielddef)*:fs _")" -> (nile-recordtype (cons f1 fs)) ;
  tupletype     = "("_ typename:t1 (_","_ typename)*:ts _")" -> (nile-tupletype (cons t1 ts)) ;
  processtype   = (typename | tupletype):in _">>"_ (typename | tupletype):out -> (nile-processtype in out) ;
  typedef       = "type "_ typename:n _"="_ (processtype | recordtype):t _ eol -> (nile-typedef n t) ;
  toplevel      = (typedef | (_ eol)) ;
  program       = toplevel*:p -> p ;
}

(define nile-program
  (let ((pstream (parser-stream (string-stream (concat-files *arguments*))))
        (nparser (parser <nile-parser> pstream)))
    ($program nparser)
    (<parser>-result nparser)))
