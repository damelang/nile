{
  <example> : <parser> ()

  _		= ([\t ] | "\n""\r"* | "\r""\n"*)* ;

  alpha		= [ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz] ;
  num		= [0123456789] ;
  alphanum	= alpha | num ;

  COMMA		= "," _ ;
  LP		= "(" _ ;
  RP		= ")" _ ;

  name		= (alpha alphanum*)@$$:name _	-> name ;

  statement	= LP name:n			-> `(,n):s
		  ( COMMA name:n		-> `(,@s ,n):s
                  )* RP				-> s ;

  program	= _ statement*:prog "." 	-> prog ;
}

(map println { example-program })

( this , is,a, list , of , names )
( and , another )
( and , another )
.
