function prefix_operator_lookup(operator, type)
{
    var r = table[operator + type];
    if (!r) {
        var onReal = table[operator + "Real"]);
        if (onReal)
            r = table[operator + type] = implementUnaryPairwiseOperator (type, onReal);
    }
    return r;
}

function binary_operator_lookup(operator, ltype, rtype)
{
    var r = table[ltype + operator + rtype];
    if (!r && ltype == rtype) {
        var onReal = table["Real" + operator + "Real"];
        if (onReal) 
            r = table[ltype + operator + rtype] = implementBinaryPairwiseOperator (type, onReal);
    }
    return r;
}

Explicit conversions

    Real   :: Record -- succeeds if record dimension == 1, just duplicate value
    Tuple  :: Record -- succeeds if tuple has exact shape of record

    Real   :: Tuple  -- make syntactically impossible
    Tuple  :: Real   -- make syntactically impossible
    Record :: *      -- always fails

Tuples are only for constructing Records, or composing/pattern matching.
