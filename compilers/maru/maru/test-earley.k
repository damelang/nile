(define-function array-last (arr) (array-at arr (- (array-length arr) 1)))

(define-method do-print <array> ()
  (let ((s ""))
    (print "Array<"(array-length self)">(")
    (array-do elt self (print s elt))
    (set s " ")
    (print ")")))

(define-structure <nonterminal> (name))         (define-function nonterminal? (x)       (= (type-of x) <nonterminal>))
(define-function nonterminal (x) (new <nonterminal> x))
(define-method do-print <nonterminal> () (print "<"self.name">"))

(define-structure <terminal> (token))                   (define-function terminal? (x)          (= (type-of x) <terminal>))
(define-function terminal (x) (new <terminal> x))
(define-method do-print <terminal> () (print "\""self.token"\""))

(define-structure <production> (name symbols))

(define-method do-print <production> ()
  (print "<production "self.name" ->")
  (array-do sym self.symbols (print " " sym))
  (print ">"))

(define-method print-tree <production> (i)
  (for (j 0 i) (print "  "))
  (print self.name" ->")
  (array-do sym self.symbols (print " " sym))
  (println))

(define-structure <state> (i production k left down))

(define-method do-print <state> ()
  (print "<state "self.i" "self.production" "self.k))

(define-method print-tree <undefined> (i p))

(define-method print-tree <state> (i p)
  (or (= p self.production)
     (let () 
       (print-tree self.production i)
       (incr i)))
  (print-tree self.left i self.production)
  (print-tree self.down i ()))

(define-function complete? (s)          (>= (<state>-i s) (array-length (<production>-symbols (<state>-production s)))))
(define-function incomplete? (s)        (<  (<state>-i s) (array-length (<production>-symbols (<state>-production s)))))

(define-function next-cat (state)       (array-at (<production>-symbols (<state>-production state)) (<state>-i state)))

(define-function state= (a b)
  (and (= (<state>-i          a) (<state>-i          b))
       (= (<state>-production a) (<state>-production b))
       (= (<state>-k          a) (<state>-k          b))))

(define-function state-advance (s)      (new <state> (+ (<state>-i s) 1) (<state>-production s) (<state>-k s)))

(define-function set-state-left-down (s l d)
  (set (<state>-left s) l)
  (set (<state>-down s) d)
  s)

(define-function chart-at (chart i)
  (or (array-at chart i)
      (set (array-at chart i)
           (array))))

(define-function array-state-for-production (a p)
  (let ((len (array-length a))
        (idx 0)
        (s   ()))
    (while (< idx len)
      (and (= (<state>-production (array-at a idx)) p)
           (set s (array-at a idx))
           (set idx len))
      (incr idx))
    s))

(define-function array-contains-state (a s)
  (let ((len (array-length a))
        (idx 0)
        (got ()))
    (while (< idx len)
      (and (state= (array-at a idx) s)
           (set got (array-at a idx) s)
           (set idx len))
      (incr idx))
    got))

(define-function chart-add-state (chart i prod)
  (let ((a (chart-at chart i)))
    (or (array-contains-state a prod)
        (array-append a prod))))

(define-function print-chart (chart)
  (for (i 0 (array-length chart))
    (print i)
    (let ((a (chart-at chart i)))
      (for (j 0 (array-length a))
        (println "\t"(array-at a j))))
    (println)
    ))

;;; ----------------

;; procedure PREDICTOR((A → α•B, i), j, grammar),
;;     for each (B → γ) in GRAMMAR-RULES-FOR(B, grammar) do
;;         ADD-TO-SET((B → •γ, j), chart[ j])
;;     end

(define-function predictor (chart state j grammar)              ;;(println "PREDICTOR "state" "j)
  (let ((B (<nonterminal>-name (next-cat state))))              ;;(println "predicting for nonterm "B)
    (array-do prod grammar                                      ;;(println "    checking "prod)
      (and (= B (<production>-name prod))                       ;;(println "predicting "prod" from "state)
           (chart-add-state chart j (new <state> 0 prod j)))))  ;;(println "-------- predicted") (print-chart chart) (println "--------")
  )

;; procedure SCANNER((A → α•B, i), j),
;;     if B ⊂ PARTS-OF-SPEECH(word[j]) then
;;         ADD-TO-SET((B → word[j], i), chart[j + 1])
;;     end

(define-function scanner (words chart state j)                  ;;(println "SCANNER "state" "j)
  (let ((tok (<terminal>-token (next-cat state))))              ;;(println "scanning for term "tok)
    (and (= tok (array-at words j))                             ;;(println "scanning "tok" from "state)
         (set-state-left-down
           (chart-add-state chart (+ j 1) (state-advance state))
           state ())))                                          ;;(println "-------- scanned") (print-chart chart) (println "--------")
  )

