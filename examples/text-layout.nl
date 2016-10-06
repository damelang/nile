type Glyph = (w:Number, s:Number)
type Word  = (w:Number, s:Number, n:Number)
type Point = (x:Number, y:Number)

MakeWords (w:Number) : Glyph >> Word
    W:Word = (0, 0, 0)
    ∀ G
        if G.s ≠ W.s ∨ W.s = 2 ∨ (W.w + G.w > w)
            W' = (G.w, G.s, 1)
            >> W
        else
            W' = (W.w + G.w, W.s, W.n + 1)
    >> W

InsertLineBreaks (w:Number) : Word >> Word
    o = 0
    ∀ W
        if W.s = 2
            o' = 0
            >> W
        else if (W.s = 1) ∨ (o + W.w ≤ w)
            o' = o + W.w
            >> W
        else
            o' = 0 + W.w
            >> (0, 2, 0)
            >> W

PlaceWords (b:Point, h:Number) : Word >> (Word, Point)
    x = b.x
    y = b.y
    ∀ W
        >> (W, (x, y))
        if W.s = 2
            x' = b.x
            y' = y + h
        else
            x' = x + W.w

RepeatPlacement () : (Word, Point) >> Point
    ∀ (W, P) 
        if W.n > 0
            >> P
            << ((W.w, W.s, W.n - 1), P)

PlaceGlyphs () : (Point, Glyph) >> Point
    x = 0
    y = 0
    o = 0
    ∀ ((x', y'), (w, _))
        if x = x' ∧ y = y'
            o' = o + w 
            >> (x' + o, y')
        else
            o' = 0 + w
            >> (x' + 0, y')

LayoutText (b:Point, w:Number, h:Number) : Glyph >> Point
    → DupZip (→ MakeWords (w) → InsertLineBreaks (w) → PlaceWords (b, h) → RepeatPlacement(), → PassThrough ()) → PlaceGlyphs()
