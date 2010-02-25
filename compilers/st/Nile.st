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

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 2/5/2010 09:58'!
cr

	self nextPut: Character cr.
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

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 2/5/2010 09:43'!
nextPut: aCharacter

	self nextPutAll: aCharacter asString.! !

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:29'!
popIndentationLevel

	indentationLevelStack size <= 1 ifTrue: [self error: 'unmatched popIndentationLevel!!'].
	indentationLevelStack removeLast.
	lineIsEmpty ifTrue: [pos := indentationLevelStack last].! !

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:27'!
pushIndentationLevel

	indentationLevelStack addLast: pos.! !

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 2/5/2010 10:01'!
space

	self nextPut: Character space.! !

!IndentingWriteStream methodsFor: 'as yet unclassified' stamp: 'aw 2/5/2010 10:02'!
tab

	self nextPut: Character tab.
	" nextPut has already incremented the position, but we consider tabs to be more spaces "
	pos := pos + self tabSize - 1.! !

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

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 15:28'!
apply: aRule

	^ self perform: aRule! !

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

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 12:07'!
binOp trans:x :op trans:y =

	// op is a UDO
	?[typedMacros includesKey: op]
	[typedMacros at: op]:macroType
	(
		?[macroType canBeUsedPairwise]
		[currentKernelVarTypes at: x]:tx
		[currentKernelVarTypes at: y]:ty
		?[tx isTupleType or: [ty isTupleType]]
		[tx max: ty]:tans
		[self coerce: x to: tans]:cx
		[self coerce: y to: tans]:cy
		[tans elementNames collect: [:en |
			{#var. self apply: #trans withArgs: {macroType expandWithArgs: {{#fieldAccess. {#var. cx}. en}. {#fieldAccess. {#var. cy}. en}}}}
		]]:es
		trans({#tuple}, es):ans
		-> [self coerce: ans to: tans]
	|
		[self coerce: x to: macroType top1]:cx
		[self coerce: y to: macroType top2]:cy
		trans(macroType expandWithArgs: {{#var. cx}. {#var. cy}}):ans
		-> [self coerce: ans to: macroType tans]
	)

|

	// op is not a UDO
	?[(typedMacros includesKey: op) not]
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

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/9/2010 14:26'!
coerce: rhsTmp to: lhsType into: desiredName

	| rhsType coercedRhsTmp |
	lhsType isAnyType ifTrue: [^ rhsTmp].
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
			self error: 'cannot coerce scalar value to non-homogeneous tuple'.
		].
		coercedRhsTmp := desiredName ifNil: [self newTmpName].
		self declareVariable: coercedRhsTmp withType: lhsType.
		self emitScalarPromotionOf: rhsTmp to: lhsType as: coercedRhsTmp.
		^ coercedRhsTmp
	].
	lhsType isScalarType ifTrue: [
		self error: 'cannot coerce tuple value to scalar'
	].
	lhsType == rhsType ifTrue: [
		^ desiredName
				ifNil: [rhsTmp]
				ifNotNil: [
					self emitVarDeclFor: desiredName initializedWith: rhsTmp withType: lhsType.
				]
	].
	lhsType elementTypes size ~= rhsType elementTypes size ifTrue: [
		self error: 'tuple value cannot be coerced to tuple of a different size'.
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

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 15:46'!
decl :n trans:t trans:v =

	[t isAnyType ifTrue: [t := currentKernelVarTypes at: v]]
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

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 10:42'!
declareVariable: name withType: type

	| iName |
	iName := self intern: name.
	(currentKernelVarTypes includesKey: iName) ifTrue: [
		" TODO: take out the check below, fix this problem properly (see prologue look-ahead stuff in #kernel) "
		(prologueVarNames includes: name) ifFalse: [
			self error: 'cannot re-declare variable: ', name
		]
	].
	currentKernelVarTypes at: iName put: type.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/25/2010 01:05'!
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

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/23/2010 14:51'!
emitForAllWithPattern: pat body: body andEpilogue: epilogue

	| pvs |
	currentForAllAssignments := Set new.
	cOut nextPutAll: 'while (in->i < in->n) {'; cr; condTab; pushIndentationLevel.
	self initializePrimeVars.
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

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/19/2010 14:44'!
emitKernelBody {#forwarding :peek :fwdExpr}   = [self emitForwardingWithPeek: peek andForwardingExpression: fwdExpr],
emitKernelBody {#forAll :pat :body :epilogue} = [self emitForAllWithPattern: pat body: body andEpilogue: epilogue]! !

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

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/23/2010 14:56'!
emitKernelFieldsAsLocalVars

"prologueVarNames ifNotEmpty: [self halt]."
	(currentKernelType underlyingKernelType
		ifNil: [{}] 
		ifNotNil: [currentKernelType underlyingKernelType argumentNames]),
	currentKernelType argumentNames,
	prologueVarNames do: [:v |
		| iv vt isFromPrologue |
		iv := self intern: v.
		isFromPrologue := false.
		vt := currentKernelVarTypes at: iv.
		isFromPrologue := prologueVarNames includes: v.
		vt isKernelType ifTrue: [
			cOut nextPutAll: ('nile_Kernel_t *{1} = k->{1};' format: {iv}); cr.
		] ifFalse: [
			vt suffixNames do: [:s |
				cOut nextPutAll: ('{1}{2}{3} = k->{2}{3};' format: {self varDeclKeyword. iv. s}); cr.
				isFromPrologue ifTrue: [
					cOut nextPutAll: ('{1}{2}_{3};' format: {self varDeclKeyword. iv. s}); cr.
				].
			].
		].	
	].
	cOut cr.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 10:45'!
emitKernelInitializerWithPrologue: prologue andBody: body

	cOut
		nextPutAll: 'if (!!k_->initialized) {'; cr; condTab; pushIndentationLevel;
		nextPutAll: 'k_->initialized = 1;'; cr.
"Transcript show: 'translating prologue...'; cr."
	self apply: #trans withArgs: {prologue}.
"Transcript show: 'done.'; cr."
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

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/8/2010 15:12'!
emitScalarPromotionOf: sName to: tType as: tName

	tType suffixNames do: [:suff |
		cOut nextPutAll: ('{1}{2}{3} = {4};' format: {self varDeclKeyword. tName. suff. sName}); cr.
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 18:37'!
emitScalar: x as: tmpName
	
	cOut nextPutAll: ('{1}{2} = {3};' format: {self varDeclKeyword. tmpName. x printString}); cr.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/8/2010 15:15'!
emitTuple: tmpName withElements: eNames andType: tmpType

	tmpType elementTypes withIndexDo: [:et :ii |
		et suffixNames do: [:s |
			cOut nextPutAll: ('{1}{2}_{3}{4} = {5}{4};' format: {self varDeclKeyword. tmpName. ii asString. s. eNames at: ii}); cr.
		].
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 03:56'!
emitUnaryOp: op on: x type: t into: ans

	t suffixNames do: [:suff |
		cOut nextPutAll: ('{1}{2}{3} = {4}({5}{3});' format: {self varDeclKeyword. ans. suff. op. x}); cr.
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 15:48'!
emitVarDeclFor: n initializedWith: v withType: t

	| in cv |
	in := self intern: n.
	cv := self coerce: v to: t.
	t suffixNames do: [:suff |
		(prologueVarNames includes: in) ifFalse: [cOut nextPutAll: self varDeclKeyword].
		cOut nextPutAll: ('{1}{2} = {3}{2};' format: {in. suff. cv}); cr.
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 10:36'!
ensureValidNodeType :nt =

	?[self respondsTo: nt asSymbol]
|	[self inform: 'unknown node type: ', nt] fail! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 17:23'!
epilogue = trans*! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 11:04'!
fieldAccess trans:wholeName :fieldName =

	[currentKernelVarTypes at: wholeName]:wholeType
	[wholeType isTupleType ifFalse: [self error: 'trying to access field ', fieldName, ' of non-tuple-type ', wholeType printString]]
	[(wholeType elementNames includes: fieldName) ifFalse: [self error: 'trying to access non-existent field ', fieldName, ' of tuple type ', wholeType printString]]
	[wholeType elementTypes at: (wholeType elementNames indexOf: fieldName)]:partType
	[wholeName, '_', fieldName]:partName
	[(currentKernelVarTypes includesKey: partName) ifFalse: [self declareVariable: partName withType: partType]]
	-> [partName]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 13:16'!
if trans:cond =

	[(currentKernelVarTypes at: cond) isScalarType ifFalse: [self error: 'condition of if-statement must be a scalar']]
	[currentForAllAssignments]:oldAs
	[currentKernelVarTypes]:oldKVTs

	[cOut nextPutAll: 'if (', cond, ') {'; cr; condTab; pushIndentationLevel]
	[oldAs   copy]:currentForAllAssignments
	[oldKVTs copy]:currentKernelVarTypes
	trans
	[currentForAllAssignments]:newAs1

	[cOut
		popIndentationLevel; nextPut: $}; cr;
		nextPutAll: 'else {'; cr; condTab; pushIndentationLevel]
	[oldAs   copy]:currentForAllAssignments
	[oldKVTs copy]:currentKernelVarTypes
	trans
	[currentForAllAssignments]:newAs2
	[cOut popIndentationLevel; nextPut: $}; cr]

	[newAs1 ifNotNil: [newAs1 union: newAs2]]:currentForAllAssignments
	[oldKVTs]:currentKernelVarTypes! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 19:39'!
in = 

	(
		trans:tmpName
		[currentKernelVarTypes at: tmpName]:tmpType
		[self emitInCommand: (self coerce: tmpName to: currentKernelType inputType) withType: currentKernelType inputType]
	)*! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/9/2010 14:17'!
initialize

	super initialize.
	globals := Dictionary new.
	types := Dictionary new
		at: 'Real' put: NileRealType new;
		at: 'Any' put: NileAnyType new;
		yourself.
	typedMacros := Dictionary new.
	cOut := self writeStream on: (String new: 1024).
	hOut := self writeStream on: (String new: 1024).
	numTmps := 0.! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/23/2010 14:51'!
initializePrimeVars

	prologueVarNames do: [:v |
		| iv |
		iv := self intern: v.
		(prologueVarTypes at: (prologueVarNames indexOf: v)) suffixNames do: [:s |
			cOut nextPutAll: ('{1}_{2} = {1}{2};' format: {iv. s}); cr.
		].
	].! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 21:31'!
intern: v

	| ans |
	ans := ((types includesKey: v) or: [(v beginsWith: 't_') or: [v beginsWith: 'v_']])
		ifTrue: [v]
		ifFalse: ['v_', v].
	^ ans! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/24/2010 11:20'!
kArg :t =

	pTransHelper(#pipeline. t):p -> [p key] // this is a kind of a hack to catch a {#pipeline...} before trans, so we can propagate the type info
|	pTransHelper(#kApp. t):p -> [p key]
|	trans
|	pTrans(t):a -> [a key]
|	pTransHelper(#offset. t)! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 10:51'!
kernel :name trans:currentKernelType =

//[Transcript show: 'starting to compile kernel ', name; cr]
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

//	[currentKernelVarTypes copy]:origCurrentKernelVarTypes
//[Transcript show: 'looking at prologue'; cr]
	{#prologue {#compound
		(	{#decl :n1 trans:dt1 :v1}
				[prologueVarNames add: (self intern: n1)]
				[prologueVarTypes add: (dt1 isAnyType ifTrue: [self typeOf: v1] ifFalse: [dt1])]
				[self declareVariable: prologueVarNames last withType: prologueVarTypes last]
		|	{#peekStmt {#var :n}}
				[prologueVarNames add: (self intern: n)]
				[prologueVarTypes add: currentKernelType inputType]
				[self declareVariable: prologueVarNames last withType: prologueVarTypes last]
		|	{#peekStmt {#tuple
				[prologueVarNames size]:offset
				({#var :n}
					[prologueVarNames add: (self intern: n)]
					[prologueVarTypes add: (currentKernelType inputType elementTypes at: prologueVarNames size - offset)]
					[self declareVariable: prologueVarNames last withType: prologueVarTypes last]
				)*
			}}
		|	:someOtherKindOfNode
		)*
	}}:prologue
//[Transcript show: 'done looking at prologue'; cr]
	//[origCurrentKernelVarTypes]:currentKernelVarTypes

	anything:body

	[self
		declareGlobal: name withType: currentKernelType;
		declareType: name toBe: currentKernelType]

	[self emitKernelDeclarationHeader: name]
	[self emitKernelFieldsAsLocalVars]
	[self emitKernelInitializerWithPrologue: prologue andBody: body]

	emitKernelBody(body)

	[self emitKernelDeclarationFooter]
//[Transcript show: 'done with kernel ', name; cr]
! !

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

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/16/2010 15:15'!
nileToTargetLangOperator: op

	" ignore the following line -- is just a hack to get around some silliness in the OMeta2 compiler "
	#().

	op = '='		ifTrue: [^ 'nile_Real_eq'].
	op = '≠'		ifTrue: [^ 'nile_Real_neq'].
	op = '×'		ifTrue: [^ 'nile_Real_mul'].
	op = '/'		ifTrue: [^ 'nile_Real_div'].
	op = '+'		ifTrue: [^ 'nile_Real_add'].
	op = '-'		ifTrue: [^ 'nile_Real_sub'].
	op = '<'		ifTrue: [^ 'nile_Real_lt'].
	op = '>'		ifTrue: [^ 'nile_Real_gt'].
	op = '≤'		ifTrue: [^ 'nile_Real_leq'].
	op = '≥'		ifTrue: [^ 'nile_Real_geq'].
	op = '∧'		ifTrue: [^ 'nile_Real_and'].
	op = '∨'		ifTrue: [^ 'nile_Real_or'].
	op = '⌈_⌉'	ifTrue: [^ 'nile_Real_clg'].
	op = '⌊_⌋'	ifTrue: [^ 'nile_Real_flr'].
	op = '√_'	ifTrue: [^ 'nile_Real_sqr'].
	op = '-_'	ifTrue: [^ 'nile_Real_neg'].
	self error: 'undefined operator ', op printString.! !

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

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/8/2010 15:23'!
ntType =

	nameTypePairs:ps -> [NileNamedTupleType elementTypes: (ps at: #types) elementNames: (ps at: #names)]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/11/2009 02:06'!
out trans:tmpName =

	[currentKernelVarTypes at: tmpName ifAbsent: [self error: tmpName, ' is undeclared']]:tmpType
	[self emitOutCommand: (self coerce: tmpName to: currentKernelType outputType) withType: currentKernelType outputType]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/25/2010 01:03'!
output

	| allLower allCaps |
	allLower := prefix asLowercase allButLast.
	allCaps := prefix asUppercase allButLast.
	^ {
		(WriteStream on: (String new: 1024))
			nextPutAll: '#ifndef ', allCaps, '_H'; cr;
			nextPutAll: '#define ', allCaps, '_H'; cr; cr;
			nextPutAll: '#include "nile.h"'; cr; cr;
			nextPutAll: hOut contents; cr; cr;
			nextPutAll: '#endif'; cr; cr;
			contents.
		(WriteStream on: (String new: 1024))
			nextPutAll: '#include <stddef.h>'; cr;
			nextPutAll: '#include "', allLower, '.h"'; cr; cr;
			nextPutAll: cOut contents;
			contents
	}! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 12:13'!
peek =

	transPat(currentKernelType inputType):pvs
		[pvs do: [:pv | cOut nextPutAll: pv; nextPutAll: ' = in->data[in->i++];'; cr]]
		[cOut nextPutAll: 'in->i -= ', pvs size printString, ';'; cr]

	trans! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/24/2010 17:33'!
peekStmt =

	transPat(currentKernelType inputType):pvs
		[pvs do: [:pv | cOut nextPutAll: pv; nextPutAll: ' = in->data[in->i++];'; cr]]
		[cOut nextPutAll: 'in->i -= ', pvs size printString, ';'; cr]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/13/2009 17:09'!
pipeline =

	pPipeline(currentKernelType inputType):ans
	-> [ans key]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/24/2010 13:54'!
pKApp :ttt 'Mix' =

	kArg(ttt):k1 [currentKernelVarTypes at: k1]:tk1
	kArg(ttt):k2 [currentKernelVarTypes at: k2]:tk2
	[self newTmpName]:ans
	[tk1 ~= tk2 ifTrue: [self error: 'Mix applied to kernels of different types']]
	[NileAbstractKernelType
		argumentNames: #('a' 'b')
		argumentTypes: {tk1. tk1}
		underlyingKernelType: tk1]:it
	[self declareVariable: ans withType: tk1]
	[self emitKApp: 'Mix' withType: it andArgs: {k1. k2} into: ans]
	-> [ans -> tk1 outputType],

pKApp :ttt 'Interleave' =

	kArg(ttt):k1 [currentKernelVarTypes at: k1]:tk1 trans({#scalar. tk1 outputType size}):k1s
	kArg(ttt):k2 [currentKernelVarTypes at: k2]:tk2 trans({#scalar. tk2 outputType size}):k2s
	[self newTmpName]:ans
	[(NileKernelType
		inputType: tk1 inputType
		outputType: (NileTupleType elementTypes: {tk1 outputType. tk2 outputType}))]:ikt
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

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/24/2010 19:36'!
pVar :ttt =

	:name  [self intern: name]:iName [currentKernelVarTypes at: iName]:kt
		(
			?[name = iName] -> [prefix, iName, '(nl)' -> kt outputType]
		|
			-> [iName -> kt outputType]
		)! !

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

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/24/2010 18:05'!
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
	|	//[Transcript show: 'declaring variable ', iName, ' with type ', patType printString; cr]
		[self declareVariable: iName withType: patType]
			-> [((prologueVarNames includes: iName) ifTrue: [''] ifFalse: [self varDeclKeyword]), iName]
	):name
	-> [patType suffixNames collect: [:s | name, s]],

transPat :patType =
	{#wildcard}
	[self newTmpName]:iName
	-> [patType suffixNames collect: [:s |
			cOut nextPutAll: ('{1}{2}{3};' format: {self varDeclKeyword. iName. s}); cr.
			iName, s
		]],

transPat :patType =
	?[patType isTupleType]
	[1]:ii
	[OrderedCollection new]:ans
	{#tuple
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

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/8/2010 15:23'!
tType =

	trans*:ts -> [NileTupleType elementTypes: ts]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/8/2010 15:15'!
tuple =

	[self newTmpName]:tmpName
	trans*:elementNames
	[elementNames collect: [:n | currentKernelVarTypes at: n]]:elementTypes
	[NileTupleType elementTypes: elementTypes]:tmpType
	[self declareVariable: tmpName withType: tmpType]
	[self emitTuple: tmpName withElements: elementNames andType: tmpType]
	-> [tmpName]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 14:30'!
typeDef :tn trans:t =

//	[tn = 'ImageExtendMode' ifTrue: [self halt]]

	[globals copy]:currentKernelVarTypes                    // so we don't need to use 2 dicts for lookup
	[Set new]:currentKernelAssignableVars
	[OrderedCollection new]:prologueVarNames
	[OrderedCollection new]:prologueVarTypes

	[self declareType: tn toBe: t] -> [t]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 13:47'!
typedExpr trans:e trans:t = [self coerce: e to: t]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/11/2010 16:14'!
typedMacro :op :nx trans:tx :ny (exactly(nil) | trans):ty trans:tans :body =

	[(typedMacros includesKey: op) ifTrue: [self error: 'cannot redefine typed macro: ', op]]
	[typedMacros at: op put: (NileTypedMacroType nop1: nx top1: tx nop2: ny top2: ty tans: tans macroBody: body)]! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 11:16'!
typeOf: expr

	| oldCOut n |
	oldCOut := cOut.
	cOut := self writeStream on: (String new: 64).
	" compile a copy of expr so that later on we don't get back a variable that doesn't exist from the memo table "
	n := self apply: #trans withArgs: {expr copy}.
	cOut := oldCOut.
	^ currentKernelVarTypes at: n! !

!NileCTranslator methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 11:34'!
unOp :op trans:x =

	// op is a typed macro
	?[typedMacros includesKey: op]
	[typedMacros at: op]:macroType
	(
		?[macroType canBeUsedPairwise]
		[currentKernelVarTypes at: x]:tx
		?[tx isTupleType]
		[tx elementNames collect: [:en |
			{#var. self apply: #trans withArgs: {macroType expandWithArgs: {{#fieldAccess. {#var. x}. en}}}}
		]]:es
		trans({#tuple}, es):ans
		-> [self coerce: ans to: tx]
	|
		[self coerce: x to: macroType top1]:cx
		trans(macroType expandWithArgs: {{#var. cx}}):ans
		-> [self coerce: ans to: macroType tans]
	)

|

	// op is not a typed macro
	?[(typedMacros includesKey: op) not]
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

!NileCTranslator class methodsFor: 'as yet unclassified' stamp: 'aw 2/23/2010 15:57'!
initialize

	"
		self initialize
	"
	BuiltInKernelNames := #('Interleave' 'GroupBy' 'SortBy' 'Mix') asSet.! !

!NileCTranslator class methodsFor: 'as yet unclassified' stamp: 'aw 2/25/2010 00:43'!
nileParser

	^ NileParser! !

!NileCTranslator class methodsFor: 'as yet unclassified' stamp: 'aw 2/25/2010 01:01'!
translate: files in: folder withPrefix: prefix

	| input tree code |
	input := WriteStream on: (String new: 1024).
	tree := OrderedCollection new.
	files do: [:file |
		| stream |
		stream := FileStream readOnlyFileNamed: folder, file.
		stream wantsLineEndConversion: true.
		input nextPutAll: stream contents; cr; cr.
	].
	tree := self nileParser matchAll: input contents with: #start.
	code := self match: {prefix. tree} with: #start.
	(FileStream newFileNamed: folder, prefix, '.h') wantsLineEndConversion: true; nextPutAll: code first;  close.
	(FileStream newFileNamed: folder, prefix, '.c') wantsLineEndConversion: true; nextPutAll: code second; close.! !


OMeta2 subclass: #NileMacroExpander
	instanceVariableNames: 'actuals'
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileMacroExpander methodsFor: 'as yet unclassified' stamp: 'aw 2/11/2010 16:30'!
exp {#var :x} = ?[actuals includesKey: x]       -> [actuals at: x],
exp {#var :x} = ?[(actuals includesKey: x) not] -> [{#var. x}],
exp string:s  =                                 -> [s],
exp number:n  =                                 -> [n],
exp {exp*:xs} =                                 -> [xs asArray]! !

!NileMacroExpander methodsFor: 'as yet unclassified' stamp: 'aw 2/9/2010 11:59'!
expand :actuals = exp! !


Object subclass: #NileType
	instanceVariableNames: ''
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 04:34'!
isAbstractKernelType

	^ false! !

!NileType methodsFor: 'as yet unclassified' stamp: 'aw 2/9/2010 14:29'!
isAnyType

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

!NileKernelType methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 15:16'!
underlyingKernelType

	^ nil! !

!NileKernelType methodsFor: 'as yet unclassified' stamp: 'aw 2/23/2010 15:54'!
= aKernelType

	^
		inputType = aKernelType inputType and: [
		outputType = aKernelType outputType and: [
		self argumentNames = aKernelType argumentNames and: [
		self argumentTypes = aKernelType argumentTypes
	]]]! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

NileKernelType class
	instanceVariableNames: ''!

!NileKernelType class methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 02:46'!
inputType: it outputType: ot

	^ self new inputType: it outputType: ot! !


NileType subclass: #NileTypedMacroType
	instanceVariableNames: 'top1 top2 tans nop1 nop2 macroBody'
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileTypedMacroType methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 11:23'!
canBeUsedPairwise

	^ top1 isRealType and: [
		(top2 isNil or: [top2 isRealType]) and: [tans isRealType]
	]! !

!NileTypedMacroType methodsFor: 'as yet unclassified' stamp: 'aw 2/11/2010 16:27'!
expandWithArgs: actuals

	| dict ans |
	dict := Dictionary new.
	dict at: nop1 put: (actuals at: 1).
	dict at: nop2 put: (actuals at: 2 ifAbsent: [nil]).
	ans := NileMacroExpander matchAll: {dict. macroBody} with: #expand.
	^ ans! !

!NileTypedMacroType methodsFor: 'as yet unclassified' stamp: 'aw 2/9/2010 14:46'!
nop1: n1 top1: t1 nop2: n2 top2: t2 tans: ta macroBody: m

	nop1 := n1.
	top1 := t1.
	nop2 := n2.
	top2 := t2.
	tans := ta.
	macroBody := m.! !

!NileTypedMacroType methodsFor: 'as yet unclassified' stamp: 'aw 2/11/2010 16:18'!
printOn: aStream

	aStream nextPutAll: 'TypedMacroType['.
	nop1 printOn: aStream. aStream nextPutAll: ', '.
	top1 printOn: aStream. aStream nextPutAll: ', '.
	nop2 printOn: aStream. aStream nextPutAll: ', '.
	top2 printOn: aStream. aStream nextPutAll: ', '.
	tans printOn: aStream. aStream nextPutAll: ', '.
	macroBody printOn: aStream.
	aStream nextPut: $].! !

!NileTypedMacroType methodsFor: 'as yet unclassified' stamp: 'aw 9/21/2009 13:44'!
tans

	^ tans! !

!NileTypedMacroType methodsFor: 'as yet unclassified' stamp: 'aw 9/21/2009 13:44'!
top1

	^ top1! !

!NileTypedMacroType methodsFor: 'as yet unclassified' stamp: 'aw 9/21/2009 13:44'!
top2

	^ top2! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

NileTypedMacroType class
	instanceVariableNames: ''!

!NileTypedMacroType class methodsFor: 'as yet unclassified' stamp: 'aw 2/9/2010 14:47'!
nop1: n1 top1: t1 nop2: n2 top2: t2 tans: ta macroBody: m

	^ self new nop1: n1 top1: t1 nop2: n2 top2: t2 tans: ta macroBody: m! !


NileType subclass: #NileValueType
	instanceVariableNames: ''
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileValueType methodsFor: 'as yet unclassified' stamp: 'aw 10/7/2009 13:59'!
isColorComponentType

	^ true! !

!NileValueType methodsFor: 'as yet unclassified' stamp: 'aw 2/8/2010 15:01'!
isNamedTupleType

	^ false! !

!NileValueType methodsFor: 'as yet unclassified' stamp: 'aw 10/7/2009 13:58'!
isRealType

	^ false! !

!NileValueType methodsFor: 'as yet unclassified' stamp: 'aw 9/19/2009 12:12'!
isScalarType

	^ false! !

!NileValueType methodsFor: 'as yet unclassified' stamp: 'aw 2/8/2010 15:01'!
isTupleType

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


NileValueType subclass: #NileAnyType
	instanceVariableNames: ''
	classVariableNames: 'Singleton'
	poolDictionaries: ''
	category: 'Nile'!

!NileAnyType methodsFor: 'as yet unclassified' stamp: 'aw 2/9/2010 14:27'!
isAnyType

	^ true! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

NileAnyType class
	instanceVariableNames: ''!

!NileAnyType class methodsFor: 'as yet unclassified' stamp: 'aw 2/9/2010 14:16'!
new

	^ Singleton ifNil: [
		Singleton := self basicNew.
	]! !


NileValueType subclass: #NileScalarType
	instanceVariableNames: ''
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileScalarType methodsFor: 'as yet unclassified' stamp: 'aw 9/19/2009 12:12'!
isScalarType

	^ true! !

!NileScalarType methodsFor: 'as yet unclassified' stamp: 'aw 2/8/2010 15:01'!
max: anotherType

	^ anotherType isTupleType
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


NileValueType subclass: #NileTupleType
	instanceVariableNames: 'suffixNames elementTypes elementNames'
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileTupleType methodsFor: 'as yet unclassified' stamp: 'aw 12/15/2009 13:40'!
elementNames

	^ elementNames ifNil: [elementNames :=  (1 to: elementTypes size) collect: [:ii | ii printString]]! !

!NileTupleType methodsFor: 'as yet unclassified' stamp: 'aw 9/18/2009 13:32'!
elementTypes

	^ elementTypes! !

!NileTupleType methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 13:36'!
elementTypes: ets

	elementTypes := ets.! !

!NileTupleType methodsFor: 'as yet unclassified' stamp: 'aw 2/8/2010 15:18'!
isTupleType

	^ true! !

!NileTupleType methodsFor: 'as yet unclassified' stamp: 'aw 2/8/2010 15:02'!
max: anotherType

	^ anotherType isNamedTupleType
		ifTrue: [anotherType]
		ifFalse: [self]! !

!NileTupleType methodsFor: 'as yet unclassified' stamp: 'aw 12/15/2009 13:42'!
printOn: aStream

	aStream nextPut: $[.
	elementTypes
		do: [:et | et printOn: aStream]
		separatedBy: [aStream nextPutAll: ', '].
	aStream nextPut: $].! !

!NileTupleType methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 13:57'!
size

	^ self suffixNames size! !

!NileTupleType methodsFor: 'as yet unclassified' stamp: 'aw 12/17/2009 13:43'!
suffixNames

	^ suffixNames ifNil: [
		suffixNames := OrderedCollection new.
		elementTypes withIndexDo: [:et :ii |
			et suffixNames do: [:sn | suffixNames add: '_', ii printString, sn].
		].
		suffixNames
	]! !

!NileTupleType methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 14:08'!
underlyingScalarType
	" returns nil if I am not homogeneous "

	| st |
	st := elementTypes first underlyingScalarType.
	elementTypes do: [:et |
		st ~~ et underlyingScalarType ifTrue: [^ nil].
	].
	^ st! !

!NileTupleType methodsFor: 'as yet unclassified' stamp: 'aw 2/8/2010 15:02'!
= t

	t isTupleType ifFalse: [^ false].
	t isNamedTupleType ifTrue: [^ false].
	elementTypes size ~~ t elementTypes size ifTrue: [^ false].
	elementTypes with: t elementTypes do: [:et1 :et2 |
		et1 ~= et2 ifTrue: [^ false].
	].
	^ true! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

NileTupleType class
	instanceVariableNames: ''!

!NileTupleType class methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 13:36'!
elementTypes: ets

	^ self new elementTypes: ets! !


NileTupleType subclass: #NileNamedTupleType
	instanceVariableNames: ''
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileNamedTupleType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 00:47'!
elementNames

	^ elementNames! !

!NileNamedTupleType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 00:47'!
elementNames: ens

	elementNames := ens.
	elementNames size ~= elementTypes size ifTrue: [
		self error: 'invalid named vector type'.
	].! !

!NileNamedTupleType methodsFor: 'as yet unclassified' stamp: 'aw 2/8/2010 15:17'!
isNamedTupleType
	
	^ true! !

!NileNamedTupleType methodsFor: 'as yet unclassified' stamp: 'aw 9/19/2009 15:10'!
max: anotherType

	^ self! !

!NileNamedTupleType methodsFor: 'as yet unclassified' stamp: 'aw 12/14/2009 23:07'!
offsetOfField: f

	| r |
	r := 0.
	elementNames with: elementTypes do: [:n :t |
		n = f ifTrue: [^ r].
		r := r + t suffixNames size.
	].
	self error: f, ' is not a valid field name for type ', self printString! !

!NileNamedTupleType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 00:47'!
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

!NileNamedTupleType methodsFor: 'as yet unclassified' stamp: 'aw 9/22/2009 00:47'!
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

!NileNamedTupleType methodsFor: 'as yet unclassified' stamp: 'aw 2/8/2010 15:02'!
= t

	t isNamedTupleType ifFalse: [^ false].
	elementTypes size ~~ t elementTypes size ifTrue: [^ false].
	elementTypes with: t elementTypes do: [:et1 :et2 |
		et1 ~= et2 ifTrue: [^ false].
	].
	elementNames with: t elementNames do: [:en1 :en2 |
		en1 ~= en2 ifTrue: [^ false].
	].
	^ true! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

NileNamedTupleType class
	instanceVariableNames: ''!

!NileNamedTupleType class methodsFor: 'as yet unclassified' stamp: 'aw 9/17/2009 13:40'!
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
	instanceVariableNames: 'builtInOps prefixes infixOps'
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Nile'!

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/8/2010 15:20'!
akType =

	"(" listOf(#tTypeP. ','):as ")" ":" kType:kt -> [{#akType. as. kt}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/8/2009 11:34'!
arrowKis =

	"⇒" kis! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/10/2010 17:35'!
aType =

	"(" listOf(#tTypeP. ','):ps ")" -> [{#ntType}, ps]
|	"(" listOf(#aType. ','):ts ")" -> [{#tType}, ts]
|	ident:t -> [{#nType. t}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 13:37'!
block =

	indented(#stmts)
|	empty -> [{#compound}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 16:17'!
body =

	prologue:p (computing | forwarding):b -> [{p. b}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 21:47'!
computing =

	indent(nil) "∀" pat:p eol block:b epilogue:e -> [{#forAll. p. b. e}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/10/2010 16:12'!
condExpr =

	expr:x "if" expr:c "," condExpr:y -> [{#condExpr. c. x. y}]
|	expr! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 15:18'!
epilogue =

	stmts:ss -> [{#epilogue. ss}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/10/2010 14:45'!
expr =

	expr7! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/16/2010 15:59'!
expr0 =

	"√" 			expr0:e -> [{#unOp. '√_'. e}]
|	"-"			expr0:e -> [{#unOp. '-_'. e}]
|	prefixOp:op	expr0:e -> [{#unOp. op, '_'. e}]
|	primExpr! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/22/2010 13:46'!
expr1 =

	expr1:e "." ident:f    -> [{#fieldAccess. e. f}]
|	expr1:e "[" expr:i "]" -> [{#index. e. i}]
|	expr0:e ":" aType:t    -> [{#typedExpr. e. t}]
|	expr0! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/16/2010 15:15'!
expr2 =

	expr2:x "×" expr1:y -> [{#binOp. x. '×'. y}]
|	expr2:x "/" expr1:y -> [{#binOp. x. '/'. y}]
|	expr1! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/11/2010 13:22'!
expr3 =

	expr3:x "+"        expr2:y -> [{#binOp. x. '+'. y}]
|	expr3:x "-"        expr2:y -> [{#binOp. x. '-'. y}]
|	expr3:x infixOp:op expr2:y -> [{#binOp. x. op.  y}]
|	expr2! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/16/2010 15:05'!
expr4 =

	expr3:x "<" expr3:y -> [{#binOp. x. '<'. y}]
|	expr3:x "≤" expr3:y -> [{#binOp. x. '≤'. y}]
|	expr3:x ">" expr3:y -> [{#binOp. x. '>'. y}]
|	expr3:x "≥" expr3:y -> [{#binOp. x. '≥'. y}]
|	expr3! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/10/2010 16:09'!
expr5 =

	expr4:x "=" expr4:y -> [{#binOp. x. '='. y}]
|	expr4:x "≠" expr4:y -> [{#binOp. x. '≠'. y}]
|	expr4! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/10/2010 16:09'!
expr6 =

	expr6:x "∧" expr5:y -> [{#binOp. x. '∧'. y}]
|	expr5! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/10/2010 16:09'!
expr7 =

	expr7:x "∨" expr6:y -> [{#binOp. x. '∨'. y}]
|	expr6! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/19/2010 13:20'!
exprs =

	expr:x ("," optEol expr)+:xs -> [xs addFirst: x; yourself]! !

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

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/11/2010 13:21'!
infixOp = spaces <[self trieMatch: infixOps]>! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/16/2010 15:16'!
initialize

	super initialize.
	builtInOps := Set withAll: #(× / + - < ≤ < = ≠ ∧ ∨ √ > >>).
	infixOps := nil -> Dictionary new.
	prefixes := nil -> Dictionary new.! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/3/2009 11:11'!
kasPart =

	listOf(#ident. ','):ns ":"  ident:t -> [{t. ns}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 16:11'!
kernel =

	ident:n (akType | ":" kType):t eol indented(#body):b -> [{#kernel. n. t. b first. b second}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/19/2010 13:25'!
ki =

	ident:k 	"(" kisOrExpr:a ("," optEol kisOrExpr)*:as ")" -> [{#kApp. k. a}, as]
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

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/16/2010 15:23'!
op = spaces ~pref <opChar+>:x ?[(builtInOps includes: x) not] -> [x]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/10/2010 18:08'!
opChar =

	~(space | nl | $( | $) | ${ | $} | $, | $: | $@ | $_ | letter | digit) char! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/11/2010 16:07'!
opDef =

	"(" ident:n1 ":" aType:t1 ")" op:op "(" ident:n2 ":" aType:t2 ")" ":" aType:t eol opDefBody:body
		[self trie: infixOps at: op put: true]
		-> [{#typedMacro. op. n1. t1. n2. t2. t. body}]
|	op:p "(" ident:n1 ":" aType:t1 ")" op:s ":" aType:t eol opDefBody:body
		[self trie: prefixes at: p put: s]
		-> [{#typedMacro. p, '_', s. n1. t1. nil. nil. t. body}]
|	op:p "(" ident:n1 ":" aType:t1 ")" ":" aType:t eol opDefBody:body
		[self trie: prefixes at: p put: true]
		-> [{#typedMacro. p, '_'. n1. t1. nil. nil. t. body}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/10/2010 11:03'!
opDefBody =

	indent(nil)	expr:b eol -> [b]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/19/2010 13:18'!
optEol =

	spaces eol | empty! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/16/2010 14:40'!
pat =

	ident:x -> [{#var. x}]
|	"_" -> [{#wildcard}]
|	"(" listOf(#pat. ','):ps ")" -> [{#tuple}, ps]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/11/2010 16:03'!
pref = spaces <[self trieMatch: prefixes]>:p ?[(self trie: prefixes at: p) isString] -> [p]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/11/2010 16:05'!
prefixOp = spaces <[self trieMatch: prefixes]>:p ?[(self trie: prefixes at: p) == true] -> [p]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/11/2010 13:25'!
primExpr =

	ident:x -> [{#var. x}]
|	scalar:s -> [{#scalar. s}]
|	"{" condExpr:x "}" -> [x]
|	"∧[" expr:x "]" -> [{#reduce. '∧'. x}]
|	"∨[" expr:x "]" -> [{#reduce. '∨'. x}]
|	"[" exprs:xs "]" -> [{#tuple}, xs]
|	"(" exprs:xs ")" -> [{#tuple}, xs]
|	"(" expr:x ")" -> [x]
|	"⌊" expr:x "⌋" -> [{#unOp. '⌊_⌋'. x}]
|	"⌈" expr:x "⌉" -> [{#unOp. '⌈_⌉'. x}]
|	pref:p expr:x suff(p):s -> [{#unOp. p, '_', s. x}]
|	"@" nsIdent:x -> [{#offset. x}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 15:18'!
prologue =

	stmts:ss -> [{#prologue. ss}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/10/2010 17:05'!
restOfInput = <anything*>! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/2/2009 12:10'!
scalar =

	spaces digit+:is $. digit+:fs -> [(String withAll: is, '.', fs) asNumber]
|	spaces digit+:is -> [(String withAll: is) asNumber]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/10/2010 17:24'!
space =

	^space
|	``{-'' (~``-}'' char)* ``-}'' (eol | empty)! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/10/2010 17:21'!
start =

	((space | nl)* topLevel)*:ans (space | nl)* end -> [ans]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/19/2010 13:32'!
stmt :dummy =

	indent(nil)	( ">>" expr:e -> [{#out. e}]
					| ">" primExpr:n $> expr:e -> [{#nOut. n. e}]
					)+:outs eol -> [{#compound}, outs]
|	indent(nil) ("<<" expr)*:es eol -> [{#in}, es]
|	indent(nil) ident:x ?[(x endsWith: '_') not] "=" expr:e eol -> [{#decl. x. {#nType. 'Any'}. e}]
|	indent(nil) ident:x ?[(x endsWith: '_') not] ":" aType:t "=" expr:e eol -> [{#decl. x. t. e}]
|	indent(nil) ident:x ?[x endsWith: '_'] "=" expr:e eol -> [{#assign. x allButLast. e}]
|	indent(nil) "&" pat:p eol -> [{#peekStmt. p}]
|	indent(nil) ifStmt! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 12/10/2009 12:32'!
stmts =

	stmt(nil)*:xs -> [{#compound}, xs]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/11/2010 13:23'!
suff :p = [self trie: prefixes at: p]:s spaces seq(s)! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/9/2010 16:15'!
topLevel =

	kernel | typeDef | opDef! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/11/2010 13:16'!
trieMatch: trie

	^ self ometaOr: {
		[self trieMatch: (trie value at: (self apply: #anything) ifAbsent: [OM2Fail signal])].
		[self pred: trie key notNil]
	}! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/11/2010 13:17'!
trie: origTrie at: p

	| trie |
	trie := origTrie.
	p doWithIndex: [:c :i |
		trie := trie value at: c ifAbsent: [OMeta2Fail signal].
		i == p size ifTrue: [
			trie key ifNil: [OMeta2Fail signal].
			^ trie key
		].
	].! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/11/2010 16:06'!
trie: origTrie at: p put: s

	| trie |
	trie := origTrie.
	p withIndexDo: [:c :i |
		trie := trie value at: c ifAbsentPut: [nil -> Dictionary new].
		i == p size ifTrue: [
			trie key ifNotNil: [self error: 'more than one store into same key (', p, ') in a trie'].
			trie key: s.
		].
	].! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/8/2010 15:20'!
tTypeP =

	listOf(#ident. ','):ns ":" aType:t -> [{t. ns}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/10/2010 17:35'!
typeDef =

	ident:n ("<:" aType:t -> [t] | "::" (akType | kType)):t -> [{#typeDef. n. t}]! !

!NileParser methodsFor: 'as yet unclassified' stamp: 'aw 2/11/2010 16:53'!
xstmt = stmt(nil)! !

"-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- "!

NileParser class
	instanceVariableNames: ''!

!NileParser class methodsFor: 'as yet unclassified' stamp: 'aw 2/10/2010 18:00'!
debugParse: fileName

	| stream |
	stream := FileStream readOnlyFileNamed: '/Users/awarth/prog/dan/gezira/', fileName.
	stream wantsLineEndConversion: true.
	^ NileParser debugMatchAll: stream with: #start! !

!NileParser class methodsFor: 'as yet unclassified' stamp: 'aw 2/10/2010 17:42'!
parse: fileName

	| stream |
	stream := FileStream readOnlyFileNamed: '/Users/awarth/prog/dan/gezira/', fileName.
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
