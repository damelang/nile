;;; net/icmp.k -- the Internet Control Message Protocol

(require "trie.k")

(require "net/ip.k")
(require "net/icmp.osdefs.k")

					       { diagram }
+-------------------------+-------------------------+-------------------------------------------------+
| 00 01 02 03 04 05 06 07 | 08 09 10 11 12 13 14 15 | 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 |
+-------------------------+-------------------------+-------------------------------------------------+
|           type          |           code          |                   checksum                      |
+-------------------------+-------------------------+-------------------------------------------------+
		     icmp -- Internet Control Message Protocol packet header [RFC 792]

(define *net-icmp-handlers* (trie-new))		;; icmp-type x icmp-code -> packet-handler

(define-function net-icmp-register-handler (icmp-type icmp-code packet-handler)
  (set-trie-at *net-icmp-handlers* (list icmp-type icmp-code) packet-handler))

(define-function icmp-print (icmp)
  (printf "type=%02x " (icmp:type icmp))
  (printf "code=%02x " (icmp:code icmp))
  (printf "sum=%04x\n" (icmp:checksum icmp)))

(define-function net-icmp-receive (dev src dst packet start length)
  (let ((icmp (+ packet start)))
    (print "ICMP\tRECV\t"length"\t") (icmp-print icmp)
    (let* ((icmp-type (icmp:type icmp))
	   (icmp-code (icmp:code icmp))
	   (handler   (trie-at *net-icmp-handlers* (list icmp-type icmp-code))))
      (if handler (handler dev src dst icmp-type icmp-code packet (+ start 4) (- length 4))
	(println "ignoring unhandled ICMP packet: type "icmp-type" code "icmp-code)))))

(define-function net-icmp-transmit (dev src dst type code packet start length)
  (decr start 4)
  (incr length 4)
  (let ((icmp (+ packet start)))
    (set (icmp:type     icmp) type)
    (set (icmp:code     icmp) code)
    (set (icmp:checksum icmp) 0)
    (set (icmp:checksum icmp) (^ 65535 (net-checksum packet start (+ start 4))))
    (print "ICMP\tSEND\t"length"\t") (icmp-print icmp)
    (net-ip-transmit dev src dst packet start length)))

(net-ip-register-handler net-ip-address IP_PROTO_ICMP net-icmp-receive)
