-- Types

type Boolean
type Integer
type Real

-- Operators

¬(a:Boolean) : Boolean

(a:Boolean ∨ b:Boolean) : Boolean

(a:Boolean ∧ b:Boolean) : Boolean

-(a:Real) : Real

√(a:Real) : Real

⌈(a:Real)⌉ : Real

⌊(a:Real)⌋ : Real

(a:Real + b:Real) : Real

(a:Real - b:Real) : Real

(a:Real   b:Real) : Real

(a:Real / b:Real) : Real

(a:Real = b:Real) : Boolean

(a:Real ≠ b:Real) : Boolean

(a:Real < b:Real) : Boolean

(a:Real ≤ b:Real) : Boolean

(a:Real > b:Real) : Boolean

(a:Real ≥ b:Real) : Boolean

-- Processes

Passthrough () : α >> α

Reverse () : α >> α

SortBy (f:Integer) : α >> α

DupZip (p1:α >> β, p2:α >> γ) : α >> (β, γ)

DupCat (p1:α >> β, p2:α >> β) : α >> β
