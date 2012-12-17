<dc> : <parser> ()

error		=                   -> (error "syntax error near: "(parser-stream-context self.source)) ;

space		= " " | "\t" ;
eol			= "\r" "\n"* | "\n" "\r"* ;
comment		= "#" (!eol .)* ;
_		= (space | eol | comment)* ;

LPAREN		= "(" _ ;
RPAREN		= ")" _ ;
STAR		= "*" _ ;
SLASH		= "/" _ ;
PLUS		= "+" _ ;
MINUS		= "-" _ ;

float		= ([+-]?[0-9]+"."[0-9]+("e"[+-]?[0-9]+)?)@$:n _	-> (string->double n)
          	| ([+-]?[0-9]+          "e"[+-]?[0-9]+  )@$:n _	-> (string->double n) ;
integer		= ([+-]?[0-9]+)@$:n _				-> (string->long n) ;
number		= float | integer ;

primary		= number
		| LPAREN expression:e RPAREN			-> e
		;

mulop		= primary:l	( STAR  primary:r		-> (* l r):l
				| SLASH primary:r		-> (/ l r):l
				)*				-> l ;

addop		= mulop:l	( PLUS  mulop:r			-> (+ l r):l
				| MINUS mulop:r			-> (- l r):l
				)*				-> l ;

expression	= addop:e					-> (println e) ;

program		= _ expression* _ (!. | error) ;
