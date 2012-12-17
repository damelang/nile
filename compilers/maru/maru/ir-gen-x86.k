(require "ir2.k")
(require "port.l")	(define-function long->string (x) (format "%d" x))

(define *info-level* 99)

(define *optimise-literals*	())
(define *optimise-globals*	())
(define *align-functions*	16)
(define *compact-prologues*	())
(define *compact-epilogues*	())

(define-structure <ir-gen-x86> (frame current-section callsize port))

(define-function ir-gen-new ()	(make <ir-gen-x86> (port (string-port))))

(define-function x86-mangle (s)
  (let* ((in  (symbol->string s))
	 (len (string-length in))
	 (out (array)))
    (for (i 0 len)
      (let ((c (string-at in i)))
	(if (or (and (<= 0x61 c) (<= c 0x7a))
		(and (<= 0x40 c) (<= c 0x5a))
		(and (<= 0x30 c) (<= c 0x39)))
	    (array-append out c)
	  (if (= ?_ c)
	      (array-append-all out "__")
	    (array-append-all out (format "_%02x" c))))))
    (array->string out)))

(define-function ir-gen-x86-section (self name)
  (unless (= name (<ir-gen-x86>-current-section self))
    (emitln self "	."name)
    (set (<ir-gen-x86>-current-section self) name)))

(define-function ir-gen-x86-variable-name (var)
  (concat-string "v_" (x86-mangle (symbol->string (<ir-variable>-name var)))))

(define-function ir-gen-x86-function-name (func)
  (if (<ir-function>-export func)
      (concat-string __USER_LABEL_PREFIX__ (symbol->string (<ir-function>-export func)))
    (concat-string "f_" (x86-mangle (symbol->string (car (<ir-function>-parameters func)))))))

;;;

(define-structure <ir-register> (name))
(define-structure <ir-label> (number))

(define-function ir-gen-output (gen))

(define-function info (gen level . args)	(and (< level *info-level*) (apply println args)))

(define-method do-emit <long> (gen)		(print self))
(define-method do-emit <symbol> (gen)		(print self))
(define-method do-emit <string> (gen)		(print self))

(define-method do-emit <ir-register> (gen)	(print self.name))
(define-method do-emit <ir-lit> (gen)		(print "$" (car self.parameters)))
(define-method do-emit <ir-location> (gen)	(print self.offset"("(if self.base (<ir-register>-name self.base) "%esp")")"))
(define-method do-emit <ir-label> (gen)		(print "L"(<ir-label>-number self)))
(define-method do-emit <ir-global> (gen)	(print (ir-gen-x86-variable-name self)))
(define-method do-emit <ir-local> (gen)		(do-emit self.location gen))
(define-method do-emit <ir-parameter> (gen)	(do-emit self.location gen))

;; (define-function ir-gen-output (gen)	 (print (port-contents (<ir-gen-x86>-port gen))))

;; (define-function info (gen level . args)	(and (< level *info-level*) (apply print args)))

;; (define-method do-emit <long> (gen)		(print self))
;; (define-method do-emit <symbol> (gen)		(print self))
;; (define-method do-emit <string> (gen)		(print self))

;; (define-method do-emit <ir-register> (gen)	(print self.name))
;; (define-method do-emit <ir-lit> (gen)		(print "$" (car self.parameters)))
;; (define-method do-emit <ir-location> (gen)	(print self.offset"("(if self.base (<ir-register>-name self.base) "%esp")")"))
;; (define-method do-emit <ir-label> (gen)		(print "L"(<ir-label>-number self)))
;; (define-method do-emit <ir-global> (gen)	(print (ir-gen-x86-variable-name self)))
;; (define-method do-emit <ir-local> (gen)		(do-emit self.location gen))
;; (define-method do-emit <ir-parameter> (gen)	(do-emit self.location gen))

(define-function emit (gen . args)	(list-do arg args (do-emit arg gen)))
(define-function emitln (gen . args)	(list-do arg args (do-emit arg gen)) (print "\n"))

(define %eax (new <ir-register> "%eax"))
(define %ecx (new <ir-register> "%ecx"))
(define %edx (new <ir-register> "%edx"))
(define %ebp (new <ir-register> "%ebp"))
(define %esp (new <ir-register> "%esp"))

(define *ir-gen-x86-last-label* 0)

(define-function ir-gen-x86-temp-label (gen)		(new <ir-label> (incr *ir-gen-x86-last-label*)))

(define-function ir-gen-x86-load (type location gen)
  (cond
    ((= type IR-INT8)		(emitln gen "	movb	"  location", %al"))
    ((= type IR-INT16)		(emitln gen "	movw	"  location", %ax"))
    ((= type IR-INT32)		(emitln gen "	movl	"  location", %eax"))
    ((= type IR-INT64)		(emitln gen "	movl	"  location", %eax")
				(emitln gen "	movl	4+"location", %edx"))
    ((ir-pointer-type? type)	(emitln gen "	movl	"  location", %eax"))
    ((= type IR-FLOAT32)	(emitln gen "	movss	"  location", %xmm0"))
    ((= type IR-FLOAT64)	(emitln gen "	movsd	"  location", %xmm0"))
    (else			(error "cannot load: "type))))

(define-function ir-gen-x86-store (type location gen)
  (cond
    ((= type IR-INT8)		(emitln gen "	movb	%al, " 	 location))
    ((= type IR-INT16)		(emitln gen "	movw	%ax, " 	 location))
    ((= type IR-INT32)		(emitln gen "	movl	%eax, "	 location))
    ((= type IR-INT64)		(emitln gen "	movl	%eax, "	 location)
				(emitln gen "	movl	%edx, 4+"location))
    ((ir-pointer-type? type)	(emitln gen "	movl	%eax, "	 location))
    ((= type IR-FLOAT32)	(emitln gen "	movss	%xmm0, " location))
    ((= type IR-FLOAT64)	(emitln gen "	movsd	%xmm0, " location))
    (else			(error "cannot store: "type))))

(define-function ir-gen-x86-spill (insn gen)	(or (ir-struct-type? (<ir-insn>-type insn))
						    (and (ir-lit? insn) (= insn (<ir-insn>-location insn)))
						    (ir-gen-x86-store (<ir-insn>-type insn) (<ir-insn>-location insn) gen)))

