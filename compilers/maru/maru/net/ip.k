;; net-ip.k										-*- coke -*-

(require "define-data.k")
(require "trie.k")

(require "net/structure-diagram.k")
(require "net/link.k")

						 { diagram }
+-------------+-------------+-------------------------+----------+----------------------------------------+
| 00 01 02 03 | 04 05 06 07 | 08 09 10 11 12 13 14 15 | 16 17 18 | 19 20 21 22 23 24 25 26 27 28 29 30 31 |
+-------------+-------------+-------------------------+----------+----------------------------------------+
|   version   |  headerSize |      typeOfService      |                     length                        |
+-------------+-------------+-------------------------+----------+----------------------------------------+
|                     identification                  |  flags   |                  offset                |
+---------------------------+-------------------------+----------+----------------------------------------+
|       timeToLive          |         protocol        |                    checksum                       |
+---------------------------+-------------------------+---------------------------------------------------+
|                                               sourceAddress                                             |
+---------------------------------------------------------------------------------------------------------+
|                                             destinationAddress                                          |
+---------------------------------------------------------------------------------------------------------+
			       ip -- Internet Protocol packet header [RFC 791]

(define-data <protoent>
  (p_name	pointer)
  (p_aliases	pointer)
  (p_proto	int))

(define get-proto-by-name (subr "getprotobyname" "s"))

(define IP_PROTO_ICMP	(<protoent>-p_proto (get-proto-by-name "icmp")))
(define IP_PROTO_TCP	(<protoent>-p_proto (get-proto-by-name "tcp")))

(define ip-print
  (lambda (ip)
    (printf "v=%x "       (ip:version ip))
    (printf "hl=%x "      (ip:headerSize ip))
    (printf "tos=%02x "   (ip:typeOfService ip))
    (printf "len=%04x "   (ip:length ip))
    (printf "id=%04x "    (ip:identification ip))
    (printf "flags=%x "   (ip:flags ip))
    (printf "off=%04x "   (ip:offset ip))
    (printf "ttl=%02x "   (ip:timeToLive ip))
    (printf "proto=%02x " (ip:protocol ip))
    (printf "sum=%04x "   (ip:checksum ip))
    (printf "src=%08x "   (ip:sourceAddress ip))
    (printf "dst=%08x\n"  (ip:destinationAddress ip))))

(define-function net-ip-address-to-ascii (addr)
  (concat-strings (long->string (& 255 (>> addr 24)))
	      "." (long->string (& 255 (>> addr 16)))
	      "." (long->string (& 255 (>> addr  8)))
	      "." (long->string (& 255     addr    ))))

(define-function net-checksum (ip start end)
  (let ((sum 0))
    (for (i start (- end 1) 2)
      (incr sum (+ (<< (& 255 (byte-at ip i)) 8) (& 255 (byte-at ip (+ i 1))))))
    (if (= 1 (& end 1))
	(incr sum (<< (& 255 (byte-at ip (- end 1))) 8)))
    (while (> sum 65535) (set sum (+ (& sum 65535) (>> sum 16))))
    sum))

(define-function ip-compute-checksum (ip)	(net-checksum ip 0 20))

(define *net-ip-handlers* (trie-new))	;; ip-addr x ip-proto -> packet-handler

(define-function net-ip-register-handler (ip-addr ip-proto handler)
  (set-trie-at *net-ip-handlers* (list ip-addr ip-proto) handler))

(define-function net-ip-transmit (dev src dst packet start length)
  (decr start 20)
  (incr length 20)
  (let ((ip (+ packet start)))
    (set (ip:length             ip) length)
    (set (ip:timeToLive         ip) 64)
    (set (ip:sourceAddress      ip) src)
    (set (ip:destinationAddress ip) dst)
    (set (ip:checksum           ip) 0)
    (set (ip:checksum           ip) (^ 0xffff (ip-compute-checksum ip)))
    (print "IP\tSEND\t"length"\t") (ip-print (+ packet start)))
  (net-link-transmit dev packet start length))

(define-function net-ip-receive (dev packet start length)
  (let ((ip (+ packet start)))
    (print "IP\tRECV\t"length"\t") (ip-print ip)
    (or (= 0xffff (ip-compute-checksum ip)) (error "bad ip checksum: "   (ip-compute-checksum ip)))
    (or (= 4      (ip:version          ip)) (error "bad ip version: "    (ip:version          ip)))
    (or (= 5 	  (ip:headerSize       ip)) (error "bad ip headerSize: " (ip:headerSize       ip)))
    (or (= length (ip:length           ip)) (error "bad ip length: "     (ip:length           ip)))
    (let* ((ip-src   (ip:sourceAddress      ip))
	   (ip-dst   (ip:destinationAddress ip))
	   (ip-proto (ip:protocol           ip))
	   (handler  (trie-at *net-ip-handlers* (list ip-dst ip-proto))))
      (if handler (handler dev ip-src ip-dst packet (+ start 20) (- length 20))
	(println "ignoring unhandled IP packet from "(format "%08x" ip-src)" to "(format "%08x" ip-dst)" proto "ip-proto)))))

(define-function net-ip-start ()
  (net-link-receive net-link-device (| IFF_TUN IFF_NO_PI) net-ip-receive))

(unit-test "ip"
  (let (;; 13:57:13.037224 IP 10.8.0.6 > 10.8.0.6: ICMP echo request, id 52599, seq 0, length 64
	;;         0x0000:  4500 0054 1931 0000 4001 4d5d 0a08 0006  E..T.1..@.M]....
	;;         0x0010:  0a08 0006 0800 dfa7 cd77 0000 5049 7ea9  .........w..PI~.
	;;         0x0020:  0000 90ea 0809 0a0b 0c0d 0e0f 1011 1213  ................
	;;         0x0030:  1415 1617 1819 1a1b 1c1d 1e1f 2021 2223  .............!"#
	;;         0x0040:  2425 2627 2829 2a2b 2c2d 2e2f 3031 3233  $%&'()*+,-./0123
	;;         0x0050:  3435 3637                                4567
	(str "\x45\x00\x00\x54\x19\x31\x00\x00\x40\x01\x4d\x5d\x0a\x08\x00\x06\x0a\x08\x00\x06")
	(ip  (data 20)))
    (for (i 0 20) (set (byte-at ip i) (string-at str i)))
    ;;(ip-print ip)
    (unit-assert (=             4 (ip:version            ip)))
    (unit-assert (=             5 (ip:headerSize         ip)))
    (unit-assert (=             0 (ip:typeOfService      ip)))
    (unit-assert (=            84 (ip:length             ip)))
    (unit-assert (=        0x1931 (ip:identification     ip)))
    (unit-assert (=             0 (ip:flags              ip)))
    (unit-assert (=             0 (ip:offset             ip)))
    (unit-assert (=            64 (ip:timeToLive         ip)))
    (unit-assert (= IP_PROTO_ICMP (ip:protocol           ip)))
    (unit-assert (=        0x4d5d (ip:checksum           ip)))
    (unit-assert (=    0x0a080006 (ip:sourceAddress      ip)))
    (unit-assert (=    0x0a080006 (ip:destinationAddress ip)))
    (unit-assert (=        0xffff (ip-compute-checksum   ip)))))
