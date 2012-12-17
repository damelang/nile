(require "osdefs.k")

(define *dlopen-path* (list "" "./" "/lib/" "/usr/lib/" "/usr/local/lib/" "/opt/X11/lib/" "/opt/local/lib/" "/usr/X11/lib/"))

(define *dlopen-suffix*
  (cond
    ((defined? '__APPLE__)	".dylib")
    ((defined? '__WIN32__)	".dll")
    (else			".so")))

(define-function init-dlopen ()
  (define %dlopen  (subr "dlopen" "si"))
  (define %dlsym   (subr "dlsym"  "ps"))
  (define %dlerror (subr "dlerror" "" )))

(define-function dlopen (name)
  (let ((filename (concat-string name *dlopen-suffix*))
	(dirnames *dlopen-path*)
	(lib      0))
    (while (and (= 0 lib) dirnames)
      (let ((pathname (concat-string (car dirnames) filename)))
	;;(println pathname)
	(set lib (%dlopen pathname (| RTLD_NOW RTLD_GLOBAL)))
	;;(and (= 0 lib) (println pathname": "(format "%s" (%dlerror))))
	(set dirnames (cdr dirnames))))
    (and (= 0 lib) (error "could not load: "name))
    ;;(println name": "lib)
    lib))

(define-function dlextern (lib-name sym-name signature)
  (let ((addr (%dlsym RTLD_DEFAULT sym-name)))
    (when (= 0 addr)
      (dlopen lib-name)
      (set addr (%dlsym RTLD_DEFAULT sym-name)))
    (when (= 0 addr)
      (error "could not find external symbol: "sym-name))
    (or (subr sym-name signature)
	(error "could not make external subr: "sym-name))))