(define-function ir-gen-x86-reload (insn gen)	(or (ir-struct-type? (<ir-insn>-type insn))
						    (and (ir-lit? insn) (= insn (<ir-insn>-location insn)))
						    (ir-gen-x86-load  (<ir-insn>-type insn) (<ir-insn>-location insn) gen)))

(define-function ir-gen-x86-move-struct-with (type sinit src dinit dst gen)
  (info gen 2 "# move struct <"sinit" "dinit"> "type)
  (emitln gen "	"sinit"	"src", %esi")
  (emitln gen "	"dinit"	"dst", %edi")
  (emitln gen "	movl	$"(<ir-struct-type>-size type)", %ecx")
  (emitln gen "	cld")
  (emitln gen "	rep	movsb"))

(define-function ir-gen-x86-move-struct  (type src dst gen)	(ir-gen-x86-move-struct-with type "leal" src "leal" dst gen))
(define-function ir-gen-x86-load-struct  (type src dst gen)	(ir-gen-x86-move-struct-with type "movl" src "leal" dst gen))
(define-function ir-gen-x86-store-struct (type src dst gen)	(ir-gen-x86-move-struct-with type "leal" src "movl" dst gen))

;;; allocate-generate

;; (define-function ir-gen-x86-prologue (framesize)
;;   (if *compact-prologues*
;;       (emitln gen "	pushl	%ebp")
;;     (emitln gen "	subl	$4, %esp")
;;     (emitln gen "	movl	%ebp, (%esp)"))
;;   (emitln gen "	movl	%esp, %ebp")
;;   (emitln gen "	subl	$"(- framesize 8)", %esp"))

(define-function ir-gen-x86-prologue (gen framesize)
  (if *compact-prologues*
      (emitln gen "	pushl	%ebp")
    (emitln gen "	subl	$4, %esp")
    (emitln gen "	movl	%ebp, (%esp)"))
  (emitln gen "	movl	%esp, %ebp")
  (emitln gen "	subl	$"(- framesize 8)", %esp"))

(define-function ir-gen-x86-epilogue (gen)
  (if *compact-epilogues*
      (emitln gen "	leave")
    (emitln gen "	movl	%ebp, %esp")
    (emitln gen "	popl	%ebp"))
  (emitln gen "	ret"))

