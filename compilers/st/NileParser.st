initialize

       super initialize.
       builtInOps := Set withAll: #(× / + - < ≤ ≥ > = ≠ ∧ ∨ √ << >> ¬).
       infixOps := nil -> Dictionary new.
       prefixes := nil -> Dictionary new.
       
start =

       ((space | nl)* topLevel)*:ans (space | nl)* (<anything+>:rest [rest inspect] [OM2Fail signal] | end -> [ans])

token

        | t |
        t := self apply: #anything.
        self apply: #spaces.
        ^ self apply: #seq withArgs: {t}

nsIdent =

        <letter letterOrDigit*>:n ($' -> ['_'] | empty -> ['']):p -> [n, p]

ident =

        spaces nsIdent
        
space =

        ^space
|       $\ eol
|       fromTo('{-', '-}') eol?

spaceNlOk =

        space
|       nl indent(nil)

optEol =

        (spaces eol)?
               
topLevel =

       typeDef | opDef | processDef
       
typeDef =

       "type" ident:n "=" (recType | procType):t -> [{#typeDef. n. t}]
       
recType =
        
        "(" listOf(#recTypePart. ','):ps ")" -> [{#recType}, ps]
    
recTypePart =

        listOf(#ident. ','):is ":" typeName:t -> [{t. is}]

typeName =

        ident:t -> [{#typeName. t}]

procType =

       (typeName | tupleType):t1 ">>" (typeName | tupleType):t2 -> [{#procType. t1. t2}]

tupleType =

       "(" listOf(#typeName. ','):ts ")" -> [{#tupleType}, ts]
       
opDef =

        "(" ident:n1 ":" typeName:t1 ")" op:op "(" ident:n2 ":" typeName:t2 ")" ":" typeName:t eol opDefBody:body
                [self trie: infixOps at: op put: true]
                -> [{#opDef. op. n1. t1. n2. t2. t. body}]
|       op:p "(" ident:n1 ":" typeName:t1 ")" op:s ":" typeName:t eol opDefBody:body
                [self trie: prefixes at: p put: s]
                -> [{#opDef. p, '_', s. n1. t1. nil. nil. t. body}]
|       op:p "(" ident:n1 ":" typeName:t1 ")" ":" typeName:t eol opDefBody:body
                [self trie: prefixes at: p put: true]
                -> [{#opDef. p, '_'. n1. t1. nil. nil. t. body}]
        
op =

        ~outfixOpen spaces <opChar+>:x ?[(builtInOps includes: x) not] -> [x]
    
outfixOpen =

        spaces <[self trieMatch: prefixes]>:p ?[(self trie: prefixes at: p) isString] -> [p]

outfixClose :p =

        [self trie: prefixes at: p]:s spaces seq(s)

prefixOp =

        spaces <[self trieMatch: prefixes]>:p ?[(self trie: prefixes at: p) == true] -> [p]

infixOp =

        spaces <[self trieMatch: infixOps]>

opChar =

        ~(space | nl | $( | $) | ${ | $} | $, | $: | $@ | $_ | $\ | letter | digit) char

opDefBody =

        indent(nil) expr:b eol -> [b]

expr =

        expr8

expr8 =

        expr8:x "∨" expr7:y -> [{#binOp. x. '∨'. y}]
|       expr7

expr7 =

        expr7:x "∧" expr6:y -> [{#binOp. x. '∧'. y}]
|       expr6

expr6 =

        expr5:x "=" expr5:y -> [{#binOp. x. '='. y}]
|       expr5:x "≠" expr5:y -> [{#binOp. x. '≠'. y}]
|       expr5

expr5 =

        expr4:x "<" expr4:y -> [{#binOp. x. '<'. y}]
|       expr4:x "≤" expr4:y -> [{#binOp. x. '≤'. y}]
|       expr4:x ">" expr4:y -> [{#binOp. x. '>'. y}]
|       expr4:x "≥" expr4:y -> [{#binOp. x. '≥'. y}]
|       expr4

expr4 =

        expr4:x "+"        expr3:y -> [{#binOp. x. '+'. y}]
|       expr4:x "-"        expr3:y -> [{#binOp. x. '-'. y}]
|       expr4:x infixOp:op expr3:y -> [{#binOp. x. op.  y}]
|       expr3

expr3 =

        expr3:x "×" expr2:y -> [{#binOp. x. '×'. y}]
|       expr3:x "/" expr2:y -> [{#binOp. x. '/'. y}]
|       expr2

expr2 =

        expr2:e "." ident:f    -> [{#fieldAccess. e. f}]
|       expr1:e ":" typeName:t -> [{#typedExpr. e. t}]
|       expr1

expr1 =

        "√"         expr0:e -> [{#unOp. '√_'. e}]
|       "-"         expr0:e -> [{#unOp. '-_'. e}]
|       "¬"         expr0:e -> [{#unOp. '¬_'. e}]
|       prefixOp:op expr0:e -> [{#unOp. op, '_'. e}]
|       expr0

expr0 =

        ident:x -> [{#var. x}]
|       scalar:s -> [{#scalar. s}]
|       "{" condExpr:x "}" -> [x]
|       "(" exprs:xs ")" -> [{#tuple}, xs]
|       "(" expr:x ")" -> [x]
|       "⌊" expr:x "⌋" -> [{#unOp. '⌊_⌋'. x}]
|       "⌈" expr:x "⌉" -> [{#unOp. '⌈_⌉'. x}]
|       outfixOpen:p expr:x outfixClose(p):s -> [{#unOp. p, '_', s. x}]
|       "@" nsIdent:f -> [{#offset. f}]

scalar =

        <digit+ ($. digit+)?>:s -> [s asNumber]

condExpr =

        expr:x "if" expr:c "," optEol condExpr:y -> [{#condExpr. c. x. y}]
|       expr:x "otherwise"? -> [x]

exprs =

        expr:x ("," optEol expr)+:xs -> [xs addFirst: x; yourself]

processDef =

        ident:n processFormalArgs?:as ":" procType:t eol indented(#prologue):p indented(#body):b indented(#epilogue):e
        -> [{#processDef. n. as. t. p. b. e}]    

processFormalArgs =
        
        "(" listOf(#recTypePart. ','):as ")" -> [{#args}, ps]

prologue =

        stmts:ss -> [{#prologue. ss}]
    
body =

        indent(nil) "∀" pat:p eol indented(#stmts)?:b -> [{#body. p. b}]
    
epilogue =

        stmts:ss -> [{#epilogue. ss}]
    
stmts =

        stmt(nil)*:xs -> [{#compound}, xs]
    
stmt :dummy =

        indent(nil) (">>" expr)+:es eol -> [{#out}, es]
|       indent(nil) ("<<" expr)+:es eol -> [{#in},  es]
|       indent(nil) ident:x ?[(x endsWith: '_') not]                "=" expr:e eol -> [{#decl. x. {#typeName. 'Any'}. e}]
|       indent(nil) ident:x ?[(x endsWith: '_') not] ":" typeName:t "=" expr:e eol -> [{#decl. x. t. e}]
|       indent(nil) ident:x ?[x endsWith: '_']                      "=" expr:e eol -> [{#assign. x allButLast. e}]
|       indent(nil) pat:p                                           "=" expr:e eol -> [{#patAssign. p. e}]
|       indent(nil) ifStmt
|       indent(nil) "⇒" pipeline:p eol -> [{#replace. p}]
        
pipeline =

        processInstantiation:x "→" optEol pipeline:y -> [{#pipeline. x. y}]
|       processInstantiation

processInstantiation =

        ident:p "(" processActualArgs:as ")" -> [{#processInstantiation. p}, as]
|       ident:p                              -> [{#processInstantiation. p}]
|       "(" "→" ")" -> [{#pipeline}]


processActualArgs =

        processActualArg:a ("," optEol processActualArg)*:as -> [as addFirst: a]
        
processActualArg =

        expr | pipeline

ifStmt =

        "if" expr:c eol
            indented(#stmts)?:t
            (indent(nil) "else" (ifStmt | eol indented(#stmts)?)
            | empty -> [{#noOp}]
            ):e
            -> [{#if. c. t. e}]
        
pat =

        ident:x -> [{#varPat. x}]
|       "_" -> [{#wildcardPat}]
|       "(" listOf(#pat. ','):ps ")" -> [{#tuplePat}, ps]

trieMatch: trie

    ^ self ometaOr: {
        [self trieMatch: (trie value at: (self apply: #anything) ifAbsent: [OM2Fail signal])].
        [self pred: trie key notNil]
    }

trie: origTrie at: p

    | trie |
    trie := origTrie.
    p doWithIndex: [:c :i |
        trie := trie value at: c ifAbsent: [OMeta2Fail signal].
        i == p size ifTrue: [
            trie key ifNil: [OMeta2Fail signal].
            ^ trie key
        ].
    ].

trie: origTrie at: p put: s

    | trie |
    trie := origTrie.
    p withIndexDo: [:c :i |
        trie := trie value at: c ifAbsentPut: [nil -> Dictionary new].
        i == p size ifTrue: [
            trie key ifNotNil: [self error: 'more than one store into same key (', p, ') in a trie'].
            trie key: s.
        ].
    ].
