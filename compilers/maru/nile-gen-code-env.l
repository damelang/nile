(require "port.l")

(define *nile-gen-code-indent-width* 4)

(define-structure <nile-gen-code-env>
  (module-name bindings out-port indentation next-cvar-num cvars))

(define-function %nile-gen-code-env
  (module-name bindings out-port indentation next-cvar-num cvars)
  (let ((self (new <nile-gen-code-env>)))
    (set (<nile-gen-code-env>-module-name   self) module-name)
    (set (<nile-gen-code-env>-bindings      self) bindings)
    (set (<nile-gen-code-env>-out-port      self) out-port)
    (set (<nile-gen-code-env>-indentation   self) indentation)
    (set (<nile-gen-code-env>-next-cvar-num self) next-cvar-num)
    (set (<nile-gen-code-env>-cvars         self) cvars)
    self))

(define-function nile-gen-code-env (module-name)
  (%nile-gen-code-env module-name '() (string-port) 0 0 '()))

(define-method clone <nile-gen-code-env> (out-port)
  (%nile-gen-code-env self.module-name self.bindings out-port
                      self.indentation self.next-cvar-num self.cvars))

(define-method module-name <nile-gen-code-env> () self.module-name)
(define-method bindings    <nile-gen-code-env> () self.bindings)
(define-method out-port    <nile-gen-code-env> () self.out-port)
(define-method cvars       <nile-gen-code-env> () self.cvars)

(define-method set-bindings <nile-gen-code-env> (bindings)
  (set self.bindings bindings))

(define-method bind <nile-gen-code-env> (vardecl cvals)
  (set self.bindings (cons (cons vardecl cvals) self.bindings))
  cvals)

(define-method lookup <nile-gen-code-env> (_name)
  (cdr (list-detect (vardecl . cvals) self.bindings
    (= _name (name vardecl)))))

(define-method out-no-indent <nile-gen-code-env> args
  (apply port-write (cons (out-port self) args)))

(define-method out <nile-gen-code-env> args
  (port-indent (out-port self) self.indentation)
  (apply out-no-indent (cons self args)))

(define-method push-indent <nile-gen-code-env> ()
  (set self.indentation (+ self.indentation *nile-gen-code-indent-width*)))

(define-method pop-indent <nile-gen-code-env> ()
  (set self.indentation (- self.indentation *nile-gen-code-indent-width*)))

(define-method alloc-cvar <nile-gen-code-env> (type)
  (let ((cvar (format "v_%d" self.next-cvar-num)))
    (set self.next-cvar-num (+ self.next-cvar-num 1))
    (set self.cvars (cons (cons cvar type) self.cvars))
    cvar))
