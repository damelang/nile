space         = char:x ?[x ~~ Character cr and: [x asciiValue <= 32]] -> [x]
spaces        = [0]:n (space [n + 1]:n)* -> [n]
nl            = exactly(Character cr)
eol           = spaces nl
indent :dummy = spaces:n ?[n >= level]
indented :r   =
    [level]:oldLevel &spaces:level ?[level > oldLevel]
        ( apply(r):ans [oldLevel]:level -> [ans]
        | [oldLevel]:level ?[false]
        )
initialize
    super initialize.
    level := 0.
