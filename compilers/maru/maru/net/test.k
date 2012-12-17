;;; A small collection of internet services.
;;;
;;; See net/test-link.k for instructions on setting up the virtual device, then
;;; run:
;;;
;;;	./eval -O repl.l net/test.k
;;;
;;; Then choose between:
;;;
;;;	ping 10.42.42.1
;;;	telnet 10.42.42.1 13
;;;	your-www-browser http://10.42.42.1

;;; register ICMP services

(require "net/icmp.k")

(define-function net-icmp-echorequest (dev src dst type code packet start length)
  (net-icmp-transmit dev dst src ICMP_ECHOREPLY 0 packet start length))

(net-icmp-register-handler ICMP_ECHO 0 net-icmp-echorequest)

;;; register TCP services

(require "net/tcp.k")

(define time  (subr "time" "p"))
(define ctime (subr "ctime" "p"))

(define-function ascii-time-now ()
  (let ((timep (data sizeof-long)))
    (time timep)
    (format "%s" (ctime timep))))

(define-function net-tcp-daytime (packet payload length)	;; answer the local date and time
  (ascii-time-now))

(net-tcp-register-handler 13 net-tcp-daytime)

(define-function net-tcp-http (packet payload length)		;; answer HTTP requests
  (concat-strings
   "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN\"
<html><head>
<title>HTTP Server :: Maru</title>
</head><body>
<h1>Hello, Internet!</h1><p>This is the HTTP nanoserver running in Maru.  The current data and time are: "(ascii-time-now)"</p>
<hr>
<address>NanoHTTP/0.0.1 (Maru) server at "(net-ip-address-to-ascii net-ip-address)" port 80</address>
</body></html>"))

(net-tcp-register-handler 80 net-tcp-http)

;;; run the network

(net-ip-start)
