(require "libglfw.k")
(require "libglu.k")
(require "libgl.k")

(define rtri 0.0)

(define rquad 0.0)

(define-function resize-gl-scene (width height)
  (or (> height 0) (set height 1))
  (glViewport 0 0 width height)
  (glMatrixMode GL_PROJECTION)
  (glLoadIdentity)
  (gluPerspective 45.0 (/ (long->double width) (long->double height)) 0.1 100.0)
  (glMatrixMode GL_MODELVIEW))

(define-function init-gl (width height)
  (glClearColor 0.0 0.0 0.0 0.0)
  (glClearDepth 1.0)
  (glDepthFunc GL_LESS)
  (glEnable GL_DEPTH_TEST)
  (glShadeModel GL_SMOOTH)
  (resize-gl-scene width height))

(define-function draw-gl-scene ()
  (glClear (| GL_DEPTH_BUFFER_BIT GL_COLOR_BUFFER_BIT))
  (glLoadIdentity)
  (glTranslatef -1.5 0.0 -6.0)
  (glRotatef rtri 0.0 1.0 0.0);		;; Rotate The Pyramid On The Y axis 

  (glBegin GL_POLYGON);				;; start drawing a pyramid
  ;; front face of pyramid
  (glColor3f 1.0 0.0 0.0);			;; Set The Color To Red
  (glVertex3f 0.0  1.0  0.0);		        ;; Top of triangle (front)
  (glColor3f 0.0 1.0 0.0);			;; Set The Color To Green
  (glVertex3f -1.0 -1.0  1.0);		;; left of triangle (front)
  (glColor3f 0.0 0.0 1.0);			;; Set The Color To Blue
  (glVertex3f 1.0 -1.0  1.0);		        ;; right of traingle (front)	

  ;; right face of pyramid
  (glColor3f 1.0 0.0 0.0);			;; Red
  (glVertex3f  0.0  1.0  0.0);		;; Top Of Triangle (Right)
  (glColor3f 0.0 0.0 1.0);			;; Blue
  (glVertex3f  1.0 -1.0  1.0);		;; Left Of Triangle (Right)
  (glColor3f 0.0 1.0 0.0);			;; Green
  (glVertex3f  1.0 -1.0  -1.0);		;; Right Of Triangle (Right)

  ;; back face of pyramid
  (glColor3f 1.0 0.0 0.0);			;; Red
  (glVertex3f  0.0  1.0  0.0);		;; Top Of Triangle (Back)
  (glColor3f 0.0 1.0 0.0);			;; Green
  (glVertex3f  1.0 -1.0  -1.0);		;; Left Of Triangle (Back)
  (glColor3f 0.0 0.0 1.0);			;; Blue
  (glVertex3f -1.0 -1.0  -1.0);		;; Right Of Triangle (Back)

  ;; left face of pyramid.
  (glColor3f 1.0 0.0 0.0);			;; Red
  (glVertex3f  0.0  1.0  0.0);		;; Top Of Triangle (Left)
  (glColor3f 0.0 0.0 1.0);			;; Blue
  (glVertex3f -1.0 -1.0 -1.0);		;; Left Of Triangle (Left)
  (glColor3f 0.0 1.0 0.0);			;; Green
  (glVertex3f -1.0 -1.0  1.0);		;; Right Of Triangle (Left)
  (glEnd);					;; Done Drawing The Pyramid

  (glLoadIdentity );				;; make sure we're no longer rotated.
  (glTranslatef 1.5 0.0 -7.0);		;; Move Right 3 Units, and back into the screen 7
  (glRotatef rquad 1.0 1.0 1.0);		;; Rotate The Cube On X, Y, and Z
  (glBegin GL_QUADS);				;; start drawing the cube.
  ;; top of cube
  (glColor3f 0.0 1.0 0.0);			;; Set The Color To Blue
  (glVertex3f  1.0  1.0 -1.0);		;; Top Right Of The Quad (Top)
  (glVertex3f -1.0  1.0 -1.0);		;; Top Left Of The Quad (Top)
  (glVertex3f -1.0  1.0  1.0);		;; Bottom Left Of The Quad (Top)
  (glVertex3f  1.0  1.0  1.0);		;; Bottom Right Of The Quad (Top)
  ;; bottom of cube
  (glColor3f 1.0 0.5 0.0);			;; Set The Color To Orange
  (glVertex3f  1.0 -1.0  1.0);		;; Top Right Of The Quad (Bottom)
  (glVertex3f -1.0 -1.0  1.0);		;; Top Left Of The Quad (Bottom)
  (glVertex3f -1.0 -1.0 -1.0);		;; Bottom Left Of The Quad (Bottom)
  (glVertex3f  1.0 -1.0 -1.0);		;; Bottom Right Of The Quad (Bottom)
  ;; front of cube
  (glColor3f 1.0 0.0 0.0);			;; Set The Color To Red
  (glVertex3f  1.0  1.0  1.0);		;; Top Right Of The Quad (Front)
  (glVertex3f -1.0  1.0  1.0);		;; Top Left Of The Quad (Front)
  (glVertex3f -1.0 -1.0  1.0);		;; Bottom Left Of The Quad (Front)
  (glVertex3f  1.0 -1.0  1.0);		;; Bottom Right Of The Quad (Front)
  ;; back of cube.
  (glColor3f 1.0 1.0 0.0);			;; Set The Color To Yellow
  (glVertex3f  1.0 -1.0 -1.0);		;; Top Right Of The Quad (Back)
  (glVertex3f -1.0 -1.0 -1.0);		;; Top Left Of The Quad (Back)
  (glVertex3f -1.0  1.0 -1.0);		;; Bottom Left Of The Quad (Back)
  (glVertex3f  1.0  1.0 -1.0);		;; Bottom Right Of The Quad (Back)
  ;; left of cube
  (glColor3f 0.0 0.0 1.0);			;; Blue
  (glVertex3f -1.0  1.0  1.0);		;; Top Right Of The Quad (Left)
  (glVertex3f -1.0  1.0 -1.0);		;; Top Left Of The Quad (Left)
  (glVertex3f -1.0 -1.0 -1.0);		;; Bottom Left Of The Quad (Left)
  (glVertex3f -1.0 -1.0  1.0);		;; Bottom Right Of The Quad (Left)
  ;; Right of cube
  (glColor3f 1.0 0.0 1.0);			;; Set The Color To Violet
  (glVertex3f  1.0  1.0 -1.0);	        ;; Top Right Of The Quad (Right)
  (glVertex3f  1.0  1.0  1.0);		;; Top Left Of The Quad (Right)
  (glVertex3f  1.0 -1.0  1.0);		;; Bottom Left Of The Quad (Right)
  (glVertex3f  1.0 -1.0 -1.0);		;; Bottom Right Of The Quad (Right)
  (glEnd);					;; Done Drawing The Cube

  (incr rtri   2.50)
  (incr rquad -2.50))

(define-function *main* ()
  (init-libglfw)
  (init-libglu)
  (init-libgl)
  (glfwInit)
  (let ((w 640) (h 320))
    (glfwOpenWindow w h 8 8 8 8 32 0 GLFW_WINDOW)
    (glfwSetWindowTitle "Maru :: Hello World!")
    (init-gl w h)
    (let ((running 1))
      (while running
	(let ((winw (data sizeof-int))
	      (winh (data sizeof-int)))
	  (glfwGetWindowSize winw winh)
	  (or (and (= w (long-at winw 0)) (= h (long-at winh 0)))
	      (resize-gl-scene (set w (long-at winw 0)) (set h (long-at winh 0)))))
	(draw-gl-scene)
	(glfwSwapBuffers)
	;;(glfwWaitEvents)
	(glfwSleep 0.033)
	(set running (and (= 0 (glfwGetKey GLFW_KEY_ESC))
			  (= 1 (glfwGetWindowParam GLFW_OPENED))))
	)))
  (glfwTerminate)
  (exit 0))

(*main*)
