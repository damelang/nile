(require "dlopen.k")

(define-function init-libglu ()
  (init-dlopen)
  (let ((lib "libGLU"))
    (define gluPerspective	(dlextern lib "gluPerspective"	"dddd"))))
