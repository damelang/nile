(define column 0)
(define result (array))

{ <offside> : <parser> ()

  space		= " "					-> (set column (+ 1 column))
		| "\t"					-> (set column (& -8 (+ 8 column))) ;

  newline	= ("\n""\r"* | "\r""\n"*)		-> (set column 0) ;

  name		= [abcdefghijklmnopqrstuvwxyz]+$:n	-> (array-append result (cons column n)) ;

  program	= (space* name? newline)* "." ;
}

{ offside-program }

this
is
a
  test
  of
     the
     offside
  parsing
.

(println result)
