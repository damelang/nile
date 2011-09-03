(define types (array))

{ <nile-parser> : <parser> ()
  newline	= ("\n""\r"* | "\r""\n"*) ;
  _             = " "* ;
  uppercase     = [ABCDEFGHIJKLMNOPQRSTUVWXYZ] ;
  lowercase     = [abcdefghijklmnopqrstuvwxyz] ;
  alpha         = (uppercase | lowercase) ;
  typename      = (uppercase alpha*)@$ ;
  fielddef      = alpha@$:name _ ":" _ typename:type -> (list name type) ;
  fielddefs     = "(" (_ fielddef _ ",")* _ fielddef _ ")" -> fdefs ;
  typedef       = "type " _ typename:name _ "=" _ fielddefs:fdefs _ newline -> (println name " " fdefs);
  program       = typedef* ;
}

(list-do path *arguments*
  (let ((program  (input-stream-up-to (input-stream (open path)) ())))
    ($program (parser <nile-parser> (parser-stream (string-stream program))))))

(println types)
