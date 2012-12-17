# -*- coke -*-

<osdefs> : <text-parser> ()

blank		= [\t ] ;
eol    		= "\n""\r"* | "\r""\n"* ;
comment1	= "//" (&. !eol .)* ;
commentN	= "/*" (&. !"*/" (commentN | .))* "*/" ;
comment		= comment1 | commentN ;
_		= (blank | comment)* ;
__		= (blank | comment | eol)* ;
dnl		= (!eol .)*@$ ;

letter		= [A-Z_a-z_] ;
digit		= [0-9] ;

expression	= "(" expression ")" | !")" . ;

qualifier	= "?" _								-> 'defined?
		| "(" _ expression* @$:e ")" _					-> e ;

header		= ( [a-zA-Z0-9_/.]+@$:x      _					-> x
		  | "\"" (!"\"" .)* $:x "\"" _					-> x
		  | "<"  (!">"  .)*@$:x ">"  _					-> x
		  ) _ (qualifier:q -> `(qualified ,q ,x):x)?			-> x ;

idpart		= (letter (letter | digit)*) @ $$ ;
identifier	= idpart:x _							-> x ;
qualified_id	= idpart:x _ (qualifier:q -> `(qualified ,q ,x):x)?		-> x ;

keyword		= !idpart _ ;

definition	= "header"  keyword header*:i				 eol __	-> (def-headers  i)
		| "integer" keyword qualified_id*:i			 eol __	-> (def-integers i)
		| "float"   keyword qualified_id*:i			 eol __	-> (def-floats   i)
		| "string"  keyword qualified_id*:i			 eol __	-> (def-strings  i)
		| "type"    keyword identifier:i _ (!eol .)*@$:t	 eol __	-> (def-type   i t)
		| "sizes"   keyword identifier*:i _ (!eol .)*@$:t	 eol __	-> (def-sizes    i)
		| "default" keyword identifier:i dnl:e			     __	-> (def-alt    i e) ;

file		= __ definition* (!. ~"'header', 'integer', 'float' or 'type'") ;
