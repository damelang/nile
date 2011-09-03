(define-structure <matrix> (rows cols))

(define-function matrix (x y)
  (let ((m (array x)))
    (for (n 0 x) (set-array-at m n (array y)))
    m))

(define-function matrix-at (m . indices)
  (list-do idx indices (set m (array-at m idx)))
  m)

(define-function set-matrix-at (m x y v)
  (set-array-at (array-at m x) y v))

(define-function make-agent-accessors (name fields i)
  (and (pair? fields)
       (cons `(, (car fields) () ((name) (list 'oop-at 'self ,i)))
	     (make-agent-accessors name (cdr fields) (+ i 1)))))
  
(define-form with-agent-accessors (type . body)
  `(with-forms ,(make-agent-accessors type (array-at %structure-fields (eval type)) 0)
    (let () ,@body)))

(define-selector %run-agent)

(define-function process (name fields expr)
  (peval `(define-structure ,name ,(cons '%next fields)))
  (let ((idx  1))
    (list-do field fields
      (peval `(define-method ,(concat-symbol '# field) ,name () (oop-at self ,idx)))
      (peval `(define-method ,(concat-symbol '# field) <undefined> ()))
      (peval `(define-method ,(concat-symbol 'set-# field) ,name (value) (set-oop-at self ,idx value)))
      (peval `(define-method ,(concat-symbol 'set-# field) <undefined> ()))
      (set idx (+ idx 1))))
  (peval `(define-method %run-agent ,name () (with-agent-accessors ,name ,expr)))
  (peval name))

(define-form member-at (obj name)	(list (concat-symbol '# name) obj))

(define %agents)

(define-function make-agent (type . args)
  (let ((self (new type))
	(idx  0))
    (list-do arg args (set-oop-at self (set idx (+ idx 1)) arg))
    (set-oop-at self 0 %agents)
    (set %agents self)))

(define-function %run ()
  (while 1
    (let ((agent %agents))
      (while agent
	(%run-agent agent)
	(set agent (oop-at agent 0))))))

{ <mpl> : <parser> ()

  blank		= [\t\n\r ] ;
  comment	= ";;"(![\n\r].)* ;
  _		= (blank | comment)* ;
  digit		= [0123456789] ;
  number	= "-" number:n							-> (- n)
		| digit+ $#:d _							-> d ;
  letter	= [ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz] ;
  name		= ( letter (letter | digit)* ) @ $$ :id _			-> id ;
  string	= "\"" (!"\"".)* @ $ :s "\"" _					-> s ;

  literal	= number | string
		| "true"_		-> ''t
		| "false"_		-> '()
		;

  element	= name:n ( "["_ expression:e (","_ expression)*:f "]"_		-> `(matrix-at ,n ,e ,@f):n
			 | "."_ name:f						-> `(member-at ,n ,f):n
			 )*							-> n
		;

  primary	= literal | element
		| "("_ expression:e ")"_ -> e
		;

  factor	= primary:a ( "*" _ factor:b	-> `(* ,a ,b)
			    | "/" _ factor:b	-> `(/ ,a ,b)
			    |			-> a
			    )
		;

  term		= factor:a ( "+" _ term:b   _	-> `(+ ,a ,b)
			   | "-" _ term:b   _	-> `(- ,a ,b)
			   |			-> a
			   )
		;

  relation	= "~"_ relation:a		-> `(not ,a)
		| term:a ( "<"  _ term:b   _	-> `(<  ,a ,b)
			 | "<=" _ term:b   _	-> `(<= ,a ,b)
			 | "="  _ term:b   _	-> `(=  ,a ,b)
			 | "~=" _ term:b   _	-> `(!= ,a ,b)
			 | ">=" _ term:b   _	-> `(>= ,a ,b)
			 | ">"  _ term:b   _	-> `(>  ,a ,b)
			 |			-> a
			 )
		;

  conjunct	= relation:a ( "&&"  _ conjunct:b   _	-> `(and ,a ,b)
			     |				-> a
			     )
		;

  disjunct	= conjunct:a ( "||"  _ disjunct:b   _	-> `(or ,a ,b)
			     |				-> a
			     )
		;

  expression	= name:n "="_  expression:e ".."_ expression:f ","_ expression:x	-> `(let ((,n ,e) (_ ,f)) (while (<= ,n _) ,x (set ,n (+ ,n 1))))
		| name:n "="_  expression:e ","_ expressions:f				-> `(let ((,n ,e)) ,@f)
		| element:n ":="_ expression:e						-> `(set ,n ,e)
		| name:n "(" expression?:a (","_ expression)*:b ")"_			-> `(make-agent ,n ,@a ,@b)
		| "if"_ expression:c expression:a ( "else"_ expression:b		-> `(if ,c ,a ,b)
						  |					-> `(if ,c ,a)
						  )
		| "print"_ arguments:a							-> `(println ,@a)
		| disjunct:e								-> e
		| compound
		;

  arguments	= expression:e (","_ expression)*:f				-> `(,e ,@f) ;

  expressions	= expression:e (";"_ expression)*:f				-> `(,e ,@f) ;

  compound	= "{"_ expressions:f (";"_)? "}"_				-> `(let () ,@f) ;

  arraydecl	= name:s "="_ "["_ number:n -> (list n):n
                            ( ","_ number:m -> `(,@n ,m):n )* "]"_		-> `(define ,s (matrix ,@n)) ;

  procdecl	= name:s ":"_ name*:fields compound:expr			-> `(define ,s (process ',s ',fields ',expr)) ;

  declaration	= arraydecl | procdecl ;

  program	= (_ declaration)*:p expressions:e ";"?				-> (let ()
										     (map peval (println p))
										     (map peval (println e))
										     (%run)) ;
}

{ mpl-program }

world = [64,64]

cell : x y alive state {
  n = 0,
  dx = -1 .. 1,
    dy = -1 .. 1,
      if ~(dx = 0 && dy = 0) && world[x + dx, y + dy].alive
        n := n + 1;
  if alive state := n = 2 || n = 3
  else     state := n = 3;
  if state ~= alive
    if   state print x, " ", y, " ", 1
    else       print x, " ", y, " ", 0;
  if x = 0 && y = 0 {
    print "---";
    xx = 0 .. 63,
      yy = 0 .. 63,
        world[xx, yy].alive := world[xx, yy].state;
  };
}

x = 0 .. 63,  y = 0 .. 63,  world[x, y] := cell(x, y);

x = 26 .. 35, { world[x, 32].alive := true;  print x, " ", 32, " ", 1; };

print "---";
