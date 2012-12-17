# -*- coke -*-

<tpeg> : <text-parser> ()

equals    	= "=" space ;
blank		= [\t ] ;
eol		= ("\n" "\r"*) | ("\r" "\n"*) ;
comment		= "#" (!eol .)* ;
space		= (blank | eol | comment)* ;
bar       	= "|"  space ;
pling     	= "!"  space ;
ampersand 	= "&"  space ;
colon     	= ":"  space ;
arrow     	= "->" space ;
quotesgl     	= "\'" space ;
backquote     	= "`"  space ;
commaat     	= ",@" space ;
comma     	= ","  space ;
dollarhash	= "$#" space ;
dollardbl	= "$$" space ;
dollar		= "$"  space ;
at		= "@"  space ;
query     	= "?"  space ;
minus      	= "-"  space ;
plus      	= "+"  space ;
star      	= "*"  space ;
lparen      	= "("  space ;
rparen     	= ")"  space ;
lbrace      	= "{"  space ;
rbrace     	= "}"  space ;
dot       	= "."  space ;
tilde       	= "~"  space ;
digit		= [0-9] ;
higit		= [0-9A-Fa-f] ;
number		= ("-"? digit+) @$#:n space -> n ;
letter		= [A-Z_a-z] ;
idpart		= (letter (letter | digit)*) @$$ ;
identifier	= idpart:id space				-> id ;

char		= "\\"	( "t"					->  9
			| "n"					-> 10
			| "r"					-> 13
			| "x" (higit higit) @$#16
			| "u" (higit higit higit higit) @$#16
			| .
                        )
		| . ;
string		= "\""  (!"\""  char)* $:s "\""  space		-> s ;
class		= "["   (!"]"   char)* $:s "]"   space		-> s ;

grammar         = symbol:name space plus
                  definition*:rules space                       -> `(grammar-extend ,name                 ,@rules)
                | symbol:name space colon symbol:parent space
                  (lparen identifier*:fields rparen)?
                  definition*:rules space                       -> `(grammar-define ,name ,parent ,fields ,@rules)
                | definition*:d space expression?:e             -> `(grammar-eval ,d ,(car e))
                ;

symfirst	= [-!#$%&*+/:<=>@A-Z^_a-z|~] ;
symrest		= [-!#$%&*+./:0-9<=>?@A-Z^_a-z|~] ;
symbol		= (symfirst symrest*) @$$ ;
sexpr		= ("-"? digit+) @$#
		| symbol
		| "?".
		| "\""  (!"\""  char)* $:e "\""					-> e
		| "("  sexpression*:e (space dot sexpression:f)? sspace ")"	-> (set-list-source `(,@e ,@f) e)
		| "["  sexpression*:e (space dot sexpression:f)? sspace "]"	-> (set-list-source `(bracket ,@e ,@f) e)
		| "'"  sexpression:e						-> (list 'quote e)
		| "`"  sexpression:e						-> (list 'quasiquote e)
		| ",@" sexpression:e						-> (list 'unquote-splicing e)
		| ","  sexpression:e						-> (list 'unquote e)
		| "{"  space grammar:e	( "}"					-> e
					|					-> (error "error in grammar near: "(parser-context self))
					)
		| ";" (![\n\r] .)*
		;
scomment	= ";" (!eol .)* ;
sspace		= (blank | eol | scomment)* ;
sexpression	= sspace sexpr ;

llist		= lparen expression:e rparen			-> e ;
atom		= lparen expression:e rparen			-> e
		| quotesgl sexpression:e space			-> `(match-object ,e)
		| string:e					-> `(match-string ,e)
		| class:e					-> `(match-class ,e)
		| idpart:p "-" identifier:e			-> `(match-rule-in ,p ,e)
		| identifier:e					-> `(match-rule ,e)
		| lbrace sexpression*:e space rbrace		-> `(match-rule ,@e)
		| dot						-> `(match-any)
		| arrow sexpression:e space			-> `(result-expr ,e)
		| backquote llist:e				-> `(match-list ,e)
		;
repetition	= atom :e ( query				-> `(match-zero-one ,e)  :e
			  | star				-> `(match-zero-more ,e) :e
			  | plus				-> `(match-one-more ,e)  :e
			  )?					-> e ;
conversion	= repetition :e ( at				-> `(make-span	    ,e) :e
				| dollarhash ( number:n		-> `(make-number ,n ,e) :e
					     |			-> `(make-number 10 ,e) :e
					     )
				| dollardbl			-> `(make-symbol      ,e   ) :e
				| dollar			-> `(make-string      ,e   ) :e
				| colon identifier :i		-> `(assign-result ,i ,e   ) :e
				)*				-> e ;
predicate	= pling     conversion:e			-> `(peek-not  ,e)
		| ampersand ( arrow sexpression:e space		-> `(peek-expr ,e)
			    | conversion:e			-> `(peek-for  ,e)
			    )
		| conversion ;

require		= predicate:p	( tilde string:e		-> `(match-require ,p ,e)
				|				-> p
				) ;

sequence	= require:p	( require+:q			-> `(match-all ,p ,@q)
				|				-> p
				) ;

expression	= sequence:s	( (bar sequence)+:t		-> `(match-first ,s ,@t)
				|				-> s
				) ;

parameters	= (colon identifier)* ;

definition	= space identifier:id parameters:p
		  equals expression:e ";"			-> `(,id ,e ,p) ;

definitions	= definition* ;

varname		= symbol:s space -> s ;

parser_decl	= space varname:name colon varname:parent lparen (varname*):vars rparen	-> `(,name ,parent ,vars) ;

parser_spec	= parser_decl?:decl definition*:defns		-> `(,decl ,@defns) ;
