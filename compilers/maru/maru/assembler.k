;;; TODO
;;;
;;; remove the duplicate labels
;;; - from calls of assembler-new-label where no new label should be made
;;; - from labels corresponding to $ and $$
;;;
;;; make .proc params and .locals be local to the enclosing .proc
;;;
;;; make (.proc name ...) enter name into a list of procs storing signature, nlocals and narguments
;;; .leave updates the proc struct with current <assembler>-locals and <assembler>-arguments
;;; if different, there is a phase change
;;; .enter uses the <proc> struct copies of -locals and -arguments
;;;
;;; .call verifies calls against <proc> signatures
;;;
;;; labels should evaluate to <memory> structures not to <long>s
;;;
;;; figure out a way to specify the address of a label for pushing addresses of message buffers

(require "buffer.k")
(require "scope.k")
(require "define-class.l")

(define-structure <segment> (name sections))

;;(define-method do-print <segment> ()	(print "<segment "self.name">"))
(define-method do-print <segment> ()	(print self.name))


(define-structure <section> (name segment data origin pc org-relocation))

;;(define-method do-print <section> ()	(print "<section "self.name" "self.segment">"))
;;(define-method do-print <section> ()	(print self.segment"."self.name))
(define-method do-print <section> ()	(print self.name))

(define-function section-set-origin (section addr)
  (set (<section>-origin section) addr)
  (set (<section>-pc     section) addr))

(define-function section-reset (section)
  (buffer-reset (<section>-data section))
  (section-set-origin section (buffer-address (<section>-data section)))
  section)

(define-function section-write-byte (sec byte)
  (incr (<section>-pc sec))
  (buffer-write (<section>-data sec) byte))


(define-structure <deref> (value))

(define-method do-print <deref> ()	(print "<deref "self.value">"))


(define-structure <label> (name section address))

;;(define-method do-print <label> ()	(print "<label "self.name" "self.section"="self.address">"))
(define-method do-print <label> ()	(print "<"(format "%08X" self.address)">"self.section"."self.name))

(define-function label? (obj)		(= <label> (type-of obj)))


(define-structure <relocation> (section offset label absolute displacement))

(define-method do-print <relocation> ()	(print "<relocation "self.section"+"self.offset" = "(if self.absolute "abs" "rel")" "self.label"+"self.displacement">"))

(define-function relocation-label-name (rel)	(<label>-name    (<relocation>-label rel)))
(define-function relocation-label-section (rel)	(<label>-section (<relocation>-label rel)))
(define-function relocation-label-address (rel)	(<label>-address (<relocation>-label rel)))

(define-function relocation-add (rel off)	(incr (<relocation>-displacement rel) off) rel)


(define-structure <register> (name encoding))


(define-structure <temporary> (name offset register))

(define-method do-print <temporary> ()	(print "<temporary "self.name"="self.offset">"))


(define-structure <assembler> (scope section phased locals arguments segments sections labels relocations))

(define-function assembler-get-segment (asm segment-name)
  (or (cdr  (assq segment-name (<assembler>-segments asm)))
      (cdar (push (<assembler>-segments asm) (cons segment-name (new <segment> segment-name))))))

(define-function assembler-get-section (asm segment-name section-name)
  (let ((segment (assembler-get-segment asm segment-name)))
    (or (cdr  (assq section-name (<segment>-sections segment)))
	(cdar (push (<segment>-sections segment) (cons section-name (section-reset (new <section> section-name segment (buffer-new 1024)))))))))

(define-function assembler-offset (asm)				(<buffer>-size (<section>-data (<assembler>-section asm))))
(define-function assembler-origin (asm)				(<section>-origin (<assembler>-section asm)))
(define-function assembler-pc (asm)				(<section>-pc (<assembler>-section asm)))
(define-function assembler-write-byte (asm byte)		(section-write-byte (<assembler>-section asm) byte))

(define-function assembler-new-label (asm name)			(let ((label (new <label> name (<assembler>-section asm) (assembler-pc asm))))
								  (push (<assembler>-labels asm) label)
								  label))

(define-function assembler-new-extern (asm name)		(let ((label (new <label> name (assembler-get-section asm '__EXTERN '__extern) 0)))
								  (push (<assembler>-labels asm) label)
								  label))

(define-function assembler-add-relocation (asm rel)		(set (<relocation>-offset rel) (assembler-offset asm))
								(push (<assembler>-relocations asm) rel))

(define-multimethod _B  ((<assembler> asm) (<long> val))	;;(println (format "%02X" val))
								(assembler-write-byte asm val))
