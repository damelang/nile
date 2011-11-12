Glyph <: (w:Real, s:Real)
Word  <: (w:Real, s:Real, n:Real)
Point <: (x:Real, y:Real)

MakeWords (w:Real) : Glyph >> Word
    W = (0, 0, 0):Word
    ∀ G
        if G.s ≠ W.s ∨ W.s = 2 ∨ (W.w + G.w > w)
            W' = (G.w, G.s, 1)
            >> W
        else
            W' = (W.w + G.w, W.s, W.n + 1)
    >> W

InsertLineBreaks (w:Real) : Word >> Word
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

PlaceWords (b:Point, h:Real) : Word >> (Word, Point)
    x = b.x
    y = b.y
    ∀ W
        >> (W, (x, y))
        x' = { b.x   if W.s = 2, x + W.w }
        y' = { y + h if W.s = 2,       y }

DuplicatePlacement : (Word, Point) >> Point
    ∀ (W, P) 
        if W.n > 0
            >> P
            << ((W.w, W.s, W.n - 1), P)

PlaceGlyphs : (Point, Glyph) >> Point
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

LayoutText (b:Point, w:Real, h:Real) : Glyph >> Point
    ⇒ DupZip (MakeWords (w) → InsertLineBreaks (w) → PlaceWords (b, h) → DuplicatePlacement, (→)) → PlaceGlyphs
