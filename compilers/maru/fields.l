(define-structure <structure-type> (members))

(define-function structure-type (initial-member)
  (let ((t (new <structure-type>)))
    (set (<structure-type>-members t) (list initial-member))
    t))

(define-method add-member <structure-type> (member)
  (set self.members (cons member self.members)))

(define-method do-print <structure-type> ()
  (print "STRUCT{")
  (list-do member self.members (print " " member))
  (print " }"))


(define-structure <type-definition> (name type))

(define-function type-definition (name type)
  (let ((t (new <type-definition>)))
    (set (<type-definition>-name t) name)
    (set (<type-definition>-type t) type)
    t))

(define-method do-print <type-definition> ()
  (print "TYPE< "self.name" = "self.type" >"))


(define column 0)

{
  <example> : <parser> ()

  eol		= ("\n""\r"* | "\r""\n"*)	-> (set column 0)
		  ( " "				-> (set column (+ 1 column))
		  | "\t"			-> (set column (& -8 (+ 8 column)))
		  )*
		  ;

  _		= [\t ]* eol* ;

  COLON		= ":" _ ;
  COMMA		= "," _ ;
  EQ		= "=" _ ;
  LP		= "(" _ ;
  RP		= ")" _ ;

  alpha		= [ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz] ;
  num		= [0123456789] ;
  alphanum	= alpha | num ;

  __		= !alphanum _ ;

  TYPE		= "type" __ ;

  typename	= ("Real" | "Integer")@$$:name __ -> name ;

  name		= (alpha alphanum*)@$$:name _ -> name ;

  member	= name:n COLON typename:t	-> (type-definition n t);

  typespec	= LP member:m			-> (structure-type m):ms
		  ( COMMA member:m		-> (add-member ms m)
		  )* RP				-> ms
		  ;

  typedef	= TYPE name:n EQ typespec:s	-> (type-definition n s) ;

  statement	= typedef ;

  program	= _ statement*:prog "." 	-> prog ;
}

(map println { example-program })

type Color	= (r : Real, g : Real, b : Real, a : Real)
type RGBA8888   = (r : Integer, g : Integer, b : Integer, a : Integer)
.