(define-multimethod _W  ((<assembler> asm) (<long> val))	(_B asm val) (_B asm (>> val 8)))
(define-multimethod _L  ((<assembler> asm) (<long> val))	(_W asm val) (_W asm (>> val 16)))
(define-multimethod _L  ((<assembler> asm) (<relocation> val))	(assembler-add-relocation asm val) (_L asm 0))
(define-multimethod _D1 ((<assembler> asm) (<long> val))	(_B asm val))
(define-multimethod _D4 ((<assembler> asm) (<long> val))	(_L asm (- (- val (assembler-pc asm)) 4)))

(define-multimethod _D4 ((<assembler> asm) (<relocation> rel))	(set (<relocation>-absolute rel) ())
								(relocation-add rel -4)
								(assembler-add-relocation asm rel)
								(_L asm 0))

(require "asm-x86.k")

(define-function assembler-set-section (asm segment-name section-name)
  (set (<assembler>-section asm) (assembler-get-section asm segment-name section-name)))

(define %eax ())

(define-function assembler-new ()
  (let* ((scope (scope-new ()))
	 (asm   (new <assembler> scope)))
    (scope-define scope '%eax (set %eax (new <register> 'eax _EAX)))
    (scope-define scope '%ecx (new <register> 'ecx _ECX))
    (scope-define scope '%edx (new <register> 'edx _EDX))
    (scope-define scope '%ebx (new <register> 'ebx _EBX))
    (scope-define scope '%esp (new <register> 'esp _ESP))
    (scope-define scope '%ebp (new <register> 'ebp _EBP))
    (scope-define scope '%esi (new <register> 'esi _ESI))
    (scope-define scope '%edi (new <register> 'edi _EDI))
    asm))

(define-method assembler-compare <undefined> (arg)	())
(define-method assembler-compare <long> (arg)		(= self arg))
(define-method assembler-compare <temporary> (arg)	(and (= self.name (<temporary>-name arg)) (= self.offset (<temporary>-offset arg))))
(define-method assembler-compare <label> (arg)		(and (= self.address (<label>-address arg))))

(define-function assembler-declare (asm name value)	(scope-define (<assembler>-scope asm) name value) value)
(define-function assembler-declare-label (asm name)	(assembler-declare asm name (assembler-new-label asm name)))

(define-function assembler-define (asm name value)
  (let ((old (cdr (scope-lookup (<assembler>-scope asm) name))))
    (or old					(error "could not find binding for "name))
    (or (= (type-of value) (type-of old))	(error "type mismatch in binding for "name))
    (or (assembler-compare old value)
	(let ()
	  (scope-define (<assembler>-scope asm) name value)
	  (set (<assembler>-phased asm) 1)))
    ;;(println name" = "value)
    ))

(define-function assembler-define-label (asm name)
  (assembler-define asm name (assembler-new-label asm name)))

(define-function assembler-new-relocation (asm label)
  (new <relocation> (<assembler>-section asm) (assembler-offset asm) label 1 0))

(define-function assembler-org-relocation (asm)
  (<section>-org-relocation (<assembler>-section asm)))

