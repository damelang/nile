(require "osdefs.k")
(require "libgezira.k")
(require "libglfw.k")
(require "libglu.k")
(require "gl-texbuf.k")
(require "matrix.k")

(define-function data-with-floats floats
  (let* ((n (list-length floats))
	 (d (data (* n sizeof-float)))
	 (i -1))
    (list-do f floats (set-float-at d (incr i) f))
    d))

(define window-width	512)
(define window-height	512)
(define n-threads	1)
(define mem-size	(* 1000000 n-threads))

(define flake-alpha	0.7)
(define flake-red	0.8)
(define flake-green	0.9)
(define flake-blue	1.0)

(define angle  0.0)
(define dangle 0.01)

(define-function clear (image process a r g b)
  (nile_Process_feed
   (nile_Process_pipe
     (gezira_RectangleSpans process 0.0 0.0 (long->double (<gezira-image>-width image)) (long->double (<gezira-image>-height image)))
     (gezira_CompositeUniformColorOverImage_ARGB32 process image a r g b)
     0)
   0 0))

(define-function render (image process points npoints)
  (let ((m (matrix)))
    (set m (matrix-translate m (/ window-width 2.0) (/ window-height 2.0)))
    (set m (matrix-rotate    m angle))
    (let ((pipeline (nile_Process_pipe
		      (gezira_TransformBeziers	process M.a M.b M.c M.d M.e M.f)
		      (gezira_ClipBeziers	process 0.0 0.0 (long->double window-width) (long->double window-height))
		      (gezira_Rasterize		process)
		      (gezira_CompositeUniformColorOverImage_ARGB32 process image flake-alpha flake-blue flake-green flake-red)
		      0)))
      (nile_Process_feed pipeline points npoints))
    (incr angle dangle)
    ))

(define path (data-with-floats
	       -200.0 -200.0	-100.0    0.0	   0.0  200.0
	          0.0  200.0	 100.0    0.0	 200.0 -200.0
	        200.0 -200.0       0.0 -200.0	-200.0 -200.0))

(define path-size (/ (data-length path) sizeof-float))

(define-function display (texbuf)
  (glClear GL_COLOR_BUFFER_BIT)
  (glLoadIdentity)
  (gl-render texbuf))

(define-function *main* ()
  (init-dlopen)
  (init-libgezira)
  (init-libglfw)
  (init-libglu)
  (init-libgl)
  (glfwInit)
  (let ((w window-width) (h window-height))
    (glfwOpenWindow w h 8 8 8 8 0 0 GLFW_WINDOW)
    (glfwSetWindowTitle "Maru :: Gezira")
    (let* ((texbuf  (texbuf window-width window-height 0 0))
	   (image   (new-<gezira-image>))
	   (memory  (data mem-size))
	   (process (nile_startup memory mem-size 1)))
      (gezira_Image_init image (<texbuf>-bits texbuf) window-width window-height (<texbuf>-stride texbuf))
      (let ((running 1))
	(while running
	  (clear image process 1.0 0.0 0.0 0.0)
	  (render image process path path-size)
	  (nile_sync process)
	  (display texbuf)
	  (glfwSwapBuffers)
	  (glfwSleep 0.025)
	  (set running (and (= 0 (glfwGetKey GLFW_KEY_ESC))
			    (= 1 (glfwGetWindowParam GLFW_OPENED))))))
      (nile_sync process)
      (nile_shutdown process)
      (glfwTerminate)
      (exit 0))))

(*main*)
