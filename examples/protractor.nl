type Point  = (x:Real, y:Real)
type Vector = (x:Real, y:Real)
type Path   = (a1:Point, a2:Point, a3:Point, a4:Point, a5:Point, a6:Point,
               a7:Point, a8:Point, a9:Point, a10:Point, a11:Point, a12:Point,
               a13:Point, a14:Point, a15:Point, a16:Point)

(u:Path) \optimalCosineDistance (v:Path) : Real
    a = u.a1.x v.a1.x + u.a1.y v.a1.y + u.a2.x v.a2.x + u.a2.y v.a2.y +
        u.a3.x v.a3.x + u.a3.y v.a3.y + u.a4.x v.a4.x + u.a4.y v.a4.y +
        u.a5.x v.a5.x + u.a5.y v.a5.y + u.a6.x v.a6.x + u.a6.y v.a6.y +
        u.a7.x v.a7.x + u.a7.y v.a7.y + u.a8.x v.a8.x + u.a8.y v.a8.y +
        u.a9.x v.a9.x + u.a9.y v.a9.y + u.a10.x v.a10.x + u.a10.y v.a10.y +
        u.a11.x v.a11.x + u.a11.y v.a11.y + u.a12.x v.a12.x + u.a12.y v.a12.y +
        u.a13.x v.a13.x + u.a13.y v.a13.y + u.a14.x v.a14.x + u.a14.y v.a14.y +
        u.a15.x v.a15.x + u.a15.y v.a15.y + u.a16.x v.a16.x + u.a16.y v.a16.y
    b = u.a1.x v.a1.y - u.a1.y v.a1.x + u.a1.x v.a1.y - u.a1.y v.a1.x +
        u.a2.x v.a2.y - u.a2.y v.a2.x + u.a3.x v.a3.y - u.a3.y v.a3.x +
        u.a4.x v.a4.y - u.a4.y v.a4.x + u.a5.x v.a5.y - u.a5.y v.a5.x +
        u.a6.x v.a6.y - u.a6.y v.a6.x + u.a7.x v.a7.y - u.a7.y v.a7.x +
        u.a8.x v.a8.y - u.a8.y v.a8.x + u.a9.x v.a9.y - u.a9.y v.a9.x +
        u.a10.x v.a10.y - u.a10.y v.a10.x + u.a11.x v.a11.y - u.a11.y v.a11.x +
        u.a12.x v.a12.y - u.a12.y v.a12.x + u.a13.x v.a13.y - u.a13.y v.a13.x +
        u.a14.x v.a14.y - u.a14.y v.a14.x + u.a15.x v.a15.y - u.a15.y v.a15.x
    angle = \atan(b / a)
    \acos(a\cos(angle) + b\sin(angle))

(u:Vector) ∙ (v:Vector) : Real
   ((x1, y1), (x2, y2)) = (u, v)
   x1x2 + y1y2

‖(u:Vector)‖ : Real
    √(u ∙ u)

PathLength : Point >> Real
    d = 0
    p:Point = 0
    first = 1
    ∀ p'
        first' = 0
        d' = { d,              if first
               d + ‖(p' - p)‖, otherwise }
    >> d

Resample (I:Real) : Point >> Point
    D = 0
    p:Point = 0
    first = 1
    ∀ r
        d = ‖(r - p)‖
        q = p + ((I - D) / d)(r - p)
        p' = { r, if first \or D + d < I
               q, otherwise              }
        D' = { 0,     if first \or D + d ≥ I
               D + d, otherwise              }
        first' = 0
        if first = 1
            >> r
        else if D + d ≥ I
                >> q
                << r
    >> p

Centralize : Point >> Point
    ...

Vectorize (oSensitive: Real) : Point >> Point
    p:Point = 0
    sum = 0
    first = 1
    ∀ p'
        first' = 0
        if first = 1
            indicativeAngle = \atan(p'.y, p'.x)
            baseOrientation = PI / 4 ⌊((indicativeAngle + PI / 8) / (PI / 4))⌋
            delta = { baseOrientation - indicativeAngle, if oSensitive
                                       -indicativeAngle, otherwise     }
            sum' = 0
        else
            newX = p.x \cos(delta) - p.y \sin(delta)
            newY = p.y \cos(delta) + p.x \sin(delta)
            >> (newX, newY)

Vectorize2 : Point >> Real
    sum = 0
    ∀ p
        sum' = sum + p ∙ p
    >> sum

Vectorize3 (sum:Real) : Point >> Point
    magnitude = √sum
    ∀ p
        >> p / magnitude

Recognize (vector:Path) : (Path, Real) >> Real
    maxScore = 0
    match = -1
    ∀ (t, id)
        distance = vector ∙ t
        score = 1 / ((vector ∙ t) ? 0.00001)
        if score > maxScore
            match' = id
            maxScore' = score
    >> match
