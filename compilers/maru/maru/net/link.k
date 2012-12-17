(require "net/link.osdefs.k")
(require "define-data.k")

(define net-link-device "tun42")
(define net-ip-address 0x0a2a2a01)	;; 10.42.42.1

(define-constant dev-tun "/dev/net/tun")

(define-data ifreq
  (ifr_name	char IFNAMSIZ)
  (ifr_flags	short)
  (padding	char 14))

(define %perror	(subr "perror"	"s"))
(define %open	(subr "open"	"si"))
(define %close	(subr "close"	"i"))
(define %read	(subr "read"	"ipi"))
(define %write	(subr "write"	"ipi"))
(define %ioctl	(subr "ioctl"	"ii"))

(define-function open-tunnel (dev flags)
  (let ((ifr (new-ifreq))
	(fd  (%open dev-tun O_RDWR)))
    (when (>= fd 0)
      (for (i 0 (data-length ifr)) (set (byte-at ifr i) 0))
      (and dev (for (i 0 IFNAMSIZ) (set (ifreq-ifr_name ifr i) (or (string-at dev i) 0))))
      (set (ifreq-ifr_flags ifr) flags)
      (let ((err (%ioctl fd TUNSETIFF ifr)))
	(when (< err 0)
	  (%close fd)
	  (set fd -1))))
    fd))

(define-function net-link-transmit (fd buf start length)
  (or (= start 0)			(error "net-link-transmit incorrect start: "start))
  (or (= length (%write fd buf length))	(error "net-link-transmit incomplete write: "fd" "buf" "length)))

(define-function net-link-receive (dev flags handler)
  (let ((fd (open-tunnel dev flags)))
    (when (< fd 0) (%perror dev) (exit 1))
    (println "link "dev" running")
    (let ((buf    (data 65536))
	  (length 0))
      (while (>= length 0)
	(set length (%read fd buf (data-length buf)))
	(when (> length 0) (handler fd (address-of buf) 0 length))))
    (%close fd)
    (exit 0)))
