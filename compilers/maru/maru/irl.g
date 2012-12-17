# -*- coke -*-

# TODO:
#
# distinguish between lvals and rvals and have rval = ... | lval:l -> { (ir-get ,l) }
# ir-member should produce a ref to the member

<irl> : <text-parser> ()

blank		= [\t ] ;
eol		= "\n""\r"* | "\r""\n"* ;
comment1	= "//" (&. !eol .)* ;
commentN	= "/*" (&. !"*/" (commentN | .))* "*/" ;
comment		= comment1 | commentN ;
_		= (blank   | eol | comment)* ;

oigit		= [0-7] ;
digit		= [0-9] ;
higit		= [0-9A-Za-z] ;
letter		= [A-Z_a-z] ;

uinteger	= "0x" higit+ $#16:x _						-> x
		| "0"  oigit+ $#8 :x _						-> x
		|      digit+ $#10:x _						-> x
		;
integer		= "-"uinteger:x							-> (- x)
		|    uinteger
		;

ufloat		= (digit+ "."digit+ ("e"digit+)?)@$:s _				-> (string->double s) ;
float		= "-"ufloat:x							-> (- x)
		|    ufloat
		;

number		= float | integer ;

char		= "\\"	( "t"					->  9
			| "n"					-> 10
			| "r"					-> 13
			| "x" (higit higit) @$#16
			| "u" (higit higit higit higit) @$#16
			| .
			)
		| . ;

string		= "\"" ("\"\""->34 | !"\"" char)* $:x "\"" _			-> x ;

idpart		= (letter (letter | digit)*) @ $$ ;
identifier	= idpart:x !":" _						-> x ;

keyword		= !idpart _ ;

xtype		= type       ~"type" ;
xidentifier	= identifier ~"identifier" ;
xstatement	= statement  ~"statement" ;
xexpression	= expression ~"expression" ;

