(define column 0)
(define result (array))

{ <offside> : <parser> ()

  space		= " "					-> (set column (+ 1 column))
		| "\t"					-> (set column (& -8 (+ 8 column))) ;

  newline	= ("\n""\r"* | "\r""\n"*)		-> (set column 0) ;

  name		= [abcdefghijklmnopqrstuvwxyz]+$:n	-> (array-append result (cons column n)) ;

  program	= (space* name? newline)* "." ;
}

(list-do path *arguments*
  (let ((program  (input-stream-up-to (input-stream (open path)) ())))
    ($program (parser <offside> (parser-stream (string-stream program))))))

(println result)
