(require "net/tcp.k")

(define time (subr "time" "p"))
(define ctime (subr "ctime" "p"))

(define-function net-tcp-daytime (packet payload length)	;; answer the local date and time
  (let ((timep (data sizeof-long)))
    (time timep)
    (format "%s" (ctime timep))))

(net-tcp-register-handler 13 net-tcp-daytime)

(net-ip-start)
