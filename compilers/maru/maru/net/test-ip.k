;;; net/test-ip.k						-*- coke -*-
;;;
;;; This program prints all IP packets sent to the 10.42.42.0/24 subnet.
;;;
;;; See net/test-link.k for instructions on setting up the virtual device, then
;;; run:
;;;
;;;	./eval net/test-ip.k

(require "net/ip.k")

(define-function handle-icmp (dev src dst packet start length)
  (for (i start (+ start length)) (print (format "%02x" (byte-at packet i))))
  (println))

(net-ip-register-handler net-ip-address IP_PROTO_ICMP handle-icmp)

(net-ip-start)
