(require "buffer.k")

(define code (buffer-new 4096))	;; binary
(define phased 1)		;; non-nil if something changed this pass
(define $% 0)			;; file offset
(define $$ 0)			;; last .org address
(define $ 0)			;; current address

(define-selector _B  (gen value)	(buffer-write code value) (incr $))
(define-selector _W  (gen value)	(_B gen (& 255 value))	 (_B gen (& 255	  (>> value 8))))
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
(define-function .half halfs		(list-do half halfs (_W () (eval half))))
(define-function .long longs		(list-do long longs (_L () (eval long))))
(define-function .ascii strings		(list-do string strings (string-do char string (_B () char))))

(define-function movlIR (src dst)	(MOVLir () src dst))
(define-function inclR (dst)		(INCLr () dst))
(define-function pushlI (src)		(PUSHLi () src))
(define-function addlIR (src dst)	(ADDLir () src dst))
(define-function sublIR (src dst)	(SUBLir () src dst))
(define-function intI (src)		(_B () 0xCD) (_B () src))

(define-function assemble (program)
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
	((symbol? insn)		(define-label insn $))
	((pair? insn)		(eval insn))
	(else			(error "huh? "insn)))))
  ;;(println "assembled "(buffer-size code)" bytes")
  )

(assemble '(
	(.org	0x08048000)
ehdr	(.byte	0x7f)				;   ident
	(.ascii	"ELF")
	(.byte	1 1 1 0)
	(.byte	0 0 0 0 0 0 0 0)
	(.half	2)				;   type
	(.half	3)				;   machine
	(.long	1)				;   version
	(.long	start)				;   entry
	(.long	(- phdr $$))			;   phoff
	(.long	0)				;   shoff
	(.long	0)				;   flags
	(.half	ehdrsize)			;   ehsize
	(.half	phdrsize)			;   phentsize
	(.half	1)				;   phnum
	(.half	0)				;   shentsize
	(.half	0)				;   shnum
	(.half	0)				;   shstrndx
	(.equ	ehdrsize (- $ ehdr))
phdr	(.long	1)				;   type
	(.long	0)				;   offset
	(.long	$$)				;   vaddr
	(.long	$$)				;   paddr
	(.long	filesize)			;   filesz
	(.long	filesize)			;   memsz
	(.long	5)				;   flags
	(.long	0x1000)				;   align
	(.equ	phdrsize (- $ phdr))
start	(movlIR	4 _EAX)
	(movlIR	1 _EBX)
	(movlIR	msg _ECX)
	(movlIR	msglen _EDX)
	(intI	0x80)
	(movlIR	1 _EAX)
	(movlIR	0 _EBX)
	(intI	0x80)
msg	(.ascii	"Hello, world\n")
	(.equ	msglen (- $ msg))
	(.equ	filesize (- $ $$))
end	))

(buffer-save code "a.out")

(assemble '(
	(movlIR	4 _EAX)				; write
	(movlIR	1 _EBX)				; stdout
	(movlIR	msg _ECX)			; buffer
	(movlIR	msglen _EDX)			; strlen(buffer)
	(intI	0x80)
	(movlIR	1 _EAX)				; exit
	(movlIR	0 _EBX)				; status
	(intI	0x80)
msg	(.ascii	"Now run ./a.out for a friendly greeting\n")
	(.equ	msglen (- $ msg))))

(buffer-call code 0)
