-- Types

type Boolean
type Number

-- Boolean operations

¬a:Boolean : Boolean

a:Boolean ∨ b:Boolean : Boolean

a:Boolean ∧ b:Boolean : Boolean

-- Number operations

-a:Number : Number

√a:Number : Number

⌊a:Number⌋ : Number

⌈a:Number⌉ : Number

a:Number = b:Number : Boolean

a:Number ≠ b:Number : Boolean

a:Number < b:Number : Boolean

a:Number ≤ b:Number : Boolean

a:Number > b:Number : Boolean

a:Number ≥ b:Number : Boolean

a:Number + b:Number : Number

a:Number - b:Number : Number

a:Number   b:Number : Number

a:Number / b:Number : Number

-- Processes

PassThrough () : α >> α

Reverse () : α >> α

SortBy (f:Number) : α >> α

DupZip (p1:(α >> β), p2:(α >> γ)) : α >> (β, γ)

DupCat (p1:(α >> β), p2:(α >> β)) : α >> β
