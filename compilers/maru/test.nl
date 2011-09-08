type Color    = (a:Real, r:Real, g:Real, b:Real)
type Point    = (x:Real, y:Real)
type Vector   = (x:Real, y:Real)
type Matrix   = (a:Real, b:Real, c:Real, d:Real, e:Real, f:Real)
type Bezier   = (A:Point, B:Point, B:Point)
type EdgeSpan = (x:Real, y:Real, c:Real, l:Real)

-- a comment
type Texture    = Point >> Color -- another comment
type Compositor = (Color, Color) >> Color
