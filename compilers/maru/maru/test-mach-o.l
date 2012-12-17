(require "buffer.k")

(define code (buffer-new 4096))	;; binary
(define phased 1)		;; non-nil if something changed this pass
(define $% 0)			;; file offset
(define $$ 0)			;; last .org address
(define $ 0)			;; current address

(define-selector _B  (gen value)	(buffer-write code value) (incr $))
(define-selector _W  (gen value)	(_B gen (& 255 value))   (_B gen (& 255   (>> value 8))))
(define-selector _L  (gen value)	(_W gen (& 65535 value)) (_W gen (& 65535 (>> value 16))))
(define-selector _D1 (gen value)	(_B gen value))
(define-selector _D4 (gen value)	(_L gen value))

(require "asm-x86.k")

(define-function define-label (name value)
  (or (= (eval name) value)
      (let ()
	(eval (list 'set name value))
	(set phased 1))))

(define-function .org (addr)		(set $$ (set $ (eval addr))))
(define-form	 .equ (name expr)	(define-label name (eval expr)) ())
(define-function .byte bytes		(list-do byte bytes (_B () (eval byte))))
(define-function .long longs		(list-do long longs (_L () (eval long))))
(define-function .ascii strings		(list-do string strings (string-do char string (_B () char))))

(define-function movlIR (src dst)	(MOVLir () src dst))
(define-function inclR (dst)		(INCLr () dst))
(define-function pushlI (src)		(PUSHLi () src))
(define-function addlIR (src dst)	(ADDLir () src dst))
(define-function sublIR (src dst)	(SUBLir () src dst))
(define-function intI (src)		(_B () 0xCD) (_B () src))

(define-function assemble (program)
;;  (let ((asm (assembler-new)))
    (list-do insn program
      (cond
        ((symbol? insn)		(eval (list 'define insn 0)))
	((= '.equ (car insn))	(eval (list 'define (cadr insn) 0)))))
    (set phased 1)
    (while phased
      (set phased ())
      (buffer-reset code)
      (set $$ (set $ (buffer-address code)))
      (list-do insn program
        (cond
	  ((symbol? insn)	(define-label insn $))
	  ((pair? insn)		(eval insn))
	  (else			(error "huh? "insn)))))
    ;;(println "assembled "(buffer-size code)" bytes")
;;    )
    )

(assemble '(
	(.org	0x1000)
	(.long	0xFeedFace)			; magic
	(.long	7)				; CPU_TYPE_X86
	(.long	3)				; CPU_SUBTYPE_I386_ALL
	(.long	2)				; MH_EXECUTE
	(.long	2)				; ncmds
	(.long	(- start cmd0))			; cmdsize
	(.long	0)				; flags
cmd0	(.long	1)				; LC_SEGMENT
	(.long	(- cmd1 cmd0))			; cmdsize
	(.ascii	"__TEXT")			; segname
	(.byte	0 0 0 0 0 0 0 0 0 0)		; segname
	(.long	0x1000)				; vmaddr
	(.long	0x1000)				; vmsize
	(.long	0)				; fileoff
	(.long	filesize)			; filesize
	(.long	7)				; maxprot
	(.long	5)				; initprot
	(.long	1)				; nsects
	(.long	0)				; flags
	(.ascii	"__text")			; sectname
	(.byte	0 0 0 0 0 0 0 0 0 0)		; sectname
	(.ascii	"__TEXT")			; segname
	(.byte	0 0 0 0 0 0 0 0 0 0)		; segname
	(.long	start)				; addr
	(.long	(- end start))			; size
	(.long	(- start 0x1000))		; offset
	(.long	2)				; align
	(.long	0)				; reloff
	(.long	0)				; nreloc
	(.long	0)				; flags
	(.long	0)				; reserved1
	(.long	0)				; reserved2
cmd1	(.long	5)				; LC_UNIXTHREAD
	(.long	(- start cmd1))			; cmdsize
	(.long	1)				; i386_THREAD_STATE
	(.long	16)				; i386_THREAD_STATE_COUNT
	(.long	0 0 0 0 0 0 0 0)		; state
	(.long	0 0 start 0 0 0 0 0)		; state
start	(pushlI	msglen)				; strlen(buffer)
	(pushlI	msg)				; buffer
	(pushlI	1)				; stdout
	(movlIR	4 _EAX)				; write
	(sublIR	4 _ESP)				; syscall
	(intI	0x80)
	(addlIR	16 _ESP)			; pop args
	(pushlI	0)				; status
	(movlIR	1 _EAX)				; exit
	(sublIR	4 _ESP)				; syscall
	(intI	0x80)
msg	(.ascii	"Hello, world\n\0")
	(.equ	msglen (- $ msg))
	(.equ	filesize (- $ $$))
end	))

(buffer-save code "a.out")

(assemble '(
	(pushlI	msglen)				; strlen(buffer)
	(pushlI	msg)				; buffer
	(pushlI	1)				; stdout
	(movlIR	4 _EAX)				; write
	(sublIR	4 _ESP)				; syscall
	(intI	0x80)
	(addlIR	16 _ESP)			; pop args
	(pushlI	0)				; status
	(movlIR	1 _EAX)				; exit
	(sublIR	4 _ESP)				; syscall
	(intI	0x80)
msg	(.ascii	"Now run ./a.out for a friendly greeting\n\0")
	(.equ	msglen (- $ msg))))

(buffer-call code 0)
