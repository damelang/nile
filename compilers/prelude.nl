-- Types

type Boolean
type Integer
type Real

-- Operators

¬a:Boolean : Boolean

a:Boolean ∨ b:Boolean : Boolean

a:Boolean ∧ b:Boolean : Boolean

-a:Integer : Integer

a:Integer = b:Integer : Boolean

a:Integer ≠ b:Integer : Boolean

a:Integer < b:Integer : Boolean

a:Integer + b:Integer : Integer

-a:Real : Real

√a:Real : Real

⌈a:Real⌉ : Real

⌊a:Real⌋ : Real

a:Real + b:Real : Real

a:Real - b:Real : Real

a:Real   b:Real : Real

a:Real / b:Real : Real

a:Real = b:Real : Boolean

a:Real ≈ b:Real : Boolean

a:Real ≠ b:Real : Boolean

a:Real ≉ b:Real : Boolean
    ¬(a ≈ b)

a:Real < b:Real : Boolean

a:Real ≤ b:Real : Boolean

a:Real > b:Real : Boolean

a:Real ≥ b:Real : Boolean

-- TODO these should be inferred?

a:Real ≈ b:Integer : Boolean
    b':Real = b
    a ≈ b'

a:Real < b:Integer : Boolean
    b':Real = b
    a < b'

a:Real > b:Integer : Boolean
    b':Real = b
    a > b'

a:Real = b:Integer : Boolean
    b':Real = b
    (a = b')

a:Real ≠ b:Integer : Boolean
    b':Real = b
    a ≠ b'

a:Real + b:Integer : Real
    b':Real = b
    a + b'

a:Integer + b:Real : Real
    a':Real = a
    a' + b

a:Integer - b:Real : Real
    a':Real = a
    a' - b

a:Real - b:Integer : Real
    b':Real = b
    a - b'

a:Real / b:Integer : Real
    b':Real = b
    a / b'

a:Integer / b:Real : Real
    a':Real = a
    a' / b

a:Real b:Integer : Real
    b':Real = b
    ab'

a:Integer b:Real : Real
    a':Real = a
    a'b

⌊(a:Real, b:Real)⌋ : (Real, Real)
    (⌊a⌋, ⌊b⌋)

(a1:Real, b1:Real) - (a2:Real, b2:Real) : (Real, Real)
    (a1 - a2, b1 - b2)

(a1:Real, b1:Real) - b:Integer : (Real, Real)
    (a2:Real, b2:Real) = (b, b)
    (a1 - a2, b1 - b2)

a:Integer ≤ b:Real : Boolean
    a':Real = a
    a' ≤ b

-- Processes

PassThrough () : α >> α

Reverse () : α >> α

SortBy (f:Integer) : α >> α

DupZip (p1:(α >> β), p2:(α >> γ)) : α >> (β, γ)

DupCat (p1:(α >> β), p2:(α >> β)) : α >> β
