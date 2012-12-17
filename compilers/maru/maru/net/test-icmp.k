;;; A server that answers ICMP ECHO (ping) requests.
;;;
;;; See net/test-link.k for instructions on setting up the virtual device, then
;;; run:
;;;
;;;	./eval net/test-icmp.k

(require "net/icmp.k")

(define-function net-icmp-echorequest (dev src dst type code packet start length)
  (net-icmp-transmit dev dst src ICMP_ECHOREPLY 0 packet start length))

(net-icmp-register-handler ICMP_ECHO 0 net-icmp-echorequest)

(net-ip-start)
