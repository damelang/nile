Object subclass: #IndentingWriteStream
	instanceVariableNames: 'indentationLevelStack writeStream pos lineIsEmpty'
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:27'!
condTab

	lineIsEmpty ifFalse: [self error: 'conditional tabs may only be used while the line is empty'].
	pos := pos + self tabSize.! !

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:27'!
contents

	^ writeStream contents! !

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:27'!
cr

	writeStream cr.
	pos := indentationLevelStack last.
	lineIsEmpty := true.! !

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:27'!
indentIfNecessary

	lineIsEmpty ifTrue: [
		pos timesRepeat: [writeStream space].
		lineIsEmpty := false.
	].! !

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:27'!
initialize: aString

	writeStream := WriteStream on: aString.
	indentationLevelStack := OrderedCollection with: 0.
	pos := 0.
	lineIsEmpty := true.! !

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:27'!
nextPutAll: aString

	self indentIfNecessary.
	writeStream nextPutAll: aString.
	pos := pos + aString size.! !

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:27'!
nextPut: aCharacter

	self indentIfNecessary.
	writeStream nextPut: aCharacter.
	pos := pos + 1.! !

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:29'!
popIndentationLevel

	indentationLevelStack size <= 1 ifTrue: [self error: 'unmatched popIndentationLevel!!'].
	indentationLevelStack removeLast.
	lineIsEmpty ifTrue: [pos := indentationLevelStack last].! !

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:27'!
pushIndentationLevel

	indentationLevelStack addLast: pos.! !

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:28'!
space

	self indentIfNecessary.
	writeStream space.
	pos := pos + 1.! !

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:28'!
tab

	self indentIfNecessary.
	writeStream tab.
	pos := pos + self tabSize.! !

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:28'!
tabSize

	^ 4! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

IndentingWriteStream class
	instanceVariableNames: ''!

!IndentingWriteStream class methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 11:19'!
on: aString

	^ self new initialize: aString! !


