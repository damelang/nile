# -*- fundamental -*-

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
sinteger	= "0x"(higit+) @$#16
		|     (digit+) @$#
		;
sexpr		= "-" sinteger:i						-> (- i)
		| sinteger
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
					|					-> (error "error in grammar near: "(parser-stream-context self.source))
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

sequence	= predicate:p	( predicate+:q			-> `(match-all ,p ,@q)
				|				-> p
				) ;

expression	= sequence:s	( (bar sequence)+:t		-> `(match-first ,s ,@t)
				|				-> s
				) ;

parameters	= (colon identifier)* ;

definition	= space identifier:id parameters:p
		  equals expression:e ";"			-> `(,id ,e ,p) ;

definitions	= definition* ;

start		= (parser_class | definitions):result
		  ;

varname		= symbol:s space -> s ;

parser_decl	= space varname:name colon varname:parent lparen (varname*):vars rparen	-> `(,name ,parent ,vars) ;

parser_class	= parser_decl:decl
		  definition*:definitions
		  space (!. |					-> (error "error in grammar near: "(parser-stream-context self.source))
                        )
		  {gen_cola_parser (car decl) (cadr decl) (caddr decl) definitions}
		;

parser_spec	= parser_decl?:decl definition*:defns		-> `(,decl ,@defns) ;

#----------------------------------------------------------------

gen_cola_parser	= .:name .:parent .:vars .:definitions		-> (set (<peg>-grammar-name self) name)
		  {gen_cola definitions}:definitions		-> `((define-class ,name ,parent ,vars) ,@definitions) ;

gen_cola		= &gen_cola_value_declarations:a
			  &gen_cola_effect_declarations:b
			  &gen_cola_value_definitions:c
			   gen_cola_effect_definitions:d	-> `( ,@a ,@b ,@c ,@d ) ;

gen_cola_value_declarations	= `( gen_cola_value_declaration* :d ) -> d ;
gen_cola_effect_declarations	= `( gen_cola_effect_declaration*:d ) -> d ;

gen_cola_value_declaration	= `( .:id )			-> `(define-selector ,(concat-symbol '$ id)) ;
gen_cola_effect_declaration	= `( .:id )			-> `(define-selector ,(concat-symbol '$$ id)) ;

gen_cola_value_definitions	= `( gen_cola_value_definition* :d ) -> d ;
gen_cola_effect_definitions	= `( gen_cola_effect_definition*:d ) -> d ;

gen_cola_value_definition	= `( .:id &{findvars ()}:vars value:exp )  -> `(peg-define-rule ,(concat-symbol  '$ id) ,(<peg>-grammar-name self) ,vars ,exp) ;
gen_cola_effect_definition	= `( .:id &{findvars ()}:vars effect:exp ) -> `(peg-define-rule ,(concat-symbol '$$ id) ,(<peg>-grammar-name self) ,vars ,exp) ;

findvars = .:vars `( 'assign-result .:name {findvars vars}:vars		   -> (if (assq name vars) vars (cons (cons name) vars))
		   | 'result-expr		-> vars
		   | . ({findvars vars}:vars)*	-> vars
		   |				-> vars
		   ) ;

value =
`( 'match-rule .:name .+:args		-> `(let ((pos (<parser-stream>-position self.source)))
   	       	      			      ,@(map (lambda (arg) (list 'parser-stream-push 'self.source arg)) args)
					      (or (peg-match-rule ,(concat-symbol '$ name) self)
						  (let () (set (<parser-stream>-position self.source) pos) ())))
 | 'match-rule .:name			-> `(peg-match-rule ,(concat-symbol '$ name) self)
 | 'match-rule-in .:type .:name .+:args	-> `(let ((pos (<parser-stream>-position self.source))
						  (_p  (parser ,(concat-symbol '< (concat-symbol type '>)) self.source)))
  					        ,@(map (lambda (arg) (list 'parser-stream-push 'self.source arg)) args)
  						(if (peg-match-rule ,(concat-symbol '$ name) _p)
						    (let () (set self.result (<parser>-result _p)) 1)
						  (let () (set (<parser-stream>-position self.source) pos) ())))
 | 'match-rule-in .:type .:name		-> `(let ((_p  (parser ,(concat-symbol '< (concat-symbol type '>)) self.source)))
					      (and (peg-match-rule ,(concat-symbol '$ name) _p)
						   (let () (set self.result (<parser>-result _p)) 1)))
 | 'match-first value+:exps		-> `(or ,@exps)
 | 'match-all (&(..) effect)*:e value:v	-> `(let ((pos (<parser-stream>-position self.source)))
					      (or (and ,@e ,v) (let () (set (<parser-stream>-position self.source) pos) ())))
 | 'match-zero-one value:exp		-> `(let ((_list_ (group)))
   		   			      (and ,exp (group-append _list_ self.result))
 					      (set self.result (group->list! _list_))
 					      1)
 | 'match-zero-more value:exp		-> `(let ((_list_ (group)))
   		    			      (while ,exp (group-append _list_ self.result))
 					      (set self.result (group->list! _list_))
 					      1)
 | 'match-one-more value:exp		-> `(let ((_list_ (group)))
     		   			      (while ,exp (group-append _list_ self.result))
 					      (and (not (group-empty? _list_))
 					      	   (let ()
 						     (set self.result (group->list! _list_))
 						     1)))
 | 'peek-for value:exp			-> `(let ((pos (<parser-stream>-position self.source)))
					      (and ,exp (set (<parser-stream>-position self.source) pos)))
 | 'peek-expr .:exp			-> exp
 | 'peek-not value:exp			-> `(not (let ((pos (<parser-stream>-position self.source)))
						   (and ,exp (set (<parser-stream>-position self.source) pos))))
 | 'match-list value:exp		-> `(and (pair? (parser-stream-peek self.source))
 					      (let ((src self.source))
 					        (set self.source (parser-stream (list-stream (parser-stream-peek src))))
 						(let ((ok ,exp))
 						  (set self.source src)
 						  (and ok (parser-stream-next src)))))
 | 'match-class  .:str			-> `(set self.result (parser-stream-match-class self.source ,(make-class str)))
 | 'match-string .:str			-> `(set self.result (parser-stream-match-string self.source ,str))
 | 'match-object .:obj			-> `(and (= ',obj (parser-stream-peek self.source))
 					         (set self.result (parser-stream-next self.source)))
 | 'match-any				-> '(and (!= *end* (parser-stream-peek self.source))
					      (let () (set self.result (parser-stream-next self.source)) 1))
 | 'make-span effect:exp		-> `(let ((pos (<parser-stream>-position self.source)))
 					      (and ,exp
 					           (let ()
 						     (set self.result (list-from-to pos (<parser-stream>-position self.source)))
 						     1)))
 | 'make-string value:exp		-> `(and ,exp (set self.result (list->string self.result)))
 | 'make-symbol value:exp		-> `(and ,exp (set self.result (string->symbol (list->string self.result))))
 | 'make-number .:r value:exp		-> `(and ,exp (set self.result (string->number-base (list->string self.result) ,r)))
 | 'assign-result .:name value:exp	-> `(and ,exp (let () (set ,name self.result) 1))
 | 'result-expr .:exp			-> `(let () (peg-source-range-begin self) (set self.result ,exp) (peg-source-range-end self) 1)
 | .:op					->  (error "cannot generate value for "op)
 |					->  (error "cannot generate value for nil")
 ) ;

