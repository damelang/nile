;; From: Bryan Ford
;; Subject: [PEG] Fun with left recursion
;;
;; Left recursion in PEGs indeed seems like an interesting can of worms.  For those
;; interested, I'm wondering how a few example grammars behave under your preferred
;; left-recursive parsing technique, and how you think they should behave.

(define peg-make-definition peg-make-definition-with-memo)

(define-function input-between (a b)	(list->string (list-from-to a b)))

{
  sync    = (!"." .)* "." ;

  beg	  =       -> (<parser-stream>-position self.source) ;
  end     = .:beg -> (println "input matched: \""(input-between beg (<parser-stream>-position self.source))"\"") sync ;
  fail    =       -> (println "could not match input") sync ;

  space   = [ \t] ;
  eol     = [\n\r] ;
  blank   = space | eol ;
  comment = "//" (!eol .)* ;
  _       = (blank | comment)* ;
}

;; First, a trivially evil left-recursive grammar:
;;
;; S <- S
;;
;; For example, does your parser detect and reject this somehow, or does it behave the same
;; as 'S <- f'?  (I hope it doesn't result in an infinite loop at runtime anyway. :) )

{
  S = S ;
  _ beg:b S {end b} | fail
}

hello.

;; Now a grammar that's weird, not necessarily evil, in a slightly more subtle way:
;;
;; S <- S / a
;;
;; Does this behave the same as 'S <- a', or do something else?  How should it behave?

{
  S = S | "a" ;
  _ beg:b S {end b} | fail
}

a.

;; Cranking up the evilness factor one notch with a mutually left-recursive grammar...
;;
;; S <- T / a
;; T <- S / &a
;;
;; Given the input string "a", does this behave the same as 'S <- a' (succeeding
;; and consuming) or the same as 'S <- &a' (succeeding but consuming no input)?

{
  S = T | "a" ;
  T = S | &"a" ;
  _ beg:b S {end b} | fail
}

a.

;; Do S and T behave the same way or differently?  Should they?

{ _ beg:b T {end b} | fail }

a.

;; Now, another grammar that's not necessarily evil but strange in a slightly different way:
;;
;; S <- Saa / a /
;;
;; Given the input string 'aaaa', for example, does/should this grammar consume just 3 or
;; all 4 a's, or does it do something else?  What should it do?

{
  S = S "a" "a" | "a" | -> () ;
  _ beg:b S {end b} | fail
}

aaaa.

;; ---------------- OUTPUT FROM THIS PROGRAM ----------------
;;
;; could not match input
;; input matched: "a"
;; input matched: ""
;; input matched: "a"
;; input matched: "a"