;; procedure COMPLETER((B → γ•, j), k),
;;     for each (A → α•Bβ, i) in chart[j] do
;;         ADD-TO-SET((A → αB•β, i), chart[k])
;;     end

(define-function completer (chart state k)                      ;;(println "COMPLETER "state" "k)
  (let ((X (<production>-name (<state>-production state)))
        (j (<state>-k state)))
    (array-do s (chart-at chart j)                              ;;(println "checking "s" . "(next-cat s))
      (let ((Y (next-cat s)))
        (and (nonterminal? Y)
             (= X (<nonterminal>-name Y))                       ;;(println "completing "s" from "state)
             (set-state-left-down
               (chart-add-state chart k (state-advance s))
               s state)))))                                     ;;(println "-------- completed") (print-chart chart) (println "--------")
  )

;; function EARLEY-PARSE(words, grammar)
;;     ENQUEUE((γ → •S, 0), chart[0])
;;     for i ← from 0 to LENGTH(words) do
;;         for each state in chart[i] do
;;             if INCOMPLETE?(state) then
;;                 if NEXT-CAT(state) is a nonterminal then
;;                     PREDICTOR(state, i, grammar)         // non-terminal
;;                 else do
;;                     SCANNER(state, i)                    // terminal
;;             else do
;;                 COMPLETER(state, i)
;;         end
;;     end
;;     return chart

(define-function earley-parse (words grammar)
  (let ((chart (array)))
    (array-append (chart-at chart 0) (new <state> 0 (array-at grammar 0) 0))
    (for (i 0 (+ 1 (array-length words)))					;;(println "POSITION "i)
      (let* ((Si  (chart-at chart i))
             (idx 0))
        (while (< idx (array-length Si))
          (let ((state (array-at Si idx)))
            (if (incomplete? state)
                (if (nonterminal? (next-cat state))
                    (predictor chart state i grammar)
                  (scanner words chart state i))
              (completer chart state i)))
          (set idx (+ idx 1)))))
    chart))

;;; ----------------

(define-function earley-test (words grammar)
  (print "input: ") (for-each words print) (println)
  (let ((chart (earley-parse words grammar)))
    ;;(println "---------------- output") (print-chart chart)
    (let ((s (array-state-for-production (array-last chart) (array-at grammar 0))))
      (if s
          (let ()
            (println "derivation:")
            (print-tree s 0 ()))
        (println "no match")))))

(println "\nleft-recursive expression grammar...\n")

(earley-test
  (list->array '(1 + 2 * 3))
  (list->array
    (list
      (new <production> 'P (list->array (list (nonterminal 'S))))
      (new <production> 'S (list->array (list (nonterminal 'S) (terminal '+) (nonterminal 'M))))
      (new <production> 'S (list->array (list (nonterminal 'M))))
      (new <production> 'M (list->array (list (nonterminal 'M) (terminal '*) (nonterminal 'T))))
      (new <production> 'M (list->array (list (nonterminal 'T))))
      (new <production> 'T (list->array (list (terminal 0))))
      (new <production> 'T (list->array (list (terminal 1))))
      (new <production> 'T (list->array (list (terminal 2))))
      (new <production> 'T (list->array (list (terminal 3))))
      (new <production> 'T (list->array (list (terminal 4))))
      (new <production> 'T (list->array (list (terminal 5))))
      (new <production> 'T (list->array (list (terminal 6))))
      (new <production> 'T (list->array (list (terminal 7))))
      (new <production> 'T (list->array (list (terminal 8))))
      (new <production> 'T (list->array (list (terminal 9)))))))

(println "\nright-recursive expression grammar...\n")

(earley-test
  (list->array '(1 + 2 * 3))
  (list->array
    (list
      (new <production> 'P (list->array (list (nonterminal 'S))))
      (new <production> 'S (list->array (list (nonterminal 'M) (terminal '+) (nonterminal 'S))))
      (new <production> 'S (list->array (list (nonterminal 'M))))
      (new <production> 'M (list->array (list (nonterminal 'T) (terminal '*) (nonterminal 'M))))
      (new <production> 'M (list->array (list (nonterminal 'T))))
      (new <production> 'T (list->array (list (terminal 0))))
      (new <production> 'T (list->array (list (terminal 1))))
      (new <production> 'T (list->array (list (terminal 2))))
      (new <production> 'T (list->array (list (terminal 3))))
      (new <production> 'T (list->array (list (terminal 4))))
      (new <production> 'T (list->array (list (terminal 5))))
      (new <production> 'T (list->array (list (terminal 6))))
      (new <production> 'T (list->array (list (terminal 7))))
      (new <production> 'T (list->array (list (terminal 8))))
      (new <production> 'T (list->array (list (terminal 9)))))))
