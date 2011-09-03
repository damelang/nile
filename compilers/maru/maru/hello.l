{ <nile> : <parser> ()

  blank = [\t\n\r ] ;
  comment = "{-".*"-}" ;
  _ = (blank | comment)* ;
  process-definition = ;
  program = (_ process-declaration)*:pdef -> (let ()
     (map peval (println p))
     (map peval (println e))
     (%run)) ;
}

{ nile-program }

Double : Real >> Real
    ∀ a
        >> 2 × a
