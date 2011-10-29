{-
    TODO:
        new line chars
        very long words
        variable line height
-}

Glyph <: (w:Real, s:Real)
Word  <: (w:Real, s:Real, n:Real)
Point <: (x:Real, y:Real)

MakeWords : Glyph >> Word
    W = (0, 0, 0):Word
    ∀ G
        if G.s ≠ W.s
            W' = (G.w, G.s, 1)
            >> W
        else
            W' = (W.w + G.w, W.s, W.n + 1)
    >> W

PlaceWords (o:Point, w:Real, h:Real) : Word >> (Point, Real)
    x = o.x
    y = o.y
    ∀ W
        if (x + W.w < o.x + w) ∨ (W.s = 1)
            x' = x + W.w
            >> ((x, y), W.n)
        else
            x' = o.x + W.w
            y' = y + h
            >> ((o.x, y'), W.n)

DuplicatePlacement : (Point, Real) >> Point
    ∀ (P, n) 
        if n > 0
            >> P
            << (P, n - 1)

PlaceGlyphs : (Point, Glyph) >> Point
    x = 0
    y = 0
    o = 0
    ∀ (P, (w, _))
        if P.x = x ∧ P.y = y
            o' = o + w 
            >> (x + o, y)
        else
            x' = P.x
            y' = P.y
            o' = w
            >> (x', y')

LayoutText (o:Point, w:Real, h:Real) : Glyph >> Point
    ⇒ DupZip (MakeWords → PlaceWords (o, w, h) → DuplicatePlacement, (→)) → PlaceGlyphs
