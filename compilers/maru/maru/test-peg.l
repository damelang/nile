;; (require "parser.l")
;; (require "peg.l")
;; (require "peg-compile.l")

(let* ((g (input-stream-up-to (input-stream (open "peg.g") "peg.g") *end*))
       (s (string-stream g))
       (p (new <peg>))
       (r (array->list (parse-all p s))))
  ;;(map println r)
  ;;(println "----------------------------------------------------------------")
  (parse-from p (list-stream r) $gen_cola)
  (map dumpln (<parser>-result p))
  ($space p)
  (and (!= *end* (parser-stream-peek (<parser>-source p)))
       (println "ERROR NEAR: "(parser-stream-peek (<parser>-source p))))
  )
  
; (map println (array->list (parse-all (new <peg>) (string-stream peg-grammar-string))))

;(define peg-ir (array->list (parse-all (new <peg>) (string-stream peg-grammar-string))))

;(map println peg-ir)

;; (define-selector $repl)

;; (define-method $repl <peg-to-cola-parser> (source)
;;   (set self.source source)
;;   (while ($start self)
;;     (println (eval self.result))))

;; ($repl (parser-with-input <ir-to-cola-parser> (parser-with-input <peg-to-ir-parser> (input-stream *input*))))
