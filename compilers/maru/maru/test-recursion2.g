<r2> : <parser> ()

_       = [ \n\r]* ;

digit   = [0-9]:d		-> (println "\t\t\t\t\t$ "d) -> (- d ?0) ;

op      = "+" ;

term    = term:a op digit:b     -> (println "\t\t\t\t\t+ "a" "b) -> `(add ,a ,b)
        | digit:d               -> (println "\t\t\t\t\t# "d) -> d
        ;

program = (_ term)* ;