(define-function ir-gen-x86-allocate-parameters (offset param-list)
  (if param-list
      (let* ((param 	(cdar param-list))
	     (type  	(<ir-variable>-type param))
	     (size  	(<ir-type>-size type))
	     (alignment (<ir-type>-alignment type)))
	(set offset (ir-gen-x86-allocate-parameters offset (cdr param-list)))
	(set offset (align offset alignment))
	(set (<ir-variable>-location param) (new <ir-location> offset 'args-in %ebp))
	(+ offset size))
    offset))

(define-selector ir-gen-x86-allocate)
(define-selector ir-gen-x86-deallocate)

(define-method ir-gen-x86-allocate <ir-gen-x86> (type)		(ir-frame-allocate self.frame type))

(define-method ir-gen-x86-deallocate <ir-location> (gen)	(ir-location-deallocate self))
(define-method ir-gen-x86-deallocate <ir-insn> (gen)		(and self.location (ir-gen-x86-deallocate self.location gen)))

;

(define-method ir-gen-x86-allocate <ir-local> (gen)		(set self.location (ir-gen-x86-allocate gen self.type)))
(define-method ir-gen-x86-deallocate <ir-local> (gen)		(ir-gen-x86-deallocate self.location gen))

;

(define-method ir-gen-x86-allocate <ir-insn> (gen)
  (reverse-map-with ir-gen-x86-allocate self.operands gen)
  (list-do opd self.operands (ir-gen-x86-deallocate opd gen))
  (set self.location (ir-gen-x86-allocate gen self.type)))

;

(define-method ir-gen-x86-allocate <ir-return> (gen)
  (when self.operands
    (ir-gen-x86-allocate (car self.operands) gen)
    (ir-gen-x86-deallocate (car self.operands) gen))
  ())

(define-method ir-gen-x86 <ir-return> (gen)
  (let* ((operand  (car self.operands))
	 (type     (<ir-insn>-type     operand))
	 (location (<ir-insn>-location operand)))
    (info gen 2 "# return value")
    (ir-gen-x86 operand gen)
    (and (ir-struct-type? type)
	 (ir-gen-x86-store-struct type location (new <ir-location> 8 'struct-return %ebp) gen))
    (info gen 2 "# return")
    (ir-gen-x86-epilogue gen)))

;

(define-method ir-gen-x86-allocate <ir-get-var> (gen)
  (let ((var self.parameters))
    (set self.location
	 (cond
	   ((and (ir-global? self.parameters) *optimise-globals*)	var)
	   ((= self.type (<ir-variable>-type self.parameters))		(<ir-variable>-location var))
	   (else							(ir-gen-x86-allocate gen self.type))))))

(define-method ir-gen-x86 <ir-get-var> (gen)
  (or (<ir-variable>-location self.parameters) (error "var has no location "self.parameters))
  (or self.location (error "get-var has no location "self))
  (info gen 2 "# get var "self)
  (if (ir-struct-type? self.type)
      (ir-gen-x86-move-struct self.type (<ir-variable>-location self.parameters) self.location gen)
    (ir-gen-x86-load (<ir-variable>-type self.parameters) (<ir-variable>-location self.parameters) gen))
  (info gen 2 "# get var done"))

(define-method ir-gen-x86-deallocate <ir-get-var> (gen)
  (let ((var self.parameters))
    (or (= self.location var)
	(= self.location (<ir-variable>-location var))
	(ir-gen-x86-deallocate self.location gen))))

;

(define-method ir-gen-x86-allocate <ir-set-var> (gen)
  (set self.location (ir-gen-x86-allocate gen self.type))
  (ir-gen-x86-allocate (car self.operands) gen))

(define-method ir-gen-x86-deallocate <ir-set-var> (gen)
  (ir-gen-x86-deallocate (car self.operands) gen)
  (ir-gen-x86-deallocate self.location gen))

(define-method ir-gen-x86 <ir-set-var> (gen)
  (or (<ir-variable>-location self.parameters) (error "var has no location "self.parameters))
  (let ((value (car self.operands)))
    (info gen 2 "# set-var "self.parameters" <- "self.type" value")
    (ir-gen-x86 value gen)
    (info gen 2 "# set-var "(<ir-variable>-type self.parameters))
    (if (ir-struct-type? self.type)
	(let ()
	  (ir-gen-x86-move-struct self.type (<ir-insn>-location value) (<ir-variable>-location self.parameters) gen)
	  (ir-gen-x86-move-struct self.type (<ir-insn>-location value) self.location gen))
      (ir-gen-x86-store (<ir-variable>-type self.parameters) (<ir-variable>-location self.parameters) gen)
      (ir-gen-x86-store self.type self.location gen))))

;

(define-method ir-gen-x86-allocate <ir-let> (gen)
  (set self.location (ir-gen-x86-allocate gen self.type))
  (let ((vars self.parameters))
    (list-do bind vars (ir-gen-x86-allocate (cdr bind) gen))
    (list-do expr self.operands
      (ir-gen-x86-allocate expr gen)
      (or (ir-return? expr)
	  (ir-gen-x86-deallocate expr gen)))
    (reverse-map (lambda (bind) (ir-gen-x86-deallocate (cdr bind) gen)) vars))
  self.location)

(define-method ir-gen-x86 <ir-let> (gen)
  (let ((last ()))
    (list-do expr self.operands (ir-gen-x86 (set last expr) gen))))

;

(define-method ir-gen-x86-allocate <ir-while> (gen)
  (ir-gen-x86-allocate   (car   self.operands) gen)  (ir-gen-x86-deallocate (car   self.operands) gen)
  (ir-gen-x86-allocate   (cadr  self.operands) gen)  (ir-gen-x86-deallocate (cadr  self.operands) gen)
  (set self.location (ir-gen-x86-allocate gen self.type)))

(define-method ir-gen-x86 <ir-while> (gen)
  (let ((test (car  self.operands))
	(body (cadr self.operands))
	(rpt (ir-gen-x86-temp-label gen))
 	(tst (ir-gen-x86-temp-label gen)))
			(info gen 2 "# WHILE")
			(emitln gen "	jmp	"tst)
    (emitln gen rpt":")	(ir-gen-x86 body gen)
    (emitln gen tst":")	(ir-gen-x86 test gen)
			(emitln gen "	testl	%eax, %eax")
			(emitln gen "	jne	"rpt)
			(info gen 2 "# DONE")))

;

(define-method ir-gen-x86-allocate <ir-if> (gen)
  (ir-gen-x86-allocate   (car   self.operands) gen)  (ir-gen-x86-deallocate (car   self.operands) gen)
  (ir-gen-x86-allocate   (cadr  self.operands) gen)  (ir-gen-x86-deallocate (cadr  self.operands) gen)
  (ir-gen-x86-allocate   (caddr self.operands) gen)  (ir-gen-x86-deallocate (caddr self.operands) gen)
  (set self.location (ir-gen-x86-allocate gen self.type)))

(define-method ir-gen-x86 <ir-if> (gen)
  (let ((test (car   self.operands))
	(then (cadr  self.operands))
	(else (caddr self.operands))
	(alt  (ir-gen-x86-temp-label gen))
 	(end  (ir-gen-x86-temp-label gen))
	(void (= IR-VOID self.type)))
			(info gen 2 "# IF")
			(ir-gen-x86 test gen)
			(emitln gen "	testl	%eax, %eax")
			(emitln gen "	je	"alt)
			(info gen 2 "# THEN")
			(ir-gen-x86 then gen)
			(emitln gen "	jmp	"end)
			(info gen 2 "# ELSE")
    (emitln gen alt":")	(ir-gen-x86 else gen)
			(info gen 2 "# FI")
    (emitln gen end":")))

;

(define-function ir-gen-x86-allocate-logical (self gen)
  (with-instance-accessors <ir-insn>
    (let ((exps self.operands))
      (while exps
	(set self.location (ir-gen-x86-allocate (car exps) gen))
	(and (cdr exps) (ir-gen-x86-deallocate (car exps) gen))
	(set exps (cdr exps))))
    self.location))

(define-method ir-gen-x86-allocate <ir-logand> (gen)	(ir-gen-x86-allocate-logical self gen))
(define-method ir-gen-x86-allocate <ir-logor>  (gen)	(ir-gen-x86-allocate-logical self gen))

(define-function ir-gen-x86-logical (self cond gen)
  (with-instance-accessors <ir-insn>
    (let ((done (ir-gen-x86-temp-label gen))
	  (body self.operands)
	  (void (= IR-VOID self.type)))
      (while body
	(ir-gen-x86 (car body) gen)
	(when (cdr body)
	  (emitln gen "	testl	%eax, %eax")
	  (emitln gen "	j"cond"	"done))
	(set body (cdr body)))
      (emitln gen done":"))))

(define-method ir-gen-x86 <ir-logand> (gen)	(ir-gen-x86-logical self "e"  gen))
(define-method ir-gen-x86 <ir-logor>  (gen)	(ir-gen-x86-logical self "ne" gen))

;

(define-method ir-gen-x86-allocate <ir-nop> (gen))
(define-method ir-gen-x86 <ir-nop> (gen))

;

(define-method ir-gen-x86-allocate <ir-lit> (gen)
  (cond
    ((and (= self.type IR-INT)
	  *optimise-literals*)	(set self.location self))
    (else			(set self.location (ir-gen-x86-allocate gen self.type)))))

(define-method ir-gen-x86 <ir-lit> (gen)
  (info gen 2 "# LIT "self)
  (or (= self.location self)
      (let ((value    (car self.parameters))
	    (location self.location))
	(cond
	  ((= self.type IR-INT8)	(emitln gen "	movl	$"(& value 0xff)", %eax"))
	  ((= self.type IR-INT16)	(emitln gen "	movl	$"(& value 0xffff)", %eax"))
	  ((= self.type IR-INT32)	(emitln gen "	movl	$"value", %eax"))
	  ((= self.type IR-INT64)	(emitln gen "	movl	$"(&  value 0xffffffff)", %eax")
					(emitln gen "	movl	$"                    0", %edx # I64"))
	  ((= self.type IR-FLOAT32)	(let ((label (ir-gen-x86-temp-label gen))
					      (tmp   0.0))
					  (set-float-at tmp 0 value)
					  (ir-gen-x86-section gen 'data)
					  (emitln gen	 "	.balign	4")
					  (emitln gen label":	.long	"(int32-at tmp 0))
					  (ir-gen-x86-section gen 'text)
					  (emitln gen "	movss	"label", %xmm0")
					  ))
	  ((= self.type IR-FLOAT64)	(let ((label (ir-gen-x86-temp-label gen)))
					  (ir-gen-x86-section gen 'data)
					  (emitln gen	 "	.balign	4")
					  (emitln gen label":	.long	"(int32-at value 0))
					  (emitln gen	 "	.long	"(int32-at value 1))
					  (ir-gen-x86-section gen 'text)
					  (emitln gen "	movsd	"label", %xmm0")))
	  ((= self.type IR-STRING)	(let ((label (ir-gen-x86-temp-label gen))
					      (len   (string-length value)))
					  (ir-gen-x86-section gen 'data)
					  (emit gen label":	.byte	")
					  (for (i 0 len) (emit gen (string-at value i)","))
					  (emitln gen "0")
					  (ir-gen-x86-section gen 'text)
					  (emitln gen "	movl	$"label", %eax")))
	  (else				(error "cannot generate literal type: "self.type))))))

(define-method ir-gen-x86-deallocate <ir-lit> (gen)
  (or (= self self.location)
      (ir-gen-x86-deallocate self.location gen)))

;

(define-method ir-gen-x86 <ir-cast> (gen)
  (let* ((arg (car self.operands))
	 (i   (<ir-insn>-type arg))
	 (o   self.type))
    (ir-gen-x86 arg gen)
    (info gen 2 "# CAST "i" -> "o)
    (and (ir-pointer-type? i) (set i IR-LONG))
    (and (ir-pointer-type? o) (set o IR-LONG))
    (cond
      ((= i o)						)
      ((= i IR-INT8)	(cond	((= o IR-INT16)		(emitln gen "	movsbl	%al, %eax"))
				((= o IR-INT32)		(emitln gen "	movsbl	%al, %eax"))
				((= o IR-INT64)		(emitln gen "	movsbl	%al, %eax")
							(emitln gen "	movl	$0, %edx"))
				((= o IR-FLOAT32)	(emitln gen "	movsbl	%al, %eax")
							(emitln gen "	cvtsi2ss	%eax, %xmm0"))
				((= o IR-FLOAT64)	(emitln gen "	movsbl	%al, %eax")
							(emitln gen "	cvtsi2sd	%eax, %xmm0"))
				(else			(ir-gen-x86-cannot-cast i o))))
      ((= i IR-INT16)	(cond	((= o IR-INT8)		)
				((= o IR-INT32)		(emitln gen "	cwde"))
				((= o IR-INT64)		(emitln gen "	cwde")
							(emitln gen "	cdq"))
				((= o IR-FLOAT32)	(emitln gen "	cwde")
							(emitln gen "	cvtsi2ss	%eax, %xmm0"))
				((= o IR-FLOAT64)	(emitln gen "	cwde")
							(emitln gen "	cvtsi2sd	%eax, %xmm0"))
				(else			(ir-gen-x86-cannot-cast i o))))
      ((= i IR-INT32)	(cond	((= o IR-INT8)		)
				((= o IR-INT16)		)
				((= o IR-INT64)		(emitln gen "	cdq"))
				((= o IR-FLOAT32)	(emitln gen "	cvtsi2ss	%eax, %xmm0"))
				((= o IR-FLOAT64)	(emitln gen "	cvtsi2sd	%eax, %xmm0"))
				(else			(ir-gen-x86-cannot-cast i o))))
      ((= i IR-INT64)	(cond	((= o IR-INT8)		)
				((= o IR-INT16)		)
				((= o IR-INT32)		)
				((= o IR-FLOAT32)	(emitln gen "	pushl	%edx")
							(emitln gen "	pushl	%eax")
							(emitln gen "	fildll	(%esp)")
							(emitln gen "	fstps	(%esp)")
							(emitln gen "	movss	(%esp), %xmm0")
							(emitln gen "	addl	$8, %esp"))
				((= o IR-FLOAT64)	(emitln gen "	call	___cvti64f64"))
				(else			(ir-gen-x86-cannot-cast i o))))
      ((= i IR-FLOAT32)	(cond	((= o IR-INT8)		(emitln gen "	cvtss2si	%xmm0, %eax"))
				((= o IR-INT16)		(emitln gen "	cvtss2si	%xmm0, %eax"))
				((= o IR-INT32)		(emitln gen "	cvtss2si	%xmm0, %eax"))
				((= o IR-INT64)		(emitln gen "	call	___cvtf32i64"))
				((= o IR-FLOAT32)	)
				((= o IR-FLOAT64)	(emitln gen "	cvtss2sd	%xmm0, %xmm0"))
				(else			(ir-gen-x86-cannot-cast i o))))
      ((= i IR-FLOAT64)	(cond	((= o IR-INT8)		(emitln gen "	cvtsd2si	%xmm0, %eax"))
				((= o IR-INT16)		(emitln gen "	cvtsd2si	%xmm0, %eax"))
				((= o IR-INT32)		(emitln gen "	cvtsd2si	%xmm0, %eax"))
				((= o IR-INT64)		(emitln gen "	call	___cvtf64i64"))
				((= o IR-FLOAT32)	(emitln gen "	cvtsd2ss	%xmm0, %xmm0"))
				((= o IR-FLOAT64)	)
				(else			(ir-gen-x86-cannot-cast i o))))
      (else			(ir-gen-x86-cannot-cast i o)))))

;

(define-method ir-gen-x86-allocate <ir-extern> (gen) (error "not implemented"))

(define-method ir-gen-x86 <ir-extern> (gen) (error "not implemented"))

;

(define-method ir-gen-x86-allocate <ir-function> (gen) (error "not implemented"))

(define-method ir-gen-x86 <ir-function> (gen) (error "not implemented"))

;

(define-function ir-location-align (self alignment)
  (with-instance-accessors <ir-location>
    (set self.offset (align self.offset alignment))))

(define-function ir-location-advance (self advance)
  (with-instance-accessors <ir-location>
    (incr self.offset advance)))

(define-method ir-gen-x86-allocate <ir-call> (gen)
  (set self.location (ir-gen-x86-allocate gen self.type))
  (list-do arg self.operands (ir-gen-x86-allocate arg gen))
  (let* ((offset 0)
	 (fun-type  self.signature)
	 (ret-type  (<ir-function-type>-ret-type  fun-type))
	 (arg-types (<ir-function-type>-arg-types fun-type)))
    (when (ir-struct-type? ret-type)
      (incr offset (<ir-type>-size IR-LONG)))
    (list-do op (cdr self.operands)
      (let ((type (car arg-types)))
	(or type (error "this cannot happen"))
	(if (= IR-VARARGS type)
	    (set type (<ir-insn>-type op))
	  (set arg-types (cdr arg-types)))
	(set offset (align offset (<ir-type>-alignment type)))
	(incr offset (<ir-type>-size type))))
    (set (<ir-gen-x86>-callsize gen) (max offset (<ir-gen-x86>-callsize gen))))
  (reverse-map-with ir-gen-x86-deallocate self.operands gen)
  self.location)

(define-method ir-gen-x86 <ir-call> (gen)
  (list-do op self.operands
    (ir-gen-x86       op gen)
    (ir-gen-x86-spill op gen))
  (let* ((fun-type  self.signature)
	 (ret-type  (<ir-function-type>-ret-type  fun-type))
	 (arg-types (<ir-function-type>-arg-types fun-type))
	 (location  (new <ir-location> 0 'args-out %esp)))
    (info gen 2 "# call "ret-type arg-types)
    (when (ir-struct-type? ret-type)
      (info gen 2 "# struct return")
      (emitln gen "	leal	"self.location", %eax")
      (ir-gen-x86-store IR-LONG location gen)
      (ir-location-advance location (<ir-type>-size IR-LONG)))
    (list-do op (cdr self.operands)
      (let ((type (car arg-types)))
	(or type (error "this cannot happen"))
	(if (= IR-VARARGS type)
	    (set type (<ir-insn>-type op))
	  (set arg-types (cdr arg-types)))
	(ir-location-align location (<ir-type>-alignment type))
	(info gen 2 "# ARG "type" "(<ir-insn>-location op))
	(if (ir-struct-type? type)
	    (ir-gen-x86-move-struct type (<ir-insn>-location op) location gen)
	  (ir-gen-x86-reload op gen)
	  (ir-gen-x86-store type location gen))
	(ir-location-advance location (<ir-type>-size type))))
    (ir-gen-x86-reload (car self.operands) gen)
    (emitln gen "	call	*%eax")))

;

(define-function ir-gen-x86-indir-load (gen type ptr loc)
  (cond
    ((= type IR-INT8)		(emitln gen "	movb	("ptr"), %al"))
    ((= type IR-INT16)		(emitln gen "	movw	("ptr"), %ax"))
    ((= type IR-INT32)		(emitln gen "	movl	("ptr"), %eax"))
    ((= type IR-INT64)		(emitln gen "	movl	("ptr"), %eax")
				(emitln gen "	movl	4("ptr"), %edx"))
    ((ir-pointer-type? type)	(emitln gen "	movl	("ptr"), %eax"))
    ((= type IR-FLOAT32)	(emitln gen "	movss	("ptr"), %xmm0"))
    ((= type IR-FLOAT64)	(emitln gen "	movsd	("ptr"), %xmm0"))
    ((ir-struct-type? type)	(ir-gen-x86-load-struct type ptr loc gen))
    (else			(error "cannot load indirect: "type))))

(define-function ir-gen-x86-indir-store (gen type loc ptr)
  (cond
    ((= type IR-INT8)		(emitln gen "	movb	%al, ("ptr")"))
    ((= type IR-INT16)		(emitln gen "	movw	%ax, ("ptr")"))
    ((= type IR-INT32)		(emitln gen "	movl	%eax, ("ptr")"))
    ((= type IR-INT64)		(emitln gen "	movl	%eax, ("ptr")")
				(emitln gen "	movl	%edx, 4("ptr")"))
    ((ir-pointer-type? type)	(emitln gen "	movl	%eax, ("ptr")"))
    ((= type IR-FLOAT32)	(emitln gen "	movss	%xmm0, ("ptr")"))
    ((= type IR-FLOAT64)	(emitln gen "	movsd	%xmm0, ("ptr")"))
    ((ir-struct-type? type)	(ir-gen-x86-store-struct type loc ptr gen))
    (else			(error "cannot store indirect: "type))))

(define-function ir-gen-x86-indir-address (gen type ptr idx reg)
  (ir-gen-x86 ptr gen)
  (if (ir-zero? idx)
      (or (= %eax reg) (emitln gen "	movl	%eax, "reg))
    (let ((size (<ir-type>-size type)))
      (ir-gen-x86-spill ptr gen)
      (ir-gen-x86       idx gen)
      (or (= %eax reg) (emitln gen "	movl	%eax, "reg))
      (cond
	((= size  0) (error "type size is zero"))
	((= size  1) )
	((= size  2) (emitln gen "	shll	$1, "reg))
	((= size  4) (emitln gen "	shll	$2, "reg))
	((= size  8) (emitln gen "	shll	$3, "reg))
	((= size 16) (emitln gen "	shll	$4, "reg))
	((= size 32) (emitln gen "	shll	$5, "reg))
	(else	     (emitln gen "	imull	$"size", "reg)))
      (emitln gen "	addl	"(<ir-insn>-location ptr)", "reg))))

(define-method ir-gen-x86 <ir-indir> (gen)
  (let ((ptr  (car  self.operands))
	(idx  (cadr self.operands))
	(type self.type))
    (info gen 2 "# INDIR")
    (ir-gen-x86-indir-address gen self.type ptr idx %eax)
    (ir-gen-x86-indir-load gen self.type %eax self.location)))

(define-method ir-gen-x86 <ir-set-indir> (gen)
  (let ((ptr  (car   self.operands))
	(idx  (cadr  self.operands))
	(val  (caddr self.operands))
	(type self.type))
    (info gen 2 "# SET-INDIR")
    (ir-gen-x86        val gen)
    (ir-gen-x86-spill  val gen)
    (ir-gen-x86-indir-address gen self.type ptr idx %ecx)
    (ir-gen-x86-reload val gen)
    (ir-gen-x86-indir-store gen self.type self.location %ecx)))

;

(define-function ir-gen-x86-addressof-member (self dst gen)
  (with-instance-accessors <ir-member>
    (let* ((value  (car self.operands))
	   (vtype  (<ir-insn>-type value))
	   (member (car self.parameters))
	   (offset (<ir-struct-member>-offset member)))
      (if (and (ir-get-var? value) (ir-struct-type? vtype))
	  (ir-gen-x86-addressof value dst gen)
	(info gen 2 "# adddress of "value)
	(ir-gen-x86 value gen)
	(or (= %eax dst) (emitln gen "	movl	%eax, "dst)))
      (info gen 2 "# offset "offset)
      (or (= 0 offset)
	  (emitln gen "	leal	"(<ir-struct-member>-offset member)"("dst"), "dst)))))

(define-selector ir-gen-x86-addressof)

(define-method ir-gen-x86-addressof <ir-get-var> (dst gen)
  (info gen 2 "# adddress of "self.parameters)
  (emitln gen "	leal	"self.parameters", "dst))

(define-method ir-gen-x86-addressof <ir-member> (dst gen)	(ir-gen-x86-addressof-member self dst gen))
(define-method ir-gen-x86-addressof <ir-set-member> (dst gen)	(ir-gen-x86-addressof-member self dst gen))

(define-method ir-gen-x86-allocate <ir-addressof> (gen)
  (ir-gen-x86-allocate (car self.operands) gen)
  (ir-gen-x86-deallocate (car self.operands) gen)
  (set self.location (ir-gen-x86-allocate gen self.type)))

(define-method ir-gen-x86 <ir-addressof> (gen)
  (ir-gen-x86-addressof (car self.operands) %eax gen))

;

(define-method ir-gen-x86-allocate <ir-member> (gen)
  (let* ((value (car self.operands))
	 (vtype (<ir-insn>-type value)))
    (or (ir-struct-type? vtype)
	(ir-gen-x86-allocate value gen))
    (set self.location (ir-gen-x86-allocate gen self.type))))

(define-method ir-gen-x86 <ir-member> (gen)
  (let* ((memb     (car self.parameters))
	 (mtype    (<ir-struct-member>-type memb)))
    (info gen 2 "# get member "memb)
    (ir-gen-x86-addressof self %eax gen)
    (ir-gen-x86-indir-load gen mtype %eax self.location)))

;

(define-method ir-gen-x86-allocate <ir-set-member> (gen)
  (let* ((lval  (car  self.operands))
	 (ltype (<ir-insn>-type lval))
	 (rval  (cadr self.operands)))
    (ir-gen-x86-allocate     rval gen)
    (unless (ir-struct-type? ltype)
      (ir-gen-x86-allocate   lval gen)
      (ir-gen-x86-deallocate lval gen))
    (ir-gen-x86-deallocate   rval gen)
    (set self.location (ir-gen-x86-allocate gen self.type))))

(define-method ir-gen-x86 <ir-set-member> (gen)
  (let* ((rval     (cadr self.operands))
	 (memb     (car self.parameters))
	 (mtype    (<ir-struct-member>-type memb)))
    (ir-gen-x86        rval gen)
    (ir-gen-x86-spill  rval gen)
    (info gen 2 "# set member "memb)
    (ir-gen-x86-addressof self %ecx gen)
    (ir-gen-x86-reload rval gen)
    (ir-gen-x86-indir-store gen mtype self.location %ecx)))

;

(define-function ir-gen-x86-unary (self op gen)
  (with-instance-accessors <ir-insn>
    (let ((type self.type)
	  (lhs  (car self.operands)))
      (ir-gen-x86 lhs gen)
      (info gen 2 "# "op" "type)
      (cond
	((= self.type IR-INT8)		(emitln gen "	"op"b	%al"))
	((= self.type IR-INT16)		(emitln gen "	"op"w	%ax"))
	((= self.type IR-INT32)		(emitln gen "	"op"l	%eax"))
	(else				(error "cannot generate unary "op" for type: "type))))))

(define-method ir-gen-x86 <ir-neg> (gen)
  (cond
    ((= self.type IR-INT64)	(emitln gen "	negl	%eax")
				(emitln gen "	adcl	$0, %edx")
				(emitln gen "	negl	%edx"))
    ((= self.type IR-FLOAT32)	(let ((label ir-gen-x86-temp-label gen))
				  (ir-gen-x86-section 'data)
				  (emitln gen label":	.long	-2147483648,0,0,0")
				  (ir-gen-x86-section 'text)
				  (emitln gen "	xorps	"label", %xmm0")))
    ((= self.type IR-FLOAT64)	(let ((label ir-gen-x86-temp-label gen))
				  (ir-gen-x86-section 'data)
				  (emitln gen label":	.long	0,-2147483648,0,0")
				  (ir-gen-x86-section 'text)
				  (emitln gen "	xorpd	"label", %xmm0")))
    (else			(ir-gen-x86-unary self "neg" gen))))

(define-method ir-gen-x86 <ir-com> (gen)
  (cond
    ((= self.type IR-INT64)	(emitln gen "	notl	%eax")
				(emitln gen "	notl	%edx"))
    (else			(ir-gen-x86-unary self "not" gen))))

(define-method ir-gen-x86 <ir-not> (gen)
  (let ((type self.type)
	(lhs  (car  self.operands)))
    (ir-gen-x86 lhs gen)
    (info gen 2 "# not "type)
    (cond
      ((= self.type IR-INT8)	(emitln gen "	testb	%al, %al"))
      ((= self.type IR-INT16)	(emitln gen "	testw	%ax, %ax"))
      ((= self.type IR-INT32)	(emitln gen "	testl	%eax, %eax"))
      (else			(error "cannot generate logical not on type: "type)))
    (emitln gen "	sete	%al")
    (emitln gen "	movzbl	%al, %eax")))

;

(define-function ir-gen-x86-binary (self op hi fp gen)
  (with-instance-accessors <ir-insn>
    (let* ((lhs  (car  self.operands))  (ltype (<ir-insn>-type lhs))
	   (rhs  (cadr self.operands))  (rtype (<ir-insn>-type rhs)))
      (ir-gen-x86       rhs gen)
      (ir-gen-x86-spill rhs gen)
      (ir-gen-x86       lhs gen)
      (info gen 2 "# "ltype" "op" "rtype)
      (and (ir-pointer-type? ltype) (set ltype IR-LONG))	;; UNSCALED POINTER ARITHMETIC
      (cond
	((= ltype IR-INT8)		(emitln gen "	"op"b	"(<ir-insn>-location rhs)", %al"))
	((= ltype IR-INT16)		(emitln gen "	"op"w	"(<ir-insn>-location rhs)", %ax"))
	((= ltype IR-INT32)		(emitln gen "	"op"l	"(<ir-insn>-location rhs)", %eax"))
	((= ltype IR-INT64)		(emitln gen "	"op"l	"(<ir-insn>-location rhs)", %eax")
					(emitln gen "	"hi"l	"(<ir-insn>-location rhs)", %edx"))
	((= ltype IR-FLOAT32)		(emitln gen "	"fp"ss	"(<ir-insn>-location rhs)", %xmm0"))
	((= ltype IR-FLOAT64)		(emitln gen "	"fp"sd	"(<ir-insn>-location rhs)", %xmm0"))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; C-like scaling of pointer arithmetic...
;;	((ir-pointer-type? ltype)	(let ((ptype (<ir-pointer-type>-referent ltype)))
;;					  (info gen 2 "# PTR ref "ptype" "(<ir-type>-size ptype))
;;					  (cond
;;					    ((= IR-LONG        rtype)	(emitln gen "	movl	"(<ir-insn>-location rhs)", %ecx")
;;									(emitln gen "	imull	$"(<ir-type>-size ptype)", %ecx")
;;									(emitln gen "	"op"l	%ecx, %eax"))
;;					    ((ir-pointer-type? rtype)	(emitln gen "	"op"l	"(<ir-insn>-location rhs)", %eax")
;;									(emitln gen "	movl	$"(<ir-type>-size ptype)", %ecx")
;;									(emitln gen "	cdq")
;;									(emitln gen "	idivl	%ecx"))
;;					    (else			(error "cannot generate binary "op" on "ltype" and "rtype)))))
	(else				(error "cannot generate binary "fp" on type: "ltype))))))

(define-method ir-gen-x86 <ir-add> (gen) (ir-gen-x86-binary self "add" "adc" "add" gen))
(define-method ir-gen-x86 <ir-sub> (gen) (ir-gen-x86-binary self "sub" "sbb" "sub" gen))

(define-method ir-gen-x86 <ir-mul> (gen)
  (with-instance-accessors <ir-insn>
    (let ((type self.type)
	  (lhs  (car  self.operands))
	  (rhs  (cadr self.operands)))
      (ir-gen-x86       rhs gen)
      (ir-gen-x86-spill rhs gen)
      (ir-gen-x86       lhs gen)
      (info gen 2 "# mul "type" "(<ir-insn>-location lhs)" "(<ir-insn>-location rhs))
      (cond
	((= self.type IR-INT8)		(emitln gen "	imulb	"(<ir-insn>-location rhs)))
	((= self.type IR-INT16)		(emitln gen "	imulw	"(<ir-insn>-location rhs)))
	((= self.type IR-INT32)		(emitln gen "	imull	"(<ir-insn>-location rhs)))
	((= self.type IR-INT64)		(emitln gen "	leal	"(<ir-insn>-location rhs)", %ecx")	(emitln gen "	call	___muli64"))
	((= self.type IR-FLOAT32)	(emitln gen "	mulss	"(<ir-insn>-location rhs)", %xmm0"))
	((= self.type IR-FLOAT64)	(emitln gen "	mulsd	"(<ir-insn>-location rhs)", %xmm0"))
	(else				(error "cannot generate binary mul on type: "self.type))))))

(define-method ir-gen-x86 <ir-div> (gen)
  (let ((type self.type)
	(lhs  (car  self.operands))
	(rhs  (cadr self.operands)))
    (ir-gen-x86       rhs gen)
    (ir-gen-x86-spill rhs gen)
    (ir-gen-x86       lhs gen)
    (info gen 2 "# div "type)
    (cond
      ((= self.type IR-INT8)	(emitln gen "	cbw")	(emitln gen "	idivb	"(<ir-insn>-location rhs)))
      ((= self.type IR-INT16)	(emitln gen "	cwd")	(emitln gen "	idivw	"(<ir-insn>-location rhs)))
      ((= self.type IR-INT32)	(emitln gen "	cdq")	(emitln gen "	idivl	"(<ir-insn>-location rhs)))
      ((= self.type IR-INT64)	(emitln gen "	leal	"(<ir-insn>-location rhs)", %ecx")
				(emitln gen "	call	___divi64"))
      ((= self.type IR-FLOAT32)	(emitln gen "	divss	"(<ir-insn>-location rhs)", %xmm0"))
      ((= self.type IR-FLOAT64)	(emitln gen "	divsd	"(<ir-insn>-location rhs)", %xmm0"))
      (else			(error "cannot generate div on type: "type)))))

(define-method ir-gen-x86 <ir-mod> (gen)
  (let ((type self.type)
	(lhs  (car  self.operands))
	(rhs  (cadr self.operands)))
    (ir-gen-x86       rhs gen)
    (ir-gen-x86-spill rhs gen)
    (ir-gen-x86       lhs gen)
    (info gen 2 "# mod "type)
    (cond
      ((= self.type IR-INT8)	(emitln gen "	cbw")	(emitln gen "	idivb	"(<ir-insn>-location rhs))	(emitln gen " movb %ah, %al"))
      ((= self.type IR-INT16)	(emitln gen "	cwd")	(emitln gen "	idivw	"(<ir-insn>-location rhs))	(emitln gen " movw %dx, %ax"))
      ((= self.type IR-INT32)	(emitln gen "	cdq")	(emitln gen "	idivl	"(<ir-insn>-location rhs))	(emitln gen " movl %edx, %eax"))
      ((= self.type IR-INT64)	(emitln gen "	leal	"(<ir-insn>-location rhs)", %ecx")
				(emitln gen "	call	___modi64"))
      (else			(error "cannot generate mod on type: "type)))))

(define-function ir-gen-x86-shift (self op lo gen)
  (with-instance-accessors <ir-insn>
    (let ((type self.type)
	  (lhs  (car  self.operands))
	  (rhs  (cadr self.operands)))
      (ir-gen-x86       rhs gen)
      (ir-gen-x86-spill rhs gen)
      (ir-gen-x86       lhs gen)
      (info gen 2 "# "op" "type)
      (cond
	((= self.type IR-INT8)	(emitln gen "	movl	"(<ir-insn>-location rhs)", %ecx")	(emitln gen "	"op"b	%cl, %al"))
	((= self.type IR-INT16)	(emitln gen "	movl	"(<ir-insn>-location rhs)", %ecx")	(emitln gen "	"op"w	%cl, %ax"))
	((= self.type IR-INT32)	(emitln gen "	movl	"(<ir-insn>-location rhs)", %ecx")	(emitln gen "	"op"l	%cl, %eax"))
	((= self.type IR-INT64)	(let ((L (ir-gen-x86-temp-label gen)))
				  (emitln gen "	movl	"(<ir-insn>-location rhs)", %ecx")
				  (emitln gen "	"lo"l	%cl, %edx, %eax")
				  (emitln gen "	"op"l	%cl, %edx")
				  (emitln gen "	testb	$32, %cl")
				  (emitln gen "	je	"L)
				  (emitln gen "	cdq")
				  (emitln gen L":")))
	(else			(error "cannot generate shift on type: "type))))))

(define-method ir-gen-x86 <ir-shl> (gen) (ir-gen-x86-shift self "sal" "shld" gen))
(define-method ir-gen-x86 <ir-shr> (gen) (ir-gen-x86-shift self "sar" "shrd" gen))

(define-method ir-gen-x86 <ir-bitand> (gen)	(ir-gen-x86-binary self "and" "and" "and" gen))
(define-method ir-gen-x86 <ir-bitor>  (gen)	(ir-gen-x86-binary self "or"  "or"  "or"  gen))
(define-method ir-gen-x86 <ir-bitxor> (gen)	(ir-gen-x86-binary self "xor" "xor" "xor" gen))

(define-function ir-gen-x86-inequality (self op gen)
  (with-instance-accessors <ir-insn>
    (let* ((lhs (car  self.operands) gen)  (type (<ir-insn>-type lhs))
	   (rhs (cadr self.operands) gen))
      (ir-gen-x86       rhs gen)
      (ir-gen-x86-spill rhs gen)
      (ir-gen-x86       lhs gen)
      (and (ir-pointer-type? type) (set type IR-LONG))
      (cond
	((= type IR-INT8)	(emitln gen "	cmpb	"(<ir-insn>-location rhs)", %al")
				(emitln gen "	set"op"	%al")
				(emitln gen "	movzbl	%al, %eax"))
	((= type IR-INT16)	(emitln gen "	cmpw	"(<ir-insn>-location rhs)", %ax")
				(emitln gen "	set"op"	%al")
				(emitln gen "	movzbl	%al, %eax"))
	((= type IR-INT32)	(emitln gen "	cmpl	"(<ir-insn>-location rhs)", %eax")
				(emitln gen "	set"op"	%al")
				(emitln gen "	movzbl	%al, %eax"))
	((= type IR-INT64)	(emitln gen "	leal	"(<ir-insn>-location rhs)", %ecx")
				(emitln gen "	call	___cmpi64"op))
	((= type IR-FLOAT32)	(emitln gen "	ucomiss	"(<ir-insn>-location rhs)", %xmm0")
				(emitln gen "	set"op"	%al")
				(emitln gen "	movzbl	%al, %eax"))
	((= type IR-FLOAT32)	(emitln gen "	ucomisd	"(<ir-insn>-location rhs)", %xmm0")
				(emitln gen "	set"op"	%al")
				(emitln gen "	movzbl	%al, %eax"))
	(else			(error "cannot generate inequality on type: "type))))))

(define-method ir-gen-x86 <ir-eq> (gen) (ir-gen-x86-inequality self "e"  gen))
(define-method ir-gen-x86 <ir-ne> (gen) (ir-gen-x86-inequality self "ne" gen))
(define-method ir-gen-x86 <ir-lt> (gen)	(ir-gen-x86-inequality self "l"  gen))
(define-method ir-gen-x86 <ir-le> (gen) (ir-gen-x86-inequality self "le" gen))
(define-method ir-gen-x86 <ir-ge> (gen) (ir-gen-x86-inequality self "ge" gen))
(define-method ir-gen-x86 <ir-gt> (gen) (ir-gen-x86-inequality self "g"  gen))

;

(define-method ir-gen-declare-struct <ir-gen-x86> (struct)	())

(define-method ir-gen-global-declaration <ir-gen-x86> (var)	(set (<ir-variable>-location var) var))

(define-method ir-gen-local-declaration  <ir-gen-x86> (var)	())

(define-method ir-gen-function-implementation <ir-gen-x86> (value)
  (let* ((name      (ir-gen-x86-function-name value))
	 (type      (<ir-pointer-type>-referent (<ir-function>-type value)))
	 (args      (cadr (<ir-function>-parameters value)))
	 (scope     (<ir-function>-scope value))
	 (body      (<ir-function>-operands value))
	 (calls     (<ir-function>-calls value))
	 (offset    (if (ir-struct-type? (<ir-function-type>-ret-type type)) 12 8))
	 (argsize   (ir-gen-x86-allocate-parameters offset (<ir-scope>-bindings scope)))	; args start at %ebp+8
	 (framesize 0))
    (set self.callsize 0)
    (set self.frame (ir-frame-new))
    (list-do insn body (ir-gen-x86-allocate insn self))
    (set self.callsize (align self.callsize 16))
    (set framesize (align (+ 8 (ir-frame-finalise self.frame self.callsize)) 16))
    (ir-gen-x86-section self 'text)
    (and *align-functions* (emitln self "	.balign	"*align-functions*))
    (info self 0 "# FUNCTION "name" "self.callsize" "framesize" "type)
    (emitln self "	.globl	"name)
    (emitln self name":")
    (ir-gen-x86-prologue self framesize)
    (let ((last))
      (list-do insn body (ir-gen-x86 (set last insn) self))
      (unless (and last (ir-returns? last))
	(ir-gen-x86-epilogue self)))))

(define-method ir-gen-initialisation <ir-gen-x86> (definition)
  (ir-gen-x86-section self 'data)
  (let* ((setter (car (<ir-define>-operands definition)))
	 (var    (<ir-set-var>-parameters setter))
	 (name   (ir-gen-x86-variable-name var))
	 (type   (<ir-global>-type var))
	 (init   (car (<ir-set-var>-operands setter)))
	 (kind   (type-of init)))
    (cond
      ((= kind <ir-extern>)	(emitln self name":	.long	"__USER_LABEL_PREFIX__(car (<ir-extern>-parameters init))))
      ((= kind <ir-function>)	(emitln self name":	.long	"(ir-gen-x86-function-name init)))
      (else			(error "cannot initialise: "name" with: "value)))))

(define-method ir-gen-header <ir-gen-x86> ()	(info self 0 "# HEADER"))
(define-method ir-gen-preamble <ir-gen-x86> ()	(info self 0 "# PRE-INITIALISATION"))
(define-method ir-gen-postamble <ir-gen-x86> ()	(info self 0 "# POST-INITIALISATION"))
