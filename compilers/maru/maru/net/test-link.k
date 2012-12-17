;;; net/test-link.k						-*- coke -*-
;;;
;;; This program prints all IP packets sent to the 10.42.42.0/24 subnet.
;;;
;;; Create an IP tunnel device called "tun42", assign it an IPv4 address of
;;; 10.42.42.42 and make it part of a 10.42.42.0/24 subnet; e.g (on Linux):
;;;
;;;	sudo openvpn --mktun --dev tun42
;;;	sudo ip link set tun42 up
;;;	sudo ip addr add 10.42.42.42/24 dev tun42
;;;
;;; Packets sent to any address (other than 10.42.42.42) on the 10.42.42.0
;;; subnet will now appear on tun42.
;;;
;;; Execute this file in a terminal window:
;;;
;;;	./eval net/test-link.k
;;;
;;; In another terminal window, generate some traffic on the 10.42.42.0 subnet;
;;; e.g:
;;;
;;;	ping 10.42.42.1
;;;
;;; The IP packet header and payload of each echo request will be printed in the
;;; first terminal widow, beginning with the digits 4 (IP protocol version
;;; number) and 5 (size in 32-bit words of the IP packet header).  24 digits
;;; into each line you should see 0a2a2a2a (source address 10.42.42.42) and
;;; 0a2a2a01 (destination address 10.42.42.1).
;;;
;;; When you are bored, terminate the programs in both windows and then delete
;;; the tunnel device:
;;;
;;;	sudo openvpn -rmtun --dev tun42

(require "net/link.k")

(net-link-receive "tun42" (| IFF_TUN IFF_NO_PI)
  (lambda (dev packet start len)
    (for (i start (+ start len)) (print (format "%02x" (byte-at packet i))))
    (println)))