arglist		= expression?:a (","_ xexpression)*:b				-> `(,@a ,@b) ;

primary		= "false" keyword						-> '(ir-lit 0)
		| "true"  keyword						-> '(ir-lit 1)
		| identifier:e							-> `(ir-get ',e)
		| number:e							-> `(ir-lit ,e)
		| string:e							-> `(ir-lit ,e)
		| "("_ xexpression:e ")"_					-> e
		;

prefix		= "*"_ prefix:e							-> `(ir-get ,e)
		| "&"_ xidentifier:i						-> `(ir-addr ',i)
		| "struct" keyword xidentifier:a "("_ arglist:b ")"_		-> `(ir-struct ',a (list ,@b))
		| primary
		;

suffix		= prefix:a ( "("_ arglist:b ")"_				-> `(ir-call ,a (list ,@b))	:a
### FIX ME --->		   | "."_ xidentifier:b					-> `(ir-get (ir-member ',b ,a))	:a
			   | "."_ xidentifier:b					-> `(ir-member ',b ,a)		:a
			   | "["_ xexpression:b "]"_				-> `(ir-get (ir-add ,a ,b))	:a
			   )*							-> a
		;

factorop	= "*" -> 'ir-mul | "/" -> 'ir-div | "%" -> 'ir-mod ;

factor		= factor:a factorop:o _ suffix:b				-> `(,o ,a ,b)
		|			suffix
		;

termop		= "+" -> 'ir-add | "-" -> 'ir-sub ;

term		= term:a termop:o _ factor:b					-> `(,o ,a ,b)
		|		    factor
		;

relop		= "<=" -> 'ir-le | "<" -> 'ir-lt | "==" -> 'ir-eq | "!=" -> 'ir-ne | ">=" -> 'ir-ge | ">" -> 'ir-gt ;

relation	= term:a ( relop:o _ term:b					-> `(,o ,a ,b) :a
			 )?							-> a
		;

ifexp		= relation:a ("?"_ relation:b ":"_ expression:c			-> `(ir-ife ,a ,b ,c) :a
			     )*							-> a
		;

lval		= "*"_ prefix
		| prefix:p "["_ expression:e "]"_				-> `(ir-add ,p ,e)
		| identifier:i							-> `(quote ,i)
		;

expression	= lval:l ":="_ ifexp:r						-> `(ir-set ,l ,r)
		| ifexp
		;

#expression	= identifier:l ":="_ ifexp:r					-> `(ir-set ',l ,r)
#		| expression:l ":="_ ifexp:r					-> `(ir-set  ,l ,r)
#		| ifexp
#		;

#block		= "{"     _       statement*:s "}"   _				-> s
#		| "begin" keyword statement*:s "end" keyword			-> s
#		;

sequence	=  "{"_ statement*:s "}"_					-> `(ir-seq ,@s)
		| "begin" keyword statement*:s "end" keyword			-> `(ir-seq ,@s)
		;

mainclause	= sequence
		|   "if"     keyword xexpression:a
		    "then"   keyword xstatement:b
		  ( "else"   keyword xstatement )? :c					-> `(ir-ifs ,a ,b ,@c)
		|   "while"  keyword xexpression:e "do" keyword xstatement:s		-> `(ir-while ,e ,s)
		|   "return" keyword xexpression:e ";"_					-> `(ir-ret ,e)
		|   "let"    keyword xtype:t xidentifier:i ":="_ xexpression:e ";"_	-> `(ir-var ',i ,t ,e)
		|   "for"    keyword type?:t xidentifier:i ":="_ xexpression:a
                  ( "step"   keyword xexpression )?:b
		    "until"  keyword xexpression:c "do" keyword xstatement:s	-> `(ir-seq (ir-var ',i ,(or (car t) IR-INT) ,a)
											    (ir-var '_s ,(or (car t) IR-INT) ,(or (car b) '(ir-lit 1)))
											    (ir-var '__ ,(or (car t) IR-INT) ,c)
											    (ir-while (ir-le (ir-get ',i) (ir-get '__))
												      ,s
												      (ir-set ',i (ir-add (ir-get ',i) (ir-get '_s)))
												      ))
		| expression:e ";"_						-> e
		;

statement	= mainclause:s ( "where" keyword xtype:t xidentifier:i
				 ":="_ xexpression:e ";"_			-> `(ir-seq (ir-var ',i ,t ,e) ,s) :s
			       )?
			       ( "finally" keyword xstatement:f			-> `(ir-seq ,s ,f)
			       )?						-> s
		;

primtype	= "void"   keyword						-> IR-VOID
		| "char"   keyword						-> IR-INT8
		| "short"  keyword						-> IR-INT16
		| "int"	   keyword						-> IR-INT
		| "long"   keyword						-> IR-LONG
		| "float"  keyword						-> IR-FLOAT
		| "double" keyword						-> IR-FLOAT64
		| "struct" keyword xidentifier:i				-> `(ir-struct-type ir ',i)
		| "("_ type:t ")"_						-> t
		;

typelist	= type?:a type*:b						-> `(,@a ,@b) ;

type		= primtype:a ( "*"_						-> `(ir-pointer-to ,a) :a
			     | "("_ typelist:b ")"_				-> `(ir-function-type ir ,a (list ,@b)) :a
			     )*							-> a
		;

idlist		=       xidentifier:i						-> `(',i) :i
		  (","_ xidentifier:j						-> `(,@i ',j) :i
		  )*								-> i ;

mdecl		= type:t idlist:i ";"_						-> `(list ,t ,@i) ;

decl		= type:t identifier:i						-> `(,t ,i) ;

paramlist	= decl?:p (","_ decl)*:q					-> `(,@p ,@q) ;

fndecl		= type:t identifier:i "("_ paramlist:p ")"_			-> `(ir-fun ',i (ir-function-type ir ,t (list ,@(param-list-types p)))
										      ,@(param-list-decls p)) ;

fndefn		= fndecl:d statement:e						-> (concat-list d (list e)) ;

definition	= "struct" keyword xidentifier:i "{"_ mdecl*:d "}"_ ";"_	-> `(ir-def-struct ir ',i (list ,@d))
		| "import" keyword decl:d ";"_					-> `(ir-put ir (ir-ext ',(cadr d) ,(car d)))
		| type:t identifier:i ( ":="_ xexpression:e ";"_		-> `(ir-put ir (ir-def ',i ,t ,e))
				      | "("_ paramlist:p ")"_ xstatement:e	-> `(ir-put ir (ir-fun ',i
												       (ir-function-type ir ,t (list ,@(param-list-types p)))
												       (list ,@(param-list-decls p) ,e)))
				      )
		| statement:s							-> `(ir-put ir ,s)
		;

program		= _ definition*:p (!. ~"definition or expression")		-> p ;
