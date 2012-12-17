;;; net-tcp.k -- the Transmission Control Protocol (over IP)

(require "net/ip.k")

						   { diagram }
+-------------+----------+----------+-------------------+-------------------------------------------------+
| 00 01 02 03 | 04 05 06 | 07 08 09 | 10 11 12 13 14 15 | 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 |
+-------------+----------+----------+-------------------+-------------------------------------------------+
|                       sourcePort                      |                 destinationPort                 |
+-------------------------------------------------------+-------------------------------------------------+
|                                                 sequenceNumber                                          |
+---------------------------------------------------------------------------------------------------------+
|                                              acknowledgementNumber                                      |
+-------------+----------+----------+-------------------+-------------------------------------------------+
|    offset   | reserved |   ecn    |    controlBits    |                    window                       |
+-------------+----------+----------+-------------------+-------------------------------------------------+
|                       checksum                        |                 urgentPointer                   |
+-------------------------------------------------------+-------------------------------------------------+
			tcp -- Transmission Control Protocol packet header [RFC 793]

(define-constant TCP_FIN  1)
(define-constant TCP_SYN  2)
(define-constant TCP_RST  4)
(define-constant TCP_PSH  8)
(define-constant TCP_ACK 16)

(define-function tcp-print (tcp)
  (printf "sport=%04x " (tcp:sourcePort tcp))
  (printf "dport=%04x " (tcp:destinationPort tcp))
  (printf "seq=%u "     (tcp:sequenceNumber tcp))
  (printf "ack=%u "     (tcp:acknowledgementNumber tcp))
  (printf "off=%d "     (tcp:offset tcp))
  (printf "flags=%02x " (tcp:controlBits tcp))
  (printf "win=%04x "   (tcp:window tcp))
  (printf "sum=%04x "   (tcp:checksum tcp))
  (printf "urg=%04x\n"  (tcp:urgentPointer tcp)))

(define-function tcp-compute-checksum (saddr daddr tcp length)
  (println "TCP CHECKSUM "(format "%08x" saddr)" "(format "%08x" daddr)" "length)
  (let ((cks (sum (& saddr 65535) (>> saddr 16)
		  (& daddr 65535) (>> daddr 16)
		  IP_PROTO_TCP
		  length
		  (net-checksum tcp 0 length))))
    (while (> cks 65535) (set cks (+ (& cks 65535) (>> cks 16))))
    (println "TCP CHECKSUM = "(format "%04x" cks))
    cks))

(define *net-tcp-handlers*	(array))

(define-selector receive)

(define-function net-tcp-transmit (dev saddr daddr sport dport seq ack flags packet start length)
  (decr start 20)
  (incr length 20)
  (let ((tcp (+ packet start)))
    (set (tcp:sourcePort	    tcp) sport)
    (set (tcp:destinationPort	    tcp) dport)
    (set (tcp:sequenceNumber	    tcp) seq)
    (set (tcp:acknowledgementNumber tcp) ack)
    (set (tcp:controlBits	    tcp) flags)
    (set (tcp:offset		    tcp) 5)
    (set (tcp:checksum		    tcp) 0)
    (set (tcp:checksum		    tcp) (^ 0xffff (tcp-compute-checksum saddr daddr tcp length)))
    (print "TCP\tSEND\t"length"\t") (tcp-print tcp)
    (net-ip-transmit dev saddr daddr packet start length)))

(define-function net-tcp-receive (dev saddr daddr packet start length)
  (let ((tcp (+ packet start)))
    (print "TCP\tRECV\t"length"\t") (tcp-print tcp)
    (let ((flags (tcp:controlBits tcp)))
      (if (= 0 (& flags TCP_RST))
	  (let* ((sport   (tcp:sourcePort	     tcp))
		 (dport   (tcp:destinationPort	     tcp))
		 (seqno   (tcp:sequenceNumber	     tcp))
		 (ackno   (tcp:acknowledgementNumber tcp))
		 (flags   (tcp:controlBits           tcp))
		 (offset  (* 4 (tcp:offset tcp)))
		 (payload (+ start  offset))
		 (datalen (- length offset))
		 (finlen  (+ datalen (if (= 0 (& flags TCP_FIN)) 0 1)))
		 (handler (array-at *net-tcp-handlers* dport)))
	    (println "TCP\tPORT\t"dport":\t"datalen" bytes")
	    (if handler
		(if (!= 0 (& flags TCP_SYN))
		    (net-tcp-transmit     dev daddr saddr dport sport    -1 (+ seqno       1) (| TCP_ACK TCP_SYN        ) packet  (+ start 20)         0)
		  (if (= 0 ackno)	;; (and (= 0 ackno) (> datalen 0))
		      (let ((reply (handler packet payload datalen)))
			(set payload (+ start 20))
			(set datalen (string-length reply))
			(for (i 0 datalen) (set-byte-at packet (+ payload i) (string-at reply i)))
			(net-tcp-transmit dev daddr saddr dport sport     0 (+ seqno finlen) (| TCP_ACK (| TCP_PSH TCP_FIN)) packet payload datalen))
		    (if (> datalen 0)
			(net-tcp-transmit dev daddr saddr dport sport ackno (+ seqno finlen)    TCP_ACK		        packet (+ start 20)        0))))
	      (println "SEND ACK-RST")
	      (net-tcp-transmit		dev daddr saddr dport sport ackno (+ seqno       1) (| TCP_ACK TCP_RST        ) packet (+ start 20)        0)))))))

(define-function net-tcp-register-handler (port handler)
  (set (array-at *net-tcp-handlers* port handler)))		;;;(new <net-tcp-listen> handler))))

(net-ip-register-handler net-ip-address IP_PROTO_TCP net-tcp-receive)
