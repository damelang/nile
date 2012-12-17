(require "osdefs.k")

(define colmap)
(define colpos)
(define bitbeg)
(define rowlen)
(define rowbeg)
(define fieldmap)

(define ntohl  (subr "ntohl"  "i"))
(define htonl  (subr "htonl"  "i"))

(define-function make-field-getter (name field word-offset first-bit last-bit)
  (let* ((num-bits    (+ 1 (- last-bit first-bit)))
	 (designator `(int-at bits ,(/ word-offset (* 8 sizeof-int))))
	 (decoder    `(ntohl ,designator)))
    (if (< last-bit 31) (set decoder `(>> ,decoder ,(- 31 last-bit))))
    (if (< num-bits 32) (set decoder `(&  ,decoder ,(- (<< 1 num-bits) 1))))
    `(define-function ,(concat-symbols name ': field) (bits)
       ,decoder)))

(define-function make-field-setter (name field word-offset first-bit last-bit)
  (let* ((num-bits    (+ 1 (- last-bit first-bit)))
	 (designator `(int-at bits ,(/ word-offset (* 8 sizeof-int))))
	 (mask        (- (<< 1 num-bits) 1))
	 (value      'value))
    (if (< num-bits 32)	(set value `(& ,mask ,value)))
    (if (< last-bit 31) (set value `(<< ,value ,(- 31 last-bit))))
    (if (< last-bit 31) (set mask   (<<  mask   (- 31 last-bit))))
    (if (< num-bits 32)	(set value `(| (& ,(~ mask) (ntohl ,designator)) ,value)))
    `(define-function ,(concat-symbols 'set- name ': field) (bits value)
       (set ,designator (htonl ,value)))))

(define-function define-data-accessors (name fields)
  ;;(println "diagram "name" = "fields)
  (array-do field fields
    ;;(println name" : "field)
    (eval (make-field-getter name (car field) (cadr field) (caddr field) (cadddr field)))
    (eval (make-field-setter name (car field) (cadr field) (caddr field) (cadddr field)))
    ))

{
  error		=					-> (error "diagram error near: " (parser-context self)) ;
  eol		= "\r" "\n"* | "\n" "\r"*		-> (set  colpos 0) ;
  space		= " "					-> (incr colpos )
		| "\t"					-> (set  colpos (& -8 (+ colpos 8)))
		;
  comment	= [-+] (!eol .)* eol ;
  ws		= (space | comment | eol)* ;
  _		= space* ;
  bar		= "|"					-> (incr colpos) ;
  letter	= [a-zA-Z]				-> (incr colpos) ;
  digit		= [0-9]					-> (incr colpos) ;
  identifier	= (letter (letter | digit)*) @$$:i _	-> i ;
  number	= (digit+) @$#:n _			-> n ;
  columns	=					-> (set colmap (array))
		  bar		 			-> (set (array-at colmap colpos) 0)
  		  ( _ number:n (number:n)* bar		-> (set (array-at colmap colpos) n)
  		  )+ _					-> (set rowlen (+ n 1))
		  eol					-> (set rowbeg 0)
		  ws					-> (set fieldmap (array))
  		;
  row		= _ ( number:n				-> (set rowbeg n)
  		    ) ? bar				-> (set bitbeg (array-at colmap colpos))
  		  _ ( identifier:i bar			-> (array-append fieldmap (list i rowbeg bitbeg (array-at colmap colpos)))
							-> (set bitbeg (+ (array-at colmap colpos) 1))
  		      _ )+ eol ws			-> (incr rowbeg rowlen)
  		;
  name		= identifier:i (!eol .)* eol		-> i ;
  diagram	= ws columns row+ name:n		-> (define-data-accessors n fieldmap)
		| error
		;
}