OMeta2 subclass: #NileCTranslator
	instanceVariableNames: 'cOut hOut types globals typedMacros prefix currentKernelVarTypes currentKernelAssignableVars currentForAllAssignments currentKernelType numTmps prologueVarNames prologueVarTypes'
	classVariableNames: 'BuiltInKernelNames'
	poolDictionaries: ''
	category: 'Nile'!

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 11:16'!
akType =

	{nameTypePairs:ps} trans:kt -> [NileAbstractKernelType argumentNames: (ps at: #names) argumentTypes: (ps at: #types) underlyingKernelType: kt]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 05:27'!
assign :lhs trans:rhs =

	[self intern: lhs]:iLhs
	[currentForAllAssignments ifNil: [self error: 'assignments are only allowed inside a for-all']]
	[(currentForAllAssignments includes: iLhs) ifTrue: [self error: 'more than one assignment into ', lhs, '''']]
	[currentForAllAssignments add: iLhs]

	[(currentKernelAssignableVars includes: iLhs) ifFalse: [self error: 'cannot assign into variable ', lhs]]

	[currentKernelVarTypes at: iLhs ifAbsent: [self error: 'assignment into undeclared var ', lhs]]:lhsType
	[self coerce: rhs to: lhsType]:coercedRhs
	[self emitAssignmentInto: iLhs, '_' from: coercedRhs withType: lhsType]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 18:30'!
binOp trans:x :op trans:y =

	// op is a typed macro
	?[typedMacros includesKey: op]
	[typedMacros at: op]:macroType
	[self coerce: x to: macroType top1]:cx
	[self coerce: y to: macroType top2]:cy
	trans(macroType macro value: {#var. cx} value: {#var. cy}):ans
	-> [self coerce: ans to: macroType tans]

|

	// op is not a typed macro
	[currentKernelVarTypes at: x]:tx
	[currentKernelVarTypes at: y]:ty
	[tx max: ty]:tans
	[self coerce: x to: tans]:cx
	[self coerce: y to: tans]:cy
	[self newTmpName]:ans
	[self declareVariable: ans withType: tans]
	[self emitPairwiseOp: (self nileToTargetLangOperator: op) on: cx and: cy type: tans into: ans]
	-> [ans]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 00:10'!
coerce: rhsTmp to: lhsType

	^ self coerce: rhsTmp to: lhsType into: nil! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 09:22'!
coerce: rhsTmp to: lhsType into: desiredName

	| rhsType coercedRhsTmp |
	rhsType := currentKernelVarTypes at: rhsTmp.
	rhsType isKernelType ifTrue: [
		lhsType isKernelType
			ifTrue: [
				^ desiredName
					ifNil: [rhsTmp]
					ifNotNil: [
						self emitVarDeclFor: desiredName initializedWith: rhsTmp withType: lhsType.
					]
			]
			ifFalse: [
				self error: 'cannot coerce a kernel to anything else'
			]
	].
	rhsType isScalarType ifTrue: [
		lhsType isScalarType ifTrue: [
			" no coercion required from scalar to scalar "
			^ desiredName
				ifNil: [rhsTmp]
				ifNotNil: [
					self emitVarDeclFor: desiredName initializedWith: rhsTmp withType: lhsType.
				]
		].
		lhsType underlyingScalarType ifNil: [
			self error: 'cannot coerce scalar value to non-homogeneous vector'.
		].
		coercedRhsTmp := desiredName ifNil: [self newTmpName].
		self declareVariable: coercedRhsTmp withType: lhsType.
		self emitScalarPromotionOf: rhsTmp to: lhsType as: coercedRhsTmp.
		^ coercedRhsTmp
	].
	lhsType isScalarType ifTrue: [
		self error: 'cannot coerce vector value to scalar'
	].
	lhsType == rhsType ifTrue: [
		^ desiredName
				ifNil: [rhsTmp]
				ifNotNil: [
					self emitVarDeclFor: desiredName initializedWith: rhsTmp withType: lhsType.
				]
	].
	lhsType elementTypes size ~= rhsType elementTypes size ifTrue: [
		self error: 'vector value cannot be coerced to vector of a different size'.
	].
	coercedRhsTmp := desiredName ifNil: [self newTmpName].
	rhsType elementNames withIndexDo: [:en :ii |
		| nn tnn |
		nn := rhsTmp, '_', en.
		tnn := rhsType elementTypes at: ii.
		(currentKernelVarTypes includesKey: nn) ifFalse: [self declareVariable: nn withType: tnn].
		self coerce: nn to: (lhsType elementTypes at: ii) into: coercedRhsTmp, '_', (lhsType elementNames at: ii).
	].
	self declareVariable: coercedRhsTmp withType: lhsType.
	^ coercedRhsTmp! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 17:19'!
compound = trans*! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/14/2009 17:20'!
condExpr trans:c trans:x trans:y =

	[currentKernelVarTypes at: x]:tx
	[currentKernelVarTypes at: y]:ty
	[tx max: ty]:tans
	[self coerce: x to: tans]:cx
	[self coerce: y to: tans]:cy
	[self coerce: c to: tans]:cc
	[self newTmpName]:ans
	[self declareVariable: ans withType: tans]
	[self emitCondExpr: cc with: cx and: cy type: tans into: ans]
	-> [ans]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/15/2009 09:30'!
decl :n trans:v =

	[currentKernelVarTypes at: v]:t
		[self intern: n]:in
		[self declareVariable: in withType: t]
		[self declareVariable: in, '_' withType: t]
		[currentKernelAssignableVars add: in]
		[self emitVarDeclFor: in initializedWith: v withType: t]
		-> [in]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 12:43'!
declareGlobal: name withType: type

	(globals includesKey: name) ifTrue: [
		self error: 'duplicate global declaration: ', name.
	].
	globals at: name put: type.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 11:07'!
declareType: name toBe: type

	(types includesKey: name) ifTrue: [
		self error: 'duplicate type declaration: ', name.
	].
	types at: name put: type.
	type isKernelType ifTrue: [self emitKernelType: type named: name].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 05:34'!
declareVariable: name withType: type

	| iName |
	iName := self intern: name.
	(currentKernelVarTypes includesKey: iName) ifTrue: [self error: 'cannot re-declare variable: ', name].
	currentKernelVarTypes at: iName put: type.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:51'!
emitAbstractKernelConstructorFor: n withType: t

	| isJustAType formatString prototypePrinter |
	isJustAType := (globals includesKey: n) not.
	prototypePrinter := [:stream |
		stream
			nextPutAll: ('nile_Kernel_t *{1}{2}(' format: {prefix. n}); pushIndentationLevel;
			nextPutAll: 'nile_t *nl'.
		isJustAType ifTrue: [
			stream
				nextPutAll: ', '; cr;
				nextPutAll: 'nile_Kernel_t *k_'.
		].
		(self kernelArgumentVars: t includeTypes: true) do: [:v |
			stream
				nextPutAll: ', '; cr;
				nextPutAll: v.
		].
		stream nextPutAll: ')'; popIndentationLevel.
	].
	prototypePrinter value: hOut.
	hOut nextPut: $;; cr; cr.
	prototypePrinter value: cOut.
	cOut nextPutAll: ' {'; cr; condTab; pushIndentationLevel.
	formatString := '{1}{2}_t *k = ',
		(isJustAType ifTrue: ['({1}{2}_t *) k_;'] ifFalse: ['NILE_KERNEL_NEW(nl, {1}{2});']).
	cOut nextPutAll: (formatString format: {prefix. n}); cr.
	t isAbstract
		ifTrue: [
			"cOut nextPutAll: ('k = ({1}{2}_t *) nile_Kernel_clone(nl, k_);' format: {prefix. n}); cr."
			(self kernelArgumentVars: t includeTypes: false) do: [:v |
				cOut nextPutAll: ('k->{1} = {1};' format: {v}); cr.
			].
		].
	cOut
		nextPutAll: 'return (nile_Kernel_t *) k;'; cr;
		popIndentationLevel; nextPutAll: '}'; cr; cr.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:51'!
emitAbstractKernelStructFor: n withType: t

	| out |
	out := (globals includesKey: n) ifTrue: [cOut] ifFalse: [hOut].
	out nextPutAll: 'typedef struct {'; cr; condTab; pushIndentationLevel.
	self emitKernelTypeGuts: t to: out.
	prologueVarNames ifNotNil: [
		prologueVarNames with: prologueVarTypes do: [:pvn :pvt |
			pvt suffixNames do: [:s | out nextPutAll: ('{1}{2}{3};' format: {self varDeclKeyword. pvn. s}); cr].
		].
	].
	out popIndentationLevel; nextPutAll: ('\} {1}{2}_t;' format: {prefix. n}); cr; cr.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 03:19'!
emitAssignmentInto: lhs from: rhs withType: t

	t suffixNames do: [:suff |
		cOut nextPutAll: ('{1}{2} = {3}{2};' format: {lhs. suff. rhs}); cr.
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:51'!
emitCloneFunctionFor: n withType: t

	| prototypePrinter |
	prototypePrinter := [:stream |
		(globals includesKey: n) ifTrue: [stream nextPutAll: 'static '].
		stream nextPutAll: ('nile_Kernel_t *{1}{2}_clone(nile_t *nl, nile_Kernel_t *k_)' format: {prefix. n})
	].
	(globals includesKey: n) ifFalse: [
		prototypePrinter value: hOut.
		hOut nextPut: $;; cr; cr.
	].
	prototypePrinter value: cOut.
	cOut
		nextPutAll: ' {'; cr; condTab; pushIndentationLevel;
		nextPutAll: ('{1}{2}_t *k = ({1}{2}_t *) k_;' format: {prefix. n}); cr;
		nextPutAll: ('{1}{2}_t *clone = ({1}{2}_t *) {3}_clone(nl, k_);' format: {prefix. n. self nameOfBaseKernelOf: t}); cr.
	t argumentNames with: t argumentTypes do: [:an :at |
		| iAn |
		iAn := self intern: an.
		at isKernelType
			ifTrue: [
				cOut nextPutAll: ('clone->{1} = k->{1}->clone(nl, k->{1});' format: {iAn}); cr.
			] ifFalse: [
				at suffixNames do: [:s |
					cOut nextPutAll: ('clone->{1}{2} = k->{1}{2};' format: {iAn. s}); cr.
				].
			].
	].
	cOut
		nextPutAll: 'return (nile_Kernel_t *) clone;'; cr;
		popIndentationLevel; nextPutAll: '}'; cr; cr.
! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 19:29'!
emitCondExpr: c with: x and: y type: t into: ans

	t suffixNames do: [:suff |
		cOut nextPutAll: ('{1}{2}{3} = {4}{3} ? {5}{3} : {6}{3};' format: {self varDeclKeyword. ans. suff. c. x. y}); cr.
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:52'!
emitFakeKernelConstructorFor: n withType: t

	| prototypePrinter |
	t isAbstract ifFalse: [^ self].
	prototypePrinter := [:stream |
		stream nextPutAll: ('nile_Kernel_t *{1}{2}(nile_t *nl, {1}{2} *k)' format: {prefix. n})
	].
	(globals includesKey: n) ifTrue: [
		prototypePrinter value: hOut.
		hOut nextPut: $;; cr; cr.
	].
	prototypePrinter value: cOut.
	cOut
		nextPutAll: ' {'; cr; condTab; pushIndentationLevel;
		nextPutAll: 'return (nile_Kernel_t *) k;'; cr;
		popIndentationLevel; nextPut: $}; cr; cr.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:52'!
emitForAllWithPattern: pat body: body andEpilogue: epilogue

	| pvs |
	currentForAllAssignments := Set new.
	cOut nextPutAll: 'while (in->i < in->n) {'; cr; condTab; pushIndentationLevel.
	pvs := self apply: #transPat withArgs: {currentKernelType inputType. pat}.
	pvs do: [:pv |
		cOut nextPutAll: pv; nextPutAll: ' = nile_Buffer_shift(in);';cr
	].
	self apply: #trans withArgs: {body}.
	self updatePrimeVars.
	cOut popIndentationLevel; nextPut: $}; cr; cr.
	cOut nextPutAll: 'if (in->eos) {'; cr; condTab; pushIndentationLevel.
	self apply: #trans withArgs: {epilogue}.
	cOut
		popIndentationLevel; nextPut: $}; cr;
		nextPutAll: 'else {'; cr; condTab; pushIndentationLevel.
	self writeBackKernelFields.
	cOut popIndentationLevel; nextPut: $}; cr.
	cOut
		nextPutAll: '*in_ = in;'; cr;
		nextPutAll: '*out_ = out;'; cr;
		nextPutAll: 'return NILE_INPUT_CONSUMED;'; cr.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 11:46'!
emitForwardingWithPeek: peek andForwardingExpression: fwdExpr

	cOut nextPutAll: 'return NILE_INPUT_FORWARD;'; cr.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 11:51'!
emitInCommand: tmpName withType: tmpType

	cOut nextPutAll: 'in = nile_Buffer_prepare_to_prepend(nl, in, IN_QUANTUM, k_);'; cr.
	tmpType suffixNames do: [:s | cOut nextPutAll: ('nile_Buffer_prepend(in, {1}{2});' format: {tmpName. s}); cr].
	cOut nextPutAll: 'in->i -= IN_QUANTUM;'; cr.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/14/2009 01:16'!
emitKApp: k withType: kt andArgs: as into: tmpName

	| f passKAsArg |
	passKAsArg := false.
	f := (BuiltInKernelNames includes: k)
		ifTrue: ['nile_', k]
		ifFalse: [
			(globals includesKey: k)
				ifTrue: [prefix, k]
				ifFalse: [
					passKAsArg := true.
					prefix, (self nameOfKernelType: kt)
				]
		].
	cOut nextPutAll: ('nile_Kernel_t *{1} = {2}(nl' format: {tmpName. f}).
	passKAsArg ifTrue: [cOut nextPutAll: (', {1}' format: {k})].
	as with: kt argumentTypes do: [:a :t |
		t suffixNames do: [:suff |
			cOut nextPutAll: (', {1}{2}' format: {a. suff}).
		].
	].
	cOut nextPutAll: ');'; cr.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 21:52'!
emitKernelBody {#forwarding :peek :fwdExpr} =

	[self emitForwardingWithPeek: peek andForwardingExpression: fwdExpr],

emitKernelBody {#forAll :pat :body :epilogue} =

	[self emitForAllWithPattern: pat body: body andEpilogue: epilogue]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:52'!
emitKernelConstructorFor: n withType: t

	| prototypePrinter |
	prototypePrinter := [:stream | stream nextPutAll: ('nile_Kernel_t *{1}{2}(nile_t *nl)' format: {prefix. n})].
	prototypePrinter value: hOut.
	hOut nextPut: $;; cr; cr.
	prototypePrinter value: cOut.
	cOut
		nextPutAll: ' {'; cr; condTab; pushIndentationLevel;
		nextPutAll: ('{1}{2}_t *k = NILE_KERNEL_NEW(nl, {1}{2});' format: {prefix. n}); cr;
		nextPutAll: 'return (nile_Kernel_t *) k;'; cr;
		popIndentationLevel; nextPut: $}; cr; cr.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 11:49'!
emitKernelDeclarationFooter

	cOut
		nextPutAll: '#undef IN_QUANTUM'; cr;
		nextPutAll: '#undef OUT_QUANTUM'; cr;
		popIndentationLevel;  nextPut: $}; cr; cr.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:53'!
emitKernelDeclarationHeader: name

	| prototypePrinter |
	prototypePrinter := [:stream |
		stream
			nextPutAll: ('static int {1}{2}_process(' format: {prefix. name}); pushIndentationLevel;
			nextPutAll: 'nile_t *nl,'; cr;
			nextPutAll: 'nile_Kernel_t *k_,'; cr;
			nextPutAll: 'nile_Buffer_t **in_,'; cr;
			nextPutAll: 'nile_Buffer_t **out_)'; popIndentationLevel.
	].
	prototypePrinter value: hOut.
	hOut nextPut: $;; cr; cr.
	prototypePrinter value: cOut.
	cOut
		nextPutAll: ' {'; cr; condTab; pushIndentationLevel;
		nextPutAll: '#define IN_QUANTUM ', currentKernelType inputType size printString; cr;
		nextPutAll: '#define OUT_QUANTUM ', currentKernelType outputType size printString; cr;
		nextPutAll: 'nile_Buffer_t *in = *in_;'; cr;
		nextPutAll: 'nile_Buffer_t *out = *out_;'; cr;
		nextPutAll: ('{1}{2}_t *k = ({1}{2}_t *) k_;' format: {prefix. name}); cr.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:05'!
emitKernelFieldsAsLocalVars

	currentKernelType argumentNames, prologueVarNames do: [:v |
		| iv vt isFromPrologue |
		iv := self intern: v.
		isFromPrologue := false.
		vt := currentKernelVarTypes at: iv ifAbsent: [
			isFromPrologue := true.
			prologueVarTypes at: (prologueVarNames indexOf: iv).
		].
		vt isKernelType ifTrue: [
			cOut nextPutAll: ('nile_Kernel_t *{1} = k->{1};' format: {iv}); cr.
		] ifFalse: [
			vt suffixNames do: [:s |
				cOut nextPutAll: ('{1}{2}{3} = k->{2}{3};' format: {self varDeclKeyword. iv. s}); cr.
				isFromPrologue ifTrue: [
					cOut nextPutAll: ('{1}{2}_{3} = {2}{3};' format: {self varDeclKeyword. iv. s}); cr.
				].
			].
		].	
	].
	cOut cr.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:53'!
emitKernelInitializerWithPrologue: prologue andBody: body

	cOut
		nextPutAll: 'if (!!k_->initialized) {'; cr; condTab; pushIndentationLevel;
		nextPutAll: 'k_->initialized = 1;'; cr.
	self apply: #trans withArgs: {prologue}.
	body first == #forwarding ifTrue: [
		| fv |
		self apply: #trans withArgs: {body second}.
		fv := self apply: #trans withArgs: {body third}.
		cOut
			nextPutAll: 'nile_Kernel_t *f = ', fv; nextPutAll: ';'; cr;
			nextPutAll: 'f->downstream = k_->downstream;'; cr;
			nextPutAll: 'k_->downstream = f;'; cr.
	].
	cOut popIndentationLevel; nextPut: $}; cr; cr.

! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:15'!
emitKernelTypeGuts: t to: out

	t isAbstract ifFalse: [
		out nextPutAll: 'nile_Kernel_t base;'; cr.
		^ self
	].
	self emitKernelTypeGuts: t underlyingKernelType to: out.
	(self kernelArgumentVars: t includeTypes: true) do: [:v |
		out nextPutAll: ('{1};' format: {v}); cr.
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/14/2009 00:50'!
emitKernelType: t named: n

	self
		emitAbstractKernelStructFor: n withType: t;
		emitCloneFunctionFor: n withType: t.
	t isAbstract
		ifTrue: [self emitAbstractKernelConstructorFor: n withType: t]
		ifFalse: [
			(globals includesKey: n)
				ifTrue: [self emitKernelConstructorFor: n withType: t]
				ifFalse: [self emitFakeKernelConstructorFor: n withType: t].
		].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 22:02'!
emitOutCommand: tmpName withType: tmpType

	cOut nextPutAll: 'out = nile_Buffer_prepare_to_append(nl, out, OUT_QUANTUM, k_);'; cr.
	tmpType suffixNames do: [:s |
		cOut nextPutAll: ('nile_Buffer_append(out, {1}{2});' format: {tmpName. s}); cr.
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 02:41'!
emitPairwiseOp: op on: x and: y type: t into: ans

	t suffixNames do: [:suff |
		cOut nextPutAll: ('{1}{2}{3} = ' format: {self varDeclKeyword. ans. suff}).
		op first isLetter
			ifTrue: [
				cOut nextPutAll: ('{1}({2}{3}, {4}{3})' format: {op. x. suff. y}).
			]
			ifFalse: [
				cOut nextPutAll: ('({1}{2} {3} {4}{2})' format: {x. suff. op. y}).
			].
		cOut nextPutAll: ';'; cr.
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/14/2009 00:46'!
emitPipelineCalled: name withStages: ss

	cOut nextPutAll: ('nile_Kernel_t *{1} = nile_Pipeline(nl' format: {name}).
	ss do: [:s |
		cOut nextPutAll: ', '; nextPutAll: s.
	].
	cOut nextPutAll: ', NULL);'; cr.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 18:46'!
emitReductionOf: x type: tx withOp: op into: tmp

	cOut nextPutAll: ('{1}{2} = {3}{4};' format: {self varDeclKeyword. tmp. x. tx suffixNames first}); cr.
	tx suffixNames allButFirstDo: [:suff |
		cOut nextPutAll: ('{1} = ' format: {tmp}).
		op first isLetter
			ifTrue: [
				cOut nextPutAll: ('{1}({2}, {3}{4})' format: {op. tmp. x. suff}).
			]
			ifFalse: [
				cOut nextPutAll: ('{1} {2} {3} {4}' format: {tmp. op. x. suff}).
			].
		cOut nextPutAll: ';'; cr.
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:44'!
emitScalarPromotionOf: sName to: vType as: vName

	vType suffixNames do: [:suff |
		cOut nextPutAll: ('{1}{2}{3} = {4};' format: {self varDeclKeyword. vName. suff. sName}); cr.
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 18:37'!
emitScalar: x as: tmpName
	
	cOut nextPutAll: ('{1}{2} = {3};' format: {self varDeclKeyword. tmpName. x printString}); cr.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 03:56'!
emitUnaryOp: op on: x type: t into: ans

	t suffixNames do: [:suff |
		cOut nextPutAll: ('{1}{2}{3} = {4}({5}{3});' format: {self varDeclKeyword. ans. suff. op. x}); cr.
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:06'!
emitVarDeclFor: n initializedWith: v withType: t

	| in |
	in := self intern: n.
	t suffixNames do: [:suff |
		(prologueVarNames includes: in) ifFalse: [cOut nextPutAll: self varDeclKeyword].
		cOut nextPutAll: ('{1}{2} = {3}{2};' format: {in. suff. v}); cr.
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 02:16'!
emitVector: tmpName withElements: eNames andType: tmpType

	tmpType elementTypes withIndexDo: [:et :ii |
		et suffixNames do: [:s |
			cOut nextPutAll: ('{1}{2}_{3}{4} = {5}{4};' format: {self varDeclKeyword. tmpName. ii asString. s. eNames at: ii}); cr.
		].
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 10:36'!
ensureValidNodeType :nt =

	?[self respondsTo: nt asSymbol]
|	[self inform: 'unknown node type: ', nt] fail! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 17:23'!
epilogue = trans*! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 02:17'!
fieldAccess trans:wholeName :fieldName =

	[currentKernelVarTypes at: wholeName]:wholeType
	?[wholeType isNamedVectorType]
	?[wholeType elementNames includes: fieldName]
	[wholeType elementTypes at: (wholeType elementNames indexOf: fieldName)]:partType
	[wholeName, '_', fieldName]:partName
	[(currentKernelVarTypes includesKey: partName) ifFalse: [self declareVariable: partName withType: partType]]
	-> [partName]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:50'!
if trans:cond =

	[(currentKernelVarTypes at: cond) isScalarType ifFalse: [self error: 'condition of if-statement must be a scalar']]
	[currentForAllAssignments]:oldAs

	[cOut nextPutAll: 'if (', cond, ') {'; cr; condTab; pushIndentationLevel]
	[oldAs copy]:currentForAllAssignments
	trans
	[currentForAllAssignments]:newAs1

	[cOut
		popIndentationLevel; nextPut: $}; cr;
		nextPutAll: 'else {'; cr; condTab; pushIndentationLevel]
	[oldAs copy]:currentForAllAssignments
	trans
	[currentForAllAssignments]:newAs2
	[cOut popIndentationLevel; nextPut: $}; cr]

	[newAs1 ifNotNil: [newAs1 union: newAs2]]:currentForAllAssignments! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 19:39'!
in = 

	(
		trans:tmpName
		[currentKernelVarTypes at: tmpName]:tmpType
		[self emitInCommand: (self coerce: tmpName to: currentKernelType inputType) withType: currentKernelType inputType]
	)*! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 11:16'!
initialize

	super initialize.
	globals := Dictionary new.
	types := Dictionary new
		at: 'Real' put: NileRealType new;
		yourself.
	typedMacros := Dictionary new.
	cOut := self writeStream on: (String new: 1024).
	hOut := self writeStream on: (String new: 1024).
	numTmps := 0.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 21:31'!
intern: v

	| ans |
	ans := ((types includesKey: v) or: [(v beginsWith: 't_') or: [v beginsWith: 'v_']])
		ifTrue: [v]
		ifFalse: ['v_', v].
	^ ans! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/14/2009 22:52'!
kArg :t =

	pTransHelper(#pipeline. t):p -> [p key] // this is a kind of a hack to catch a {#pipeline...} before trans, so we can propagate the type info
|	trans
|	pTrans(t):a -> [a key]
|	pTransHelper(#offset. t)! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/15/2009 09:48'!
kernel :name trans:currentKernelType =

	[globals copy]:currentKernelVarTypes                    // so we don't need to use 2 dicts for lookup
	[Set new]:currentKernelAssignableVars
	[currentKernelType arguments keysAndValuesDo: [:k :v |
		| ik |
		ik := self intern: k.
		self declareVariable: ik withType: v.
	]]
	[0]:numTmps
	[OrderedCollection new]:prologueVarNames
	[OrderedCollection new]:prologueVarTypes

	{#prologue {#compound
		(	{#decl :n1 :v1}
				[prologueVarNames add: (self intern: n1)]
				[prologueVarTypes add: (self typeOf: v1)]
		|	:someOtherKindOfNode
		)*
	}}:prologue
	anything:body

	[self
		declareGlobal: name withType: currentKernelType;
		declareType: name toBe: currentKernelType]

	[self emitKernelDeclarationHeader: name]
	[self emitKernelFieldsAsLocalVars]
	[self emitKernelInitializerWithPrologue: prologue andBody: body]

	emitKernelBody(body)

	[self emitKernelDeclarationFooter]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 05:51'!
kernelArgumentVars: type includeTypes: includeTypes

	| r |
	r := OrderedCollection new.
	type argumentNames with: type argumentTypes do: [:n :t |
		| in |
		in := self intern: n.
		t isKernelType
			ifTrue: [
				r add: (includeTypes ifTrue: ['nile_Kernel_t *'] ifFalse: ['']), in.
			] ifFalse: [
				t suffixNames do: [:s |
					r add: (includeTypes ifTrue: [self varDeclKeyword] ifFalse: ['']), in, s.
				].
			].
	].
	^ r! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 11:05'!
kType =

	trans:it trans:ot -> [NileKernelType inputType: it outputType: ot]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 05:16'!
makeTmpName: n

	^ 't_', n asString! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 13:42'!
nameOfBaseKernelOf: aKernelType

	| name |
	(aKernelType isAbstract and: [aKernelType underlyingKernelType isAbstract]) ifTrue: [
		name := self nameOfKernelType: aKernelType underlyingKernelType.
	].
	^ name
		ifNil: ['nile_Kernel']
		ifNotNil: [prefix, name]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 11:24'!
nameOfKernelType: kernelType

	| name |
	types keysAndValuesDo: [:key :value |
		value == kernelType ifTrue: [name := key].
	].
	^ name! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 11:15'!
nameTypePairs =

	[OrderedCollection new]:ns
	[OrderedCollection new]:ts
	{trans:t1 :ns1 [ns addAll: ns1] [ns1 size timesRepeat: [ts add: t1]]}* -> [Dictionary new at: #types put: ts; at: #names put: ns; yourself]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 18:37'!
newTmpName

	numTmps := numTmps + 1.
	^ self makeTmpName: numTmps! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/14/2009 00:53'!
nileToTargetLangOperator: op

	" ignore the following line -- is just a hack to get around some silliness in the OMeta2 compiler "
	#().

	op = '='		ifTrue: [^ 'nile_Real_eq'].
	op = '≠'		ifTrue: [^ 'nile_Real_neq'].
	op = '×'		ifTrue: [^ 'nile_Real_mul'].
	op = '+'		ifTrue: [^ 'nile_Real_add'].
	op = '-'		ifTrue: [^ 'nile_Real_sub'].
	op = '<'		ifTrue: [^ 'nile_Real_lt'].
	op = '>'		ifTrue: [^ 'nile_Real_gt'].
	op = '≤'		ifTrue: [^ 'nile_Real_leq'].
	op = '≥'		ifTrue: [^ 'nile_Real_geq'].
	op = '∧'		ifTrue: [^ 'nile_Real_and'].
	op = '∨'		ifTrue: [^ 'nile_Real_or'].
	op = '~'		ifTrue: [^ 'nile_Real_ave'].
	op = '||'	ifTrue: [^ 'nile_Real_abs'].
	op = '⌈⌉'	ifTrue: [^ 'nile_Real_clg'].
	op = '⌊⌋'	ifTrue: [^ 'nile_Real_flr'].
	op = '⋗'		ifTrue: [^ 'nile_Real_max'].
	op = '⋖'		ifTrue: [^ 'nile_Real_min'].
	^ op.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:09'!
nOut trans:n trans:x =

	[currentKernelType outputType size ~~ 1 ifTrue: [self error: 'right now nOut only works when OUT_QUANTUM = 1']]

	[currentKernelVarTypes at: x]:xType
	[self coerce: x to: currentKernelType outputType]:x2
	[cOut nextPutAll: ('out = nile_Buffer_append_repeat(nl, out, {1}, {2}, k_);' format: {x2. n}); cr]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:31'!
noOp =

	[cOut nextPutAll: '; /* no-op */'; cr]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 10:52'!
nType :tn =

	[types at: tn ifAbsent: [self error: 'unkown type: ', tn]]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 11:14'!
nvType =

	nameTypePairs:ps -> [NileNamedVectorType elementTypes: (ps at: #types) elementNames: (ps at: #names)]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 02:06'!
out trans:tmpName =

	[currentKernelVarTypes at: tmpName ifAbsent: [self error: tmpName, ' is undeclared']]:tmpType
	[self emitOutCommand: (self coerce: tmpName to: currentKernelType outputType) withType: currentKernelType outputType]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 20:37'!
output

	| allLower allCaps |
	allLower := prefix asLowercase allButLast.
	allCaps := prefix asUppercase allButLast.
	^ (WriteStream on: (String new: 1024))
			nextPutAll: '/* THE .H FILE */'; cr; cr;
			nextPutAll: '#ifndef ', allCaps, '_H'; cr;
			nextPutAll: '#define ', allCaps, '_H'; cr; cr;
			nextPutAll: '#include "nile.h"'; cr; cr;
			nextPutAll: hOut contents; cr; cr;
			nextPutAll: '#endif'; cr; cr;
			nextPutAll: '---------------------------';  cr; cr; cr;
			nextPutAll: '/* THE .C FILE */'; cr; cr;
			nextPutAll: '#include <stddef.h>'; cr;
			nextPutAll: '#include "', allLower, '.h"'; cr; cr;
			nextPutAll: cOut contents;
			contents! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:13'!
peek =

	transPat(currentKernelType inputType):pvs
		[pvs do: [:pv | cOut nextPutAll: pv; nextPutAll: ' = in->data[in->i++];'; cr]]
		[cOut nextPutAll: 'in->i -= ', pvs size printString, ';'; cr]

	trans! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 17:09'!
pipeline =

	pPipeline(currentKernelType inputType):ans
	-> [ans key]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:45'!
pKApp :ttt 'Interleave' =

	kArg(ttt):k1 [currentKernelVarTypes at: k1]:tk1 trans({#scalar. tk1 outputType size}):k1s
	kArg(ttt):k2 [currentKernelVarTypes at: k2]:tk2 trans({#scalar. tk2 outputType size}):k2s
	[self newTmpName]:ans
	[(NileKernelType
		inputType: tk1 inputType
		outputType: (NileVectorType elementTypes: {tk1 outputType. tk2 outputType}))]:ikt
	[NileAbstractKernelType
		argumentNames: #('a' 'b' 'c' 'd')
		argumentTypes: {NileRealType new. NileRealType new. NileRealType new. NileRealType new}
		underlyingKernelType: ikt]:it
	[self declareVariable: ans withType: ikt]
	[self emitKApp: 'Interleave' withType: it andArgs: {k1. k1s. k2. k2s} into: ans]
	-> [ans -> ikt outputType],

pKApp :ttt 'GroupBy' {#offset :f} =

	[ttt offsetOfField: f]:o
	trans({#scalar. o}):ov
	[currentKernelType inputType size]:q
	trans({#scalar. q}):qv
	[self newTmpName]:ans
	[self declareVariable: ans withType: currentKernelType inputType]
	[NileAbstractKernelType
		argumentNames: #('index' 'quantum')
		argumentTypes: {NileRealType new. NileRealType new}
		underlyingKernelType: (NileKernelType inputType: currentKernelType inputType outputType: currentKernelType inputType)]:it
	[self emitKApp: 'GroupBy' withType: it andArgs: {ov. qv} into: ans]
	-> [ans -> currentKernelType inputType],

pKApp :ttt 'SortBy' {#offset :f} =

	[ttt offsetOfField: f]:o
	trans({#scalar. o}):ov
	[currentKernelType inputType size]:q
	trans({#scalar. q}):qv
	[self newTmpName]:ans
	[self declareVariable: ans withType: currentKernelType inputType]
	[NileAbstractKernelType
		argumentNames: #('index' 'quantum')
		argumentTypes: {NileRealType new. NileRealType new}
		underlyingKernelType: (NileKernelType inputType: currentKernelType inputType outputType: currentKernelType inputType)]:it
	[self emitKApp: 'SortBy' withType: it andArgs: {ov. qv} into: ans]
	-> [ans -> currentKernelType inputType],

pKApp :ttt :k =

	[currentKernelVarTypes at: (self intern: k) ifAbsent: [self error: 'unknown kernel: ', k]]:kt
	?[kt isAbstractKernelType]
	[1]:ii
	(
		?[ii <= kt argumentTypes size]
		[kt argumentTypes at: ii]:at
		[ii + 1]:ii
		kArg(ttt):a
		[self coerce: a to: at]:ca
	)*:as
	?[ii = (kt argumentTypes size + 1)]
	[self newTmpName]:ans
	[self declareVariable: ans withType: kt underlyingKernelType]
	[self emitKApp: (self intern: k) withType: kt andArgs: as into: ans]
	-> [ans -> kt outputType]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 17:14'!
pPipeline :origInputType =

	[origInputType]:inputType

		(
			end -> [{}]
		|
			pTrans(inputType):k1AndNewInputType
			[k1AndNewInputType key]:k1
			[k1AndNewInputType value]:inputType

			pTrans(inputType):k2AndNewInputType
			[k2AndNewInputType key]:k2
			[k2AndNewInputType value]:inputType
			-> [{k1. k2}]
		):stages

		[self newTmpName]:pVar
		[self declareVariable: pVar withType: (NileKernelType inputType: origInputType outputType: inputType)]
		[self emitPipelineCalled: pVar withStages: stages]
		
		-> [pVar -> inputType]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 17:30'!
prologue = trans! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:45'!
pTrans :t =

	pTransHelper(#pipeline. t)
|	pTransHelper(#kApp. t)
|	pTransHelper(#var. t)
! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 18:19'!
pTransHelper :tag :type =

	{exactly(tag) apply(('p', tag capitalized) asSymbol. type):ans} -> [ans]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 08:40'!
pVar :ttt =

	:name  [self intern: name]:iName [currentKernelVarTypes at: iName]:kt -> [iName -> kt outputType]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 18:43'!
reduce :op trans:x =

	[currentKernelVarTypes at: x]:tx
	[self newTmpName]:ans
	[self declareVariable: ans withType: NileRealType new]
	[self emitReductionOf: x type: tx withOp: (self nileToTargetLangOperator: op) into: ans]
	-> [ans]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 06:02'!
scalar :x =

	[self newTmpName]:tmpName
	[self declareVariable: tmpName withType: NileRealType new]
	[self emitScalar: x as: tmpName]
	-> [tmpName]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 03:24'!
start =

	{:p [p, '_']:prefix {trans*}} -> [self output]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 10:34'!
trans &anything:node =

	{:nodeType ensureValidNodeType(nodeType) apply(nodeType):ans} -> [ans]
|	[node inspect] [self error: 'could not translate this node!!']! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 06:41'!
transPat :patType =
	{#var :name}
	[self intern: name]:iName
	(	[(iName endsWith: '_') ifTrue: [
			iName := iName allButLast.
			(currentKernelAssignableVars includes: iName) ifFalse: [self error: 'cannot assign into ', name, ''' b/c ', name, ' is not declared'].
		]]
		?[currentKernelAssignableVars includes: iName]
			[(currentKernelVarTypes at: iName) = patType ifFalse: [self error: 'pattern ', name, ''' has the wrong type']]
			[currentForAllAssignments add: iName]
			-> [iName, '_']
	|	[self declareVariable: iName withType: patType]
			-> ['nile_Real_t ', iName]
	):name
	-> [patType suffixNames collect: [:s | name, s]],

transPat :patType =
	?[patType isVectorType]
	[1]:ii
	[OrderedCollection new]:ans
	{#vector
		(
			?[ii <= patType elementTypes size]
			transPat(patType elementTypes at: ii):varNames
			[ans addAll: varNames]
			[ii + 1]:ii
		)*
	}
	?[ii = (patType elementTypes size + 1)]
	-> [ans],

transPat :patType :badPat =
	[badPat inspect]
	[self error: 'invalid pattern']! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 11:06'!
typeDef :tn trans:t =

	[self declareType: tn toBe: t] -> [t]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 02:29'!
typedMacro :op trans:tx trans:ty trans:tans :m =

	[(typedMacros includesKey: op) ifTrue: [self error: 'cannot redefine typed macro: ', op]]
	[typedMacros at: op put: (NileTypedMacroType top1: tx top2: ty tans: tans macro: m)]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 11:16'!
typeOf: expr

	| oldCOut n |
	oldCOut := cOut.
	cOut := self writeStream on: (String new: 64).
	" compile a copy of expr so that later on we don't get back a variable that doesn't exist from the memo table "
	n := self apply: #trans withArgs: {expr copy}.
	cOut := oldCOut.
	^ currentKernelVarTypes at: n! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 03:54'!
unOp :op trans:x =

	[currentKernelVarTypes at: x]:tans
		[self newTmpName]:ans
		[self declareVariable: ans withType: tans]
		[self emitUnaryOp: (self nileToTargetLangOperator: op) on: x type: tans into: ans]
		-> [ans]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:11'!
updatePrimeVars

	prologueVarNames do: [:v |
		| iv |
		iv := self intern: v.
		(prologueVarTypes at: (prologueVarNames indexOf: v)) suffixNames do: [:s |
			cOut nextPutAll: ('{1}{2} = {1}_{2};' format: {iv. s}); cr.
		].
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 06:04'!
var :name =

	-> [self intern: name]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 11:42'!
varDeclKeyword

	^ 'nile_Real_t '! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 02:14'!
vector =

	[self newTmpName]:tmpName
	trans*:elementNames
	[elementNames collect: [:n | currentKernelVarTypes at: n]]:elementTypes
	[NileVectorType elementTypes: elementTypes]:tmpType
	[self declareVariable: tmpName withType: tmpType]
	[self emitVector: tmpName withElements: elementNames andType: tmpType]
	-> [tmpName]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 10:55'!
vType =

	trans*:ts -> [NileVectorType elementTypes: ts]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:12'!
writeBackKernelFields

	currentKernelType argumentNames, prologueVarNames do: [:v |
		| iv vt |
		iv := self intern: v.
		vt := currentKernelVarTypes at: iv ifAbsent: [prologueVarTypes at: (prologueVarNames indexOf: v)].
		vt isKernelType ifTrue: [
			cOut nextPutAll: ('k->{1} = {1};' format: {iv}); cr.
		] ifFalse: [
			vt suffixNames do: [:s |
				cOut nextPutAll: ('k->{1}{2} = {1}{2};' format: {iv. s}); cr.
			].
		].
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 11:38'!
writeStream

	^ IndentingWriteStream! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

NileCTranslator class
	instanceVariableNames: ''!

!NileCTranslator class methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 18:30'!
circleTimesMacro

	^ {#typedMacro. '⊗'.
			{#nType. 'Matrix'}.
			{#nType. 'Point'}.
			{#nType. 'Point'}.
			[:m :p |
				{#vector.
					{#binOp.
						{#binOp.
							{#binOp.
								{#fieldAccess. m. 'a'}.
								'×'.
								{#fieldAccess. p. 'x'}}.
							'+'.
							{#binOp.
								{#fieldAccess. m. 'c'}.
								'×'.
								{#fieldAccess. p. 'y'}}}.
						'+'.
						{#fieldAccess. m. 'e'}}.
					{#binOp.
						{#binOp.
							{#binOp.
								{#fieldAccess. m. 'b'}.
								'×'.
								{#fieldAccess. p. 'x'}}.
							'+'.
							{#binOp.
								{#fieldAccess. m. 'd'}.
								'×'.
								{#fieldAccess. p. 'y'}}}.
						'+'.
						{#fieldAccess. m. 'f'}}}
			]
		}.
! !

!NileCTranslator class methodsFor: 'as yet unclassified' stamp: 'aw 12/14/2009 01:02'!
initialize

	"
		self initialize
	"
	BuiltInKernelNames := #('Interleave' 'GroupBy' 'SortBy') asSet.! !


Object subclass: #NileType
	instanceVariableNames: ''
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 04:34'!
isAbstractKernelType

	^ false! !

!NileType methodsFor: 'as yet unclassified' stamp: 'aw 10/9/2009 14:31'!
isKernelType

	^ false! !

!NileType methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 13:38'!
printOn: aStream

	self subclassResponsibility.! !

!NileType methodsFor: 'as yet unclassified' stamp: 'aw 10/7/2009 14:00'!
= anotherNileType

	self subclassResponsibility! !


NileType subclass: #NileAbstractKernelType
	instanceVariableNames: 'argumentNames argumentTypes arguments underlyingKernelType'
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileAbstractKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 03:13'!
argumentNames

	^ argumentNames! !

!NileAbstractKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 02:54'!
argumentNames: ans argumentTypes: ats underlyingKernelType: ukt

	argumentNames := ans.
	argumentTypes := ats.
	underlyingKernelType := ukt.
	arguments := underlyingKernelType arguments copy.
	argumentNames with: argumentTypes do: [:an :at |
		arguments at: an put: at.
	].
! !

!NileAbstractKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 03:13'!
arguments

	^ arguments! !

!NileAbstractKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 03:13'!
argumentTypes

	^ argumentTypes! !

!NileAbstractKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 02:54'!
inputType

	^ underlyingKernelType inputType! !

!NileAbstractKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 03:02'!
isAbstract

	^ true! !

!NileAbstractKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 04:34'!
isAbstractKernelType

	^ true! !

!NileAbstractKernelType methodsFor: 'as yet unclassified' stamp: 'aw 10/9/2009 14:56'!
isKernelType

	^ true! !

!NileAbstractKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 02:54'!
outputType

	^ underlyingKernelType outputType! !

!NileAbstractKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 02:54'!
printOn: aStream

	| first |
	first := true.
	aStream nextPut: $(.
	argumentNames with: argumentTypes do: [:an :at |
		first
			ifTrue: [first := false]
			ifFalse: [aStream nextPutAll: ', '].
		aStream
			nextPutAll: an;
			nextPut: $:.
		at printOn: aStream.
	].
	aStream nextPutAll: ') : '.
	underlyingKernelType printOn: aStream.! !

!NileAbstractKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 04:11'!
suffixNames

	^ #('')! !

!NileAbstractKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 03:03'!
underlyingKernelType

	^ underlyingKernelType! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

NileAbstractKernelType class
	instanceVariableNames: ''!

!NileAbstractKernelType class methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 02:42'!
argumentNames: ans argumentTypes: ats underlyingKernelType: ukt

	^ self new argumentNames: ans argumentTypes: ats underlyingKernelType: ukt! !


NileType subclass: #NileKernelType
	instanceVariableNames: 'inputType outputType'
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileKernelType methodsFor: 'as yet unclassified' stamp: 'aw 10/19/2009 02:10'!
argumentNames

	^ #()! !

!NileKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 02:54'!
arguments

	^ Dictionary new! !

!NileKernelType methodsFor: 'as yet unclassified' stamp: 'aw 10/19/2009 02:10'!
argumentTypes

	^ #()! !

!NileKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 02:54'!
inputType

	^ inputType! !

!NileKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 02:54'!
inputType: it outputType: ot

	inputType := it.
	outputType := ot.! !

!NileKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 03:02'!
isAbstract

	^ false! !

!NileKernelType methodsFor: 'as yet unclassified' stamp: 'aw 10/9/2009 14:31'!
isKernelType

	^ true! !

!NileKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 02:54'!
outputType

	^ outputType! !

!NileKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 02:54'!
printOn: aStream

	inputType printOn: aStream.
	aStream nextPutAll: ' >> '.
	outputType printOn: aStream.! !

!NileKernelType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 04:11'!
suffixNames

	^ #('')! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

NileKernelType class
	instanceVariableNames: ''!

!NileKernelType class methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 02:46'!
inputType: it outputType: ot

	^ self new inputType: it outputType: ot! !


NileType subclass: #NileTypedMacroType
	instanceVariableNames: 'top1 top2 tans macro'
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileTypedMacroType methodsFor: 'as yet unclassified' stamp: 'aw 9/21/2009 13:44'!
macro

	^ macro! !

!NileTypedMacroType methodsFor: 'as yet unclassified' stamp: 'aw 9/21/2009 13:44'!
tans

	^ tans! !

!NileTypedMacroType methodsFor: 'as yet unclassified' stamp: 'aw 9/21/2009 13:44'!
top1

	^ top1! !

!NileTypedMacroType methodsFor: 'as yet unclassified' stamp: 'aw 9/21/2009 13:44'!
top1: t1 top2: t2 tans: ta macro: m

	top1 := t1.
	top2 := t2.
	tans := ta.
	macro := m.! !

!NileTypedMacroType methodsFor: 'as yet unclassified' stamp: 'aw 9/21/2009 13:44'!
top2

	^ top2! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

NileTypedMacroType class
	instanceVariableNames: ''!

!NileTypedMacroType class methodsFor: 'as yet unclassified' stamp: 'aw 9/21/2009 13:45'!
top1: t1 top2: t2 tans: ta macro: m

	^ self new top1: t1 top2: t2 tans: ta macro: m! !


NileType subclass: #NileValueType
	instanceVariableNames: ''
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileValueType methodsFor: 'as yet unclassified' stamp: 'aw 10/7/2009 13:59'!
isColorComponentType

	^ true! !

!NileValueType methodsFor: 'as yet unclassified' stamp: 'aw 9/19/2009 15:10'!
isNamedVectorType

	^ false! !

!NileValueType methodsFor: 'as yet unclassified' stamp: 'aw 10/7/2009 13:58'!
isRealType

	^ false! !

!NileValueType methodsFor: 'as yet unclassified' stamp: 'aw 9/19/2009 12:12'!
isScalarType

	^ false! !

!NileValueType methodsFor: 'as yet unclassified' stamp: 'aw 9/18/2009 13:30'!
isVectorType

	^ false! !

!NileValueType methodsFor: 'as yet unclassified' stamp: 'aw 9/19/2009 15:09'!
max: anotherType

	^ self subclassResponsibility! !

!NileValueType methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 13:58'!
size

	^ self subclassResponsibility! !

!NileValueType methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 13:58'!
suffixNames

	^ self subclassResponsibility! !

!NileValueType methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 14:05'!
underlyingScalarType

	^ self subclassResponsibility! !


NileValueType subclass: #NileScalarType
	instanceVariableNames: ''
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileScalarType methodsFor: 'as yet unclassified' stamp: 'aw 9/19/2009 12:12'!
isScalarType

	^ true! !

!NileScalarType methodsFor: 'as yet unclassified' stamp: 'aw 9/19/2009 15:12'!
max: anotherType

	^ anotherType isVectorType
		ifTrue: [anotherType]
		ifFalse: [self]! !

!NileScalarType methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 13:58'!
size

	^ 1! !

!NileScalarType methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 13:58'!
suffixNames

	^ #('')! !

!NileScalarType methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 14:06'!
underlyingScalarType

	^ self! !

!NileScalarType methodsFor: 'as yet unclassified' stamp: 'aw 10/7/2009 14:01'!
= t

	^ t isScalarType and: [t == self]! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

NileScalarType class
	instanceVariableNames: 'Singleton'!

!NileScalarType class methodsFor: 'as yet unclassified' stamp: 'aw 9/14/2009 15:05'!
new

	^ Singleton ifNil: [
		Singleton := self basicNew.
	]! !


NileScalarType subclass: #NileRealType
	instanceVariableNames: ''
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileRealType methodsFor: 'as yet unclassified' stamp: 'aw 10/7/2009 13:58'!
isRealType

	^ true! !

!NileRealType methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 13:37'!
printOn: aStream

	aStream nextPutAll: 'Real'.! !


NileValueType subclass: #NileVectorType
	instanceVariableNames: 'suffixNames elementTypes elementNames'
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileVectorType methodsFor: 'as yet unclassified' stamp: 'aw 12/15/2009 13:40'!
elementNames

	^ elementNames ifNil: [elementNames :=  (1 to: elementTypes size) collect: [:ii | ii printString]]! !

!NileVectorType methodsFor: 'as yet unclassified' stamp: 'aw 9/18/2009 13:32'!
elementTypes

	^ elementTypes! !

!NileVectorType methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 13:36'!
elementTypes: ets

	elementTypes := ets.! !

!NileVectorType methodsFor: 'as yet unclassified' stamp: 'aw 9/18/2009 13:30'!
isVectorType

	^ true! !

!NileVectorType methodsFor: 'as yet unclassified' stamp: 'aw 9/19/2009 15:11'!
max: anotherType

	^ anotherType isNamedVectorType
		ifTrue: [anotherType]
		ifFalse: [self]! !

!NileVectorType methodsFor: 'as yet unclassified' stamp: 'aw 12/15/2009 13:42'!
printOn: aStream

	aStream nextPut: $[.
	elementTypes
		do: [:et | et printOn: aStream]
		separatedBy: [aStream nextPutAll: ', '].
	aStream nextPut: $].! !

!NileVectorType methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 13:57'!
size

	^ self suffixNames size! !

!NileVectorType methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:43'!
suffixNames

	^ suffixNames ifNil: [
		suffixNames := OrderedCollection new.
		elementTypes withIndexDo: [:et :ii |
			et suffixNames do: [:sn | suffixNames add: '_', ii printString, sn].
		].
		suffixNames
	]! !

!NileVectorType methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 14:08'!
underlyingScalarType
	" returns nil if I am not homogeneous "

	| st |
	st := elementTypes first underlyingScalarType.
	elementTypes do: [:et |
		st ~~ et underlyingScalarType ifTrue: [^ nil].
	].
	^ st! !

!NileVectorType methodsFor: 'as yet unclassified' stamp: 'aw 10/7/2009 14:04'!
= t

	t isVectorType ifFalse: [^ false].
	t isNamedVectorType ifTrue: [^ false].
	elementTypes size ~~ t elementTypes size ifTrue: [^ false].
	elementTypes with: t elementTypes do: [:et1 :et2 |
		et1 ~= et2 ifTrue: [^ false].
	].
	^ true! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

NileVectorType class
	instanceVariableNames: ''!

!NileVectorType class methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 13:36'!
elementTypes: ets

	^ self new elementTypes: ets! !


NileVectorType subclass: #NileNamedVectorType
	instanceVariableNames: ''
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileNamedVectorType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 00:47'!
elementNames

	^ elementNames! !

!NileNamedVectorType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 00:47'!
elementNames: ens

	elementNames := ens.
	elementNames size ~= elementTypes size ifTrue: [
		self error: 'invalid named vector type'.
	].! !

!NileNamedVectorType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 00:47'!
isNamedVectorType
	
	^ true! !

!NileNamedVectorType methodsFor: 'as yet unclassified' stamp: 'aw 9/19/2009 15:10'!
max: anotherType

	^ self! !

!NileNamedVectorType methodsFor: 'as yet unclassified' stamp: 'aw 12/14/2009 23:07'!
offsetOfField: f

	| r |
	r := 0.
	elementNames with: elementTypes do: [:n :t |
		n = f ifTrue: [^ r].
		r := r + t suffixNames size.
	].
	self error: f, ' is not a valid field name for type ', self printString! !

!NileNamedVectorType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 00:47'!
printOn: aStream

	| first |
	first := true.
	aStream nextPut: $[.
	elementNames with: elementTypes do: [:en :et |
		first
			ifTrue: [first := false]
			ifFalse: [aStream nextPutAll: ', '].
		aStream
			nextPutAll: en;
			nextPut: $:.
		et printOn: aStream.
	].
	aStream nextPut: $].! !

!NileNamedVectorType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 00:47'!
suffixNames

	suffixNames ifNil: [
		suffixNames := OrderedCollection new.
		elementTypes withIndexDo: [:et :ii |
			et suffixNames do: [:sn |
				suffixNames add: '_', (elementNames at: ii), sn.
			].
		].
	].
	^ suffixNames! !

!NileNamedVectorType methodsFor: 'as yet unclassified' stamp: 'aw 10/7/2009 14:05'!
= t

	t isNamedVectorType ifFalse: [^ false].
	elementTypes size ~~ t elementTypes size ifTrue: [^ false].
	elementTypes with: t elementTypes do: [:et1 :et2 |
		et1 ~= et2 ifTrue: [^ false].
	].
	elementNames with: t elementNames do: [:en1 :en2 |
		en1 ~= en2 ifTrue: [^ false].
	].
	^ true! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

NileNamedVectorType class
	instanceVariableNames: ''!

!NileNamedVectorType class methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 13:40'!
elementTypes: ts elementNames: ns

	^ (self new elementTypes: ts) elementNames: ns! !


OMeta2 subclass: #OffsideRuleParser
	instanceVariableNames: 'level'
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!OffsideRuleParser methodsFor: 'as yet unclassified' stamp: 'aw 12/15/2009 13:36'!
eol = spaces nl! !

!OffsideRuleParser methodsFor: 'as yet unclassified' stamp: 'aw 12/15/2009 13:36'!
indent :dummy = spaces:n ?[n >= level]! !

!OffsideRuleParser methodsFor: 'as yet unclassified' stamp: 'aw 12/8/2009 23:06'!
indented :r =

	[level]:oldLevel &spaces:level ?[level > oldLevel]
		( apply(r):ans [oldLevel]:level -> [ans]
		| [oldLevel]:level ?[false]
		)! !

!OffsideRuleParser methodsFor: 'as yet unclassified' stamp: 'aw 12/2/2009 11:05'!
initialize

	super initialize.
	level := 0.! !

!OffsideRuleParser methodsFor: 'as yet unclassified' stamp: 'aw 12/2/2009 11:09'!
nl =

	exactly(Character cr)! !

!OffsideRuleParser methodsFor: 'as yet unclassified' stamp: 'aw 12/15/2009 13:37'!
space = char:x ?[x ~~ Character cr and: [x asciiValue <= 32]] -> [x]! !

!OffsideRuleParser methodsFor: 'as yet unclassified' stamp: 'aw 12/15/2009 13:37'!
spaces = [0]:n (space [n + 1]:n)* -> [n]! !


OffsideRuleParser subclass: #NileParser
	instanceVariableNames: ''
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/2/2009 14:40'!
akType =

	"(" listOf(#vTypeP. ','):as ")" ":" kType:kt -> [{#akType. as. kt}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/8/2009 11:34'!
arrowKis =

	"⇒" kis! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/9/2009 10:55'!
aType =

	"[" listOf(#vTypeP. ','):ps "]" -> [{#nvType}, ps]
|	"[" listOf(#aType. ','):ts "]" -> [{#vType}, ts]
|	ident:t -> [{#nType. t}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 12:31'!
block =

	indented(#stmts)! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 16:17'!
body =

	prologue:p (computing | forwarding):b -> [{p. b}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 21:47'!
computing =

	indent(nil) "∀" pat:p eol block:b epilogue:e -> [{#forAll. p. b. e}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 15:18'!
epilogue =

	stmts:ss -> [{#epilogue. ss}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/3/2009 12:19'!
expr =

	expr8! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/3/2009 11:28'!
expr1 =

	expr1:e "." ident:f -> [{#fieldAccess. e. f}]
|	expr1:e "[" expr:i "]" -> [{#index. e. i}]
|	primExpr:e ":" ident:t -> [{#typedExpr. e. t}]
|	primExpr! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 02:36'!
expr2 =

	expr2:x "∙" expr1:y -> [{#binOp. x. '∙'. y}]
|	expr2:x "×" expr1:y -> [{#binOp. x. '×'. y}]
|	expr2:x "⊗" expr1:y -> [{#binOp. x. '⊗'. y}]
|	expr1! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/3/2009 11:30'!
expr3 =

	expr3:x "+" expr2:y -> [{#binOp. x. '+'. y}]
|	expr3:x "-" expr2:y -> [{#binOp. x. '-'. y}]
|	expr2! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/8/2009 23:47'!
expr3ud =

	expr3ud:x "⋗"  expr3:y -> [{#binOp. x. '⋗'. y}]
|	expr3ud:x "⋖"  expr3:y -> [{#binOp. x. '⋖'. y}]
|	expr3ud:x "~" expr3:y -> [{#binOp. x. '~'. y}]
|	expr3! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/3/2009 12:17'!
expr4 =

	expr3:x "<" expr3:y -> [{#binOp. x. '<'. y}]
|	expr3:x "≤" expr3:y -> [{#binOp. x. '≤'. y}]
|	expr3:x ">" expr3:y -> [{#binOp. x. '>'. y}]
|	expr3ud! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/3/2009 12:17'!
expr5 =

	expr4:x "=" expr4:y -> [{#binOp. x. '='. y}]
|	expr4:x "≠" expr4:y -> [{#binOp. x. '≠'. y}]
|	expr4! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/3/2009 12:18'!
expr6 =

	expr6:x "∧" expr5:y -> [{#binOp. x. '∧'. y}]
|	expr5! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/3/2009 12:18'!
expr7 =

	expr7:x "∨" expr6:y -> [{#binOp. x. '∨'. y}]
|	expr6! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/3/2009 12:19'!
expr8 =

	expr8:x "?" primExpr:c "?" expr7:y -> [{#condExpr. c. x. y}]
|	expr7! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/8/2009 11:47'!
exprs =

	listOf(#expr. ',')! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 16:25'!
forwarding =

	indent(nil) "&" pat:p eol block:b indented(#arrowKis):arr eol -> [{#forwarding. {#peek. p. b}. arr}]
|	arrowKis:arr -> [{#forwarding. {#noOp}. arr}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/2/2009 12:00'!
ident =

	spaces nsIdent! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 15:14'!
ifStmt =

	"if" expr:c eol
		block:t
		( indent(nil) "else" (ifStmt | eol block)
		| empty -> [{#noOp}]
		):e
		-> [{#if. c. t. e}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/3/2009 11:11'!
kasPart =

	listOf(#ident. ','):ns ":"  ident:t -> [{t. ns}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 13:23'!
kernArgs =

	"(" kasPart:p ("," optEol kasPart)*:ps ")" -> [{p}, ps]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 16:11'!
kernel =

	ident:n (akType | ":" kType):t eol indented(#body):b -> [{#kernel. n. t. b first. b second}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 07:40'!
ki =

	ident:k "(" listOf(#kisOrExpr. ','):as ")" -> [{#kApp. k}, as]
|	ident:k -> [{#var. k}]
|	"(" "→" ")" -> [{#pipeline}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 17:02'!
kis =

	ki:x "→" optEol kis:y -> [{#pipeline. x. y}]
|	ki! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 17:43'!
kisOrExpr =

	kis | expr | ki! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/3/2009 10:59'!
kType =

	aType:t1 ">>" aType:t2 -> [{#kType. t1. t2}]
|	aType:t1 ">>" "|" -> [{#kType. t1. {#nType. 'Real'}}]
|	ident:t -> [{#nType. t}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 21:28'!
nsIdent =

	letter:x letterOrDigit*:xs ($' -> ['_'] | empty -> ['']):p -> [String withAll: {x}, xs, p]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/3/2009 11:07'!
optEol =

	eol | empty! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 01:38'!
pat =

	ident:x -> [{#var. x}] 
|	"[" listOf(#pat. ','):ps "]" -> [{#vector}, ps]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 18:48'!
primExpr =

	ident:x -> [{#var. x}]
|	scalar:s -> [{#scalar. s}]
|	"∧[" expr:x "]" -> [{#reduce. '∧'. x}]
|	"∨[" expr:x "]" -> [{#reduce. '∨'. x}]
|	"[" exprs:xs "]" -> [{#vector}, xs]
|	"(" expr:x ")" -> [x]
|	"|" expr:x "|" -> [{#unOp. '||'. x}]
|	"‖" expr:x "‖" -> [{#unOp. '‖‖'. x}]
|	"⌊" expr:x "⌋" -> [{#unOp. '⌊⌋'. x}]
|	"⌈" expr:x "⌉" -> [{#unOp. '⌈⌉'. x}]
|	"@" nsIdent:x -> [{#offset. x}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 15:18'!
prologue =

	stmts:ss -> [{#prologue. ss}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/2/2009 12:10'!
scalar =

	spaces digit+:is $. digit+:fs -> [(String withAll: is, '.', fs) asNumber]
|	spaces digit+:is -> [(String withAll: is) asNumber]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/8/2009 17:18'!
space =

	^space
|	``/*'' (~``*/'' char)* ``*/''
|	``//'' (~nl char:c)* nl! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/8/2009 23:49'!
start =

	((space | nl)* topLevel:t -> [t])*:ans /*[ans inspect]*/ (space | nl)* end -> [ans]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/15/2009 09:19'!
stmt :dummy =

	indent(nil)	( ">>" expr:e -> [{#out. e}]
					| ">" primExpr:n $> expr:e -> [{#nOut. n. e}]
					)+:outs eol -> [{#compound}, outs]
|	indent(nil) ("<<" expr)*:es eol -> [{#in}, es]
|	indent(nil) ident:x ?[(x endsWith: '_') not] "=" expr:e eol -> [{#decl. x. e}]
|	indent(nil) ident:x ?[x endsWith: '_'] "=" expr:e eol -> [{#assign. x allButLast. e}]
|	indent(nil) ifStmt! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 12:32'!
stmts =

	stmt(nil)*:xs -> [{#compound}, xs]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 22:44'!
testStmt = stmt(nil)! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/3/2009 12:20'!
topLevel =

	kernel | typeDef! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/8/2009 11:29'!
typeDef =

	ident:n ("<:" aType | "::" (akType | kType)):t -> [{#typeDef. n. t}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 10:56'!
vTypeP =

	listOf(#ident. ','):ns ":" aType:t -> [{t. ns}]! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

NileParser class
	instanceVariableNames: ''!

!NileParser class methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 14:24'!
parse: fileName

	| stream |
	stream := FileStream readOnlyFileNamed: '/Users/awarth/prog/dan-new/gezira/', fileName.
	stream wantsLineEndConversion: true.
	^ NileParser matchAll: stream with: #start! !


OffsideRuleParser subclass: #OffsideRuleParserTest
	instanceVariableNames: ''
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!
!OffsideRuleParserTest commentStamp: 'aw 12/2/2009 11:39' prior: 0!
self test1!


!OffsideRuleParserTest methodsFor: 'as yet unclassified' stamp: 'aw 12/2/2009 11:33'!
name =

	"x" | "foo" | "bar" | "baz"! !

!OffsideRuleParserTest methodsFor: 'as yet unclassified' stamp: 'aw 12/2/2009 11:36'!
start =

	stmts:ans (space | nl)* end -> [ans]! !

!OffsideRuleParserTest methodsFor: 'as yet unclassified' stamp: 'aw 12/8/2009 23:20'!
stmt :dummy =

	indent(nil)
		( name:n eol -> [n]
		| ``if'' name:c eol indented(#stmts):t indent(nil) ``else'' eol indented(#stmts):e -> [{#if. c. t. e}]
		| ``if'' name:c eol indented(#stmts):t -> [{#if. c. t}]
		)! !

!OffsideRuleParserTest methodsFor: 'as yet unclassified' stamp: 'aw 12/8/2009 23:04'!
stmts =

	stmt(nil)*! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

OffsideRuleParserTest class
	instanceVariableNames: ''!

!OffsideRuleParserTest class methodsFor: 'as yet unclassified' stamp: 'aw 12/8/2009 23:22'!
test1

	^ self matchAll: 'foo
if x
  foo
  bar
  if x
    baz
    baz
    foo
    if bar
      baz
else
  baz
' with: #start! !

NileCTranslator initialize!