effect =
`( 'match-rule .:name .+:args		-> `(let ((pos (<parser-stream>-position self.source)))
   	       	      			      ,@(map (lambda (arg) (list 'parser-stream-push 'self.source arg)) args)
					      (or (peg-match-rule ,(concat-symbol '$$ name) self)
					      (let () (set (<parser-stream>-position self.source) pos) ())))
 | 'match-rule .:name			-> `(peg-match-rule ,(concat-symbol '$$ name) self)
 | 'match-rule-in .:type .:name .+:args	-> `(let ((pos (<parser-stream>-position self.source)))
         				      (let ()
  					        ,@(map (lambda (arg) (list 'parser-stream-push 'self.source arg)) args)
  						(or (peg-match-rule ,(concat-symbol '$$ name)
						      (parser ,(concat-symbol '< (concat-symbol type '>)) self.source))
						    (let () (set (<parser-stream>-position self.source) pos) ()))))
 | 'match-rule-in .:type .:name		-> `(peg-match-rule ,(concat-symbol '$$ name)
					      (parser ,(concat-symbol '< (concat-symbol type '>)) self.source))
 | 'match-first     effect+:exps	-> `(or ,@exps)
 | 'match-all       effect*:e		-> `(let ((pos (<parser-stream>-position self.source)))
					      (or (and ,@e) (let () (set (<parser-stream>-position self.source) pos) ())))
 | 'match-zero-one  effect:exp		-> `(let () ,exp 1)
 | 'match-zero-more effect:exp		-> `(let () (while ,exp) 1)
 | 'match-one-more  effect:exp		-> `(and ,exp (let () (while ,exp) 1))
 | 'peek-for        effect:exp		-> `(let ((pos (<parser-stream>-position self.source)))
					      (and ,exp (set (<parser-stream>-position self.source) pos)))
 | 'peek-expr .:exp			-> exp
 | 'peek-not	    effect:exp		-> `(not (let ((pos (<parser-stream>-position self.source)))
						   (and ,exp (set (<parser-stream>-position self.source) pos))))
 | 'match-list      effect:exp		-> `(and (pair? (parser-stream-peek self.source))
 					      (let ((src self.source))
 					        (set self.source (parser-stream (list-stream (parser-stream-peek src))))
 						(let ((ok ,exp))
 						  (set self.source src)
 						  (and ok (parser-stream-next src)))))
 | 'match-class   .:str			-> `(parser-stream-match-class  self.source ,(make-class str))
 | 'match-string  .:str			-> `(parser-stream-match-string self.source ,str)
 | 'match-object  .:obj			-> `(parser-stream-match-object self.source ',obj)
 | 'match-any				-> '(parser-stream-match-any    self.source)
 | 'make-span     effect:exp		->  exp
 | 'make-string   effect:exp		->  exp
 | 'make-symbol   effect:exp		->  exp
 | 'make-number .:r effect:exp		->  exp
 | 'assign-result .:name value:exp	-> `(and ,exp (let () (set ,name self.result) 1))
 | 'result-expr   .:exp			-> `(let () (peg-source-range-begin self) ,exp (peg-source-range-end self) 1)
 | .:op					->  (error "cannot generate value for "op)
 |					->  (error "cannot generate value for nil")
 ) ;