(define-function assembler-org (asm addr)
  (section-set-origin (<assembler>-section asm) addr)
  (set (<section>-org-relocation (<assembler>-section asm))
       (assembler-new-relocation asm (assembler-new-label asm '$$))))

(define-function assembler-reset (asm)
  (alist-do segment (<assembler>-segments asm)
    (alist-do section (<segment>-sections segment)
      (section-reset section)))
  (assembler-set-section asm '__TEXT '__text)
  (set (<assembler>-phased    	asm) ())
  (set (<assembler>-locals    	asm) 0)
  (set (<assembler>-arguments 	asm) 0)
  (set (<assembler>-relocations asm) ()))

(define-function assembler-lookup (asm name)
  (scope-lookup (<assembler>-scope asm) name))

(define-function assembler-resolve-references (asm)
  (println "symbols:")
  (let ((extern (assembler-get-section asm '__EXTERN '__extern)))
    (list-do label (<assembler>-labels asm)
      (and (= extern (<label>-section label))
	   (let ((address (<subr>-_imp (subr (<label>-name label)))))
	     (set (<label>-address label) address)
	     ;;(println label)
	     ))
      (println "  "label)
      )))

(define-function assembler-do-relocations (asm)
  (println "relocations:")
  (list-do relocation (<assembler>-relocations asm)
    (let* ((section 	 (<relocation>-section 	    relocation))
	   (offset  	 (<relocation>-offset  	    relocation))
	   (label   	 (<relocation>-label   	    relocation))
	   (displacement (<relocation>-displacement relocation))
	   (address   	 (+ (<label>-address label) displacement))
	   (buffer       (<section>-data            section)))
      (or (<relocation>-absolute relocation)
	  (decr address (+ (<section>-origin section) offset)))
      (println "  "section" + "(format "%08X" offset)" = "(format "%08X" address))
      (buffer-set-long-at buffer offset address)
      ;;(print (format "%08X " offset)" ")  (for (i offset (+ offset 4)) (print (format "%02X" (buffer-at buffer i))))  (println)
      )))

(define-function assembler-call (asm offset)
  (println "assembler: calling "offset)
  (assembler-resolve-references asm)
  (assembler-do-relocations asm)
  (println (buffer-call (<section>-data (assembler-get-section asm '__TEXT '__text)) offset)))

(define-function assembler-save (asm path)
  (println "assembler: saving "path)
  (assembler-do-relocations asm)
  (buffer-save (<section>-data (<assembler>-section asm)) path))

(define-method assembler-eval <long>		(asm)	self)
(define-method assembler-eval <string>		(asm)	self)
;; (define-method assembler-eval <pair>		(asm)	(eval (cons (car self) (map-with assembler-eval (cdr self) asm))))
(define-method assembler-eval <temporary>	(asm)	self)

;; (define-method assembler-eval <symbol>		(asm)	(cond
;; 							  ((= self '$)	(assembler-pc asm))
;; 							  ((= self '$$)	(assembler-origin asm))
;; 							  (else		(or (cdr (assembler-lookup asm self)) (assembler-define asm self 0)))))

(define-method assembler-eval <symbol>		(asm)	(cond
							  ((= self '$)	(assembler-new-relocation asm (assembler-new-label asm '$)))
							  ((= self '$$)	(assembler-org-relocation asm))
							  (else		(let ((value (cdr (assembler-lookup asm self))))
									  (or value (set value (assembler-declare asm self (assembler-new-extern asm self))))
									  (if (label? value)
									      (assembler-new-relocation asm value)
									    value)))))

(define-generic assembler-eval-add args		(error "illegal types in expression: "(cons '+ (map type-name-of (cdr args)))))
(define-generic assembler-eval-sub args		(error "illegal types in expression: "(cons '- (map type-name-of (cdr args)))))

(define-multimethod assembler-eval-add ((<assembler> asm) (<relocation> l) (<long> r))		(relocation-add l r))
(define-multimethod assembler-eval-sub ((<assembler> asm) (<relocation> l) (<long> r))		(relocation-add l (- r)))

(define-multimethod assembler-eval-sub ((<assembler> asm) (<relocation> l) (<relocation> r))
  (or (= (relocation-label-section l) (relocation-label-section r))
      (error "labels are in different sections: (- "(relocation-label-name l)" "(relocation-label-name r)")"))
  (- (relocation-label-address l) (relocation-label-address r)))

(define-method assembler-eval <pair>		(asm)	(let ((op   (car self))
							      (args (map-with assembler-eval (cdr self) asm)))
							  (cond
							    ((= op '-)	(apply assembler-eval-sub (cons asm args)))
							    ((= op '+)	(apply assembler-eval-add (cons asm args)))
							    ((= op '@)	(new <deref> (car args)))
							    (else	(error "illegal expression: "self)))))

;; (define-function assembler-eval (asm expr)
;;   (cond
;;     ((long? expr)	expr)
;;     ((string? expr)	expr)
;;     ((symbol? expr)	(or (cdr (assembler-lookup asm expr))
;; 			    (assembler-define asm expr 0)))
;;     ((pair? expr)	(eval (cons (car expr) (with-map assembler-eval asm (cdr expr)))))
;;     (else		(error "illegal expression: "expr))))

(define-function .text	(asm)			(assembler-set-section asm '__TEXT '__text))
(define-function .data	(asm)			(assembler-set-section asm '__DATA '__data))
(define-function .org	(asm addr)		(assembler-org asm addr))
(define-function .equ	(asm name expr)		(assembler-define asm name expr))
(define-function .ascii (asm . strings)		(list-do string strings (string-do char string (_B asm char))))
(define-function .asciz (asm . strings)		(list-do string strings (string-do char string (_B asm char)) (_B asm 0)))
(define-function .byte	(asm . bytes)		(list-do byte bytes (if (string? byte) (.ascii asm byte) (_B asm byte))))
(define-function .long	(asm . longs)		(list-do long longs (_L asm long)))
(define-function .label (asm label)		(assembler-define-label asm label))

(define-multimethod addl  ((<assembler> asm) (<long> src) (<register>  dst))	(ADDLir  asm src (<register>-encoding dst)))
(define-multimethod int	  ((<assembler> asm) (<long> src))			(INTi	 asm src))
(define-multimethod movl  ((<assembler> asm) (<long> src) (<register>  dst))	(MOVLir  asm src (<register>-encoding dst)))
(define-multimethod movl  ((<assembler> asm) (<long> src) (<temporary> dst))	(MOVLim  asm src (<temporary>-offset dst) (<temporary>-register dst) 0 0))
(define-multimethod movl  ((<assembler> asm) (<register> src) (<temporary> dst))	(MOVLrm  asm (<register>-encoding src) (<temporary>-offset dst) (<temporary>-register dst) 0 0))
(define-multimethod pushl ((<assembler> asm) (<long> src))			(PUSHLi  asm src))
(define-multimethod pushl ((<assembler> asm) (<relocation> src))		(PUSHLil asm src))
(define-multimethod pushl ((<assembler> asm) (<deref> src))			(PUSHLm  asm (<deref>-value src) 0 0 0))
(define-multimethod pushl ((<assembler> asm) (<temporary> src))			(PUSHLm  asm (<temporary>-offset src) (<temporary>-register src) 0 0))
(define-multimethod popl  ((<assembler> asm) (<temporary> src))			(POPLm	 asm (<temporary>-offset src) (<temporary>-register src) 0 0))
(define-multimethod subl  ((<assembler> asm) (<long> src) (<register>  dst))	(SUBLir  asm src (<register>-encoding dst)))
(define-multimethod call  ((<assembler> asm) (<long> src))			(CALLm	 asm src 0 0 0))
(define-multimethod call  ((<assembler> asm) (<relocation> src))		(CALLm	 asm src 0 0 0))
(define-multimethod ret	  ((<assembler> asm))					(RET	 asm))

(define-multimethod movl  ((<assembler> asm) (<relocation> src) (<register> dst))	(MOVLir asm src (<register>-encoding dst)))

(define-multimethod xmovl  ((<assembler> asm) (<long> src) (<register>  dst))		(MOVLir  asm src (<register>-encoding dst)))
(define-multimethod xmovl  ((<assembler> asm) (<long> src) (<temporary> dst))		(MOVLim  asm src (<temporary>-offset dst) (<temporary>-register dst) 0 0))
(define-multimethod xmovl  ((<assembler> asm) (<temporary> src) (<temporary> dst))	(movl asm src %eax) (movl asm %eax dst))
(define-multimethod xmovl  ((<assembler> asm) (<relocation> src) (<temporary> dst))	(movl asm src %eax) (movl asm %eax dst))

(define-function .proc (asm name . params)	(let ((index 4))
						  (list-do param params
						    (assembler-declare asm param (new <temporary> param (incr index 4) _EBP))))
						(set (<assembler>-locals    asm) 0)
						(set (<assembler>-arguments asm) 0))

(define-function .local (asm . names)		(list-do name names
						  (assembler-define asm name (new <temporary> name (decr <assembler>-locals asm) _EBP))))

(define-function .enter (asm)			(set (<assembler>-arguments asm) 16) ;; XXXX BOGUS XXXX
						(let* ((locals-size (- (<assembler>-arguments asm) (<assembler>-locals asm)))
						       (frame-size  (- (& -32 (+ 31 (+ 8 locals-size))) 8)))
						;;  (println "LOCALS SIZE "locals-size
						;;	   "("(<assembler>-arguments asm)"-"(<assembler>-locals asm)")"
						;;	   " FRAME SIZE "frame-size)
						  (PUSHLr	asm _EBP)
						  (MOVLrr	asm _ESP _EBP)
						  (if (> locals-size 0)
						      (SUBLir	asm  frame-size _ESP))))

(define-function .args (asm offset args)	(list-do arg args
						  (xmovl asm arg (new <temporary> offset offset _ESP))
						  (incr offset 4))
						(set (<assembler>-arguments asm) (max offset (<assembler>-arguments asm))))

(define-function .call (asm proc . args)	(.args	asm 0 args)
						(call	asm proc))

;; (define-function .sys (asm index . args)	(.args	asm 4 args)			;; this version always generates a stack frame
;; 						(MOVLir	asm index _EAX)
;; 						(INTi	asm 0x80))

(define-function .sys (asm index . args)	(reverse-with-map pushl asm args)	;; this version can run without a frame in a leaf proc
						(SUBLir	asm 4 _ESP)
 						(MOVLir	asm index _EAX)
						(INTi	asm 0x80)
						(ADDLir	asm (* 4 (+ 1 (list-length args))) _ESP))

(define-function .leave (asm)			(LEAVE	asm)
						(RET	asm))

(define-method insn-assemble <symbol> (asm)	(assembler-define-label asm self))

(define-method insn-assemble <pair> (asm)
  (let ((op (car self)))
    (cond
      ((= op '.equ)	(apply .equ	    	 (cons asm (cons (cadr self) (map-with assembler-eval (cddr self) asm)))))
      ((= op '.label)	(      .label		       asm (cadr self)))
      ((= op '.local)	(apply .local		 (cons asm (cdr self))))
      ((= op '.proc)	(apply .proc	    	 (cons asm (cdr self))))
      (else		(apply (eval (car self)) (cons asm (map-with assembler-eval (cdr self) asm)))))))

(define-function assemble (program)
  (let ((asm  (assembler-new))
	(pass 0))
    ;; init labels
    (assembler-reset asm)
    (list-do insn program
      (cond
	((symbol? insn)	(assembler-declare-label asm insn))
	((pair? insn)	(let ((op (car insn)))
			  (cond
			    ((= op '.text)	(.text asm))
			    ((= op '.data)	(.data asm))
			    ((= op '.equ)	(assembler-declare asm (cadr insn) 0)))))))
    (set (<assembler>-phased asm) 1)
    (while (<assembler>-phased asm)
      (assembler-reset asm)
      (list-do insn program
	(let ((pc (<buffer>-size (<section>-data (<assembler>-section asm)))))
;;	  (println insn)
	  (insn-assemble insn asm)
;;	  (print (format "%08X " (+ pc (buffer-address (<section>-data (<assembler>-section asm))))))
;;	  (print (format "%08X " pc))
;;	  (for (i pc (<buffer>-size (<section>-data (<assembler>-section asm))))
;;	    (print (format "%02X" (buffer-at (<section>-data (<assembler>-section asm)) i))))
;;	  (println "\t"insn)
	  )
	)
      (alist-do seg (<assembler>-segments asm)
	(alist-do sec (<segment>-sections seg)
	  (println (format "%-8d" (buffer-size (<section>-data sec))) sec)))
      (or (< (incr pass) 10)
	  (error "assembler did not converge after "pass" passes")))
    asm))

(define-function assemble-to-file (path program)	(assembler-save (assemble program) path))
(define-function assemble-and-run (program)		(assembler-call (assemble program) 0))

(assemble-and-run '(
	(.text)
	(pushl	42)
	(.data)
var	(.long	fmt)
fmt	(.asciz	"integer %d!\n\0")
	(.text)
	(pushl	(@ var))
	(call	printf)
	(addl	8 %esp)
	(.sys	4 1 msg msglen)			; write(1, msg, msglen)
	(.sys	1 0)				; exit(0)
	(.data)
msg	(.ascii	"Hello, world\n")
	(.equ	msglen (- $ msg))
	))

(exit 0)

(assemble-to-file "a.out" '(
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
	(.byte	"__TEXT" 0 0 0 0 0 0 0 0 0 0)	; segname
	(.long	0x1000)				; vmaddr
	(.long	0x1000)				; vmsize
	(.long	0)				; fileoff
	(.long	filesize)			; filesize
	(.long	7)				; maxprot
	(.long	5)				; initprot
	(.long	1)				; nsects
	(.long	0)				; flags
	(.byte	"__text" 0 0 0 0 0 0 0 0 0 0)	; sectname
	(.byte	"__TEXT" 0 0 0 0 0 0 0 0 0 0)	; segname
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
start	(subl	16 %esp)
	(.call	sub msg msglen)
	(.sys	1 0)				; exit(0)
sub	(.proc sub buffer size)
	(.enter)
	(.sys	4 1 buffer size)		; write(1, buffer, size)
	(.leave)
msg	(.ascii	"Hello, world\n\0")
	(.equ	msglen (- $ msg))
	(.equ	filesize (- $ $$))
end	))

(assemble-and-run '(
	(.sys	4 1 msg msglen)			; write(1, msg, msglen)
	(.sys	1 0)				; exit(0)
msg	(.ascii	"Now run ./a.out for a friendly greeting\n\0")
	(.equ	msglen (- $ msg))
	))

(error "NOTREACHED")
