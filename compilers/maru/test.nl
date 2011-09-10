type Color    = (a:Real, r:Real, g:Real, b:Real)
type Point    = (x:Real, y:Real)
type Vector   = (x:Real, y:Real)
type Matrix   = (a:Real, b:Real, c:Real, d:Real, e:Real, f:Real)
type Bezier   = (A:Point, B:Point, B:Point)
type EdgeSpan = (x:Real, y:Real, c:Real, l:Real)

-- a comment
type Texture    = Point >> Color -- another comment
type Compositor = (Color, Color) >> Color

(a:Real) \min (b:Real) : Real
--    { a  if a < b,
--      b  otherwise }

\sgn(a:Real) : Real
--    { -1  if a < 0,
--       0  if a = 0,
--       1  otherwise }

(a:Real)\sqrd : Real
--    aa

\bar(a:Real)\bar : Real
--    { -a  if a < 0,
--       a  otherwise }
