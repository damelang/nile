//
//  NileFakeGezira.js
//  NileViewer
//
//  Created by Bret Victor on 5/25/12.
//


//====================================================================================
//
//  data types
//

NLTypes["Real"] = { name:"Real" };

function NLReal (v) {
    return {
        "_type": NLTypes.Real,
        "value": v,
    };
}

function NLRealUnbox (r) {
    return r.value;
}


NLTypes["Point"] = { name:"Point", fields:["x","y"] };

function NLPoint (x,y) {
    return {
        "_type": NLTypes.Point,
        "x": NLReal(x),
        "y": NLReal(y),
    };
}

function NLPointUnbox (p) {
    return { x:p.x.value, y:p.y.value };
}


NLTypes["Bezier"] = { name:"Bezier", fields:["A","B","C"]  };

function NLBezier (x1,y1,x2,y2,x3,y3) {
    return {
        "_type": NLTypes.Bezier,
        "A": NLPoint(x1,y1),
        "B": NLPoint(x2,y2),
        "C": NLPoint(x3,y3),
    };
}

function NLBezierUnbox (b) {
    return { A:NLPointUnbox(b.A), B:NLPointUnbox(b.B), C:NLPointUnbox(b.C) };
}


NLTypes["EdgeSample"] = { "name":"EdgeSample", fields:["x","y","area","height"] };

function NLEdgeSample (x,y,area,height) {
    return {
        "_type": NLTypes.EdgeSample,
        "x": NLReal(x),
        "y": NLReal(y),
        "area": NLReal(area),
        "height": NLReal(height),
    };
}

function NLEdgeSampleUnbox (s) {
    return { x:s.x.value, y:s.y.value, area:s.area.value, height:s.height.value };
}


NLTypes["SpanCoverage"] = { "name":"SpanCoverage", fields:["x","y","coverage","length"] };

function NLSpanCoverage (x,y,coverage,length) {
    return {
        "_type": NLTypes.SpanCoverage,
        "x": NLReal(x),
        "y": NLReal(y),
        "coverage": NLReal(coverage),
        "length": NLReal(length),
    };
}

function NLSpanCoverageUnbox (s) {
    return { x:s.x.value, y:s.y.value, coverage:s.coverage.value, length:s.length.value };
}


NLTypes["PointCoverage"] = { "name":"PointCoverage", fields:["x","y","coverage"] };

function NLPointCoverage (x,y,coverage) {
    return {
        "_type": NLTypes.PointCoverage,
        "x": NLReal(x),
        "y": NLReal(y),
        "coverage": NLReal(coverage),
    };
}

function NLPointCoverageUnbox (s) {
    return { x:s.x.value, y:s.y.value, coverage:s.coverage.value };
}


NLTypes["Color"] = { "name":"Color", fields:["r","g","b","a"] };

function NLColor (r,g,b,a) {
    return {
        "_type": NLTypes.Color,
        "r": NLReal(r),
        "g": NLReal(g),
        "b": NLReal(b),
        "a": NLReal(a),
    };
}

function NLColorUnbox (s) {
    return { r:s.r.value, g:s.g.value, b:s.b.value, a:s.a.value };
}


NLTypes["Pixel"] = { "name":"Pixel", fields:["P","color"] };

function NLPixel (x,y, r,g,b,a) {
    return {
        "_type": NLTypes.Pixel,
        "P": NLPoint(x,y),
        "color": NLColor(r,g,b,a),
    };
}

function NLPixelUnbox (s) {
    return { P:NLPointUnbox(s.P), color:NLColorUnbox(s.color) };
}



//====================================================================================
//
//  demo process definitions
//


NLTypes["default"] = {
    "name": "default",
    "code": "",
    "subprocessNames": [],

    "func": function (process) {
        NLStreamForAll(process.inputStream, process, function (item, trace) {
            NLStreamOutput(process.outputStream, NLStreamItem(item.object), trace);
        });
    }
};

NLTypes["AddToReals"] = {
    "name": "AddToReals",
    "code": "",

    "func": function (process) {
        NLStreamForAll(process.inputStream, process, function (item, trace) {
            var v = NLRealUnbox(item.object);
            v += 7;
            NLStreamOutput(process.outputStream, NLStreamItem(NLReal(v)), trace);
        });
    }
};

NLTypes["Duplicate"] = {
    "name": "Duplicate",
    "code": "",

    "func": function (process) {
        for (var i = 0; i < 4; i++) {
            NLStreamForAll(process.inputStream, process, function (item, trace) {
                NLStreamOutput(process.outputStream, NLStreamItem(item.object), trace);
            });
        }
    }
};

NLTypes["RealsToPoints"] = {
    "name": "RealsToPoints",
    "code": "",

    "func": function (process) {
        var i = 0;
        NLStreamForAll(process.inputStream, process, function (item, trace) {
            var v = NLRealUnbox(item.object);
            NLStreamOutput(process.outputStream, NLStreamItem(NLPoint(i,v)), trace);
            i++;
        });
    }
};

NLTypes["MakePolygon"] = {
    "name": "MakePolygon",
    "code": "MakePolygon () : Point >> Bezier\n    p:Point = 0\n    first = true\n    ∀ p'\n        first' = false\n        if ¬first\n            >> (p, p ~ p', p')\n",

    "func": function (process) {
        var p0 = null;
        NLStreamForAll(process.inputStream, process, function (item, trace) {
            var p = NLPointUnbox(item.object);
            if (p0) {
                var pm = { x:0.5*(p.x + p0.x), y:0.5*(p.y + p0.y) };
                NLStreamOutput(process.outputStream, NLStreamItem(NLBezier(p0.x,p0.y,pm.x,pm.y,p.x,p.y)), trace);
                NLTraceAddLineIndexes(trace, [6]);
            }
            p0 = p;
            NLTraceAddLineIndexes(trace, [4,5]);
        });
    }
};

NLTypes["RoundPolygon"] = {
    "name": "RoundPolygon",
    "code": "RoundPolygon () : Bezier >> Bezier\n    ∀ (A, B, C)\n        n = (A ⟂ C) / 4\n        >> (A, B + n, C)\n",

    "func": function (process) {
        NLStreamForAll(process.inputStream, process, function (item, trace) {
            var b = NLBezierUnbox(item.object);
            var normal = { x:-(b.C.y - b.A.y), y:b.C.x - b.A.x };
            b.B.x += normal.x * 0.25;
            b.B.y += normal.y * 0.25;
            
            NLStreamOutput(process.outputStream, NLStreamItem(NLBezier(b.A.x,b.A.y,b.B.x,b.B.y,b.C.x,b.C.y)), trace);
            NLTraceAddLineIndexes(trace, [2,3]);
        });
    }
};

NLTypes["SubdivideBeziers"] = {
    "name": "SubdivideBeziers",
    "code": "SubdivideBeziers () : Bezier >> Bezier\n    ∀ (A, B, C)\n        if ‖(A - C)‖ < 1\n            >> (A, B, C)\n        else\n            M = (A ~ B) ~ (B ~ C)\n            << (M, B ~ C, C) << (A, A ~ B, M)\n",

    "func": function (process) {
        NLStreamForAll(process.inputStream, process, function (item, trace) {
            var b = NLBezierUnbox(item.object);
            
            var norm = Math.abs( (b.A.x - b.C.x) * (b.A.x - b.C.x) + (b.A.y - b.C.y) * (b.A.y - b.C.y) );
            if (norm < 1.2) {
                NLStreamOutput(process.outputStream, NLStreamItem(item.object), trace);
                NLTraceAddLineIndexes(trace, [2,3]);
            }
            else {
                var AB = midPoint(b.A,b.B);
                var BC = midPoint(b.B,b.C);
                var ABBC = midPoint(AB,BC);
                NLStreamPush(process.inputStream, NLStreamItem(NLBezier(ABBC.x,ABBC.y,BC.x,BC.y,b.C.x,b.C.y), item.recursionDepth + 1), trace);
                NLStreamPush(process.inputStream, NLStreamItem(NLBezier(b.A.x,b.A.y,AB.x,AB.y,ABBC.x,ABBC.y), item.recursionDepth + 1), trace);
                NLTraceAddLineIndexes(trace, [2,5,6]);
            }
        });

        function midPoint(p,q) {
            return { x:0.5*(p.x + q.x), y:0.5*(p.y + q.y) };
        }
    }
};

NLTypes["TransformBeziers"] = {
    "name": "TransformBeziers",
    "code": "TransformBeziers (M:Matrix) : Bezier >> Bezier\n    ∀ (A, B, C)\n        >> (MA, MB, MC)\n",

    "func": function (process) {
        var angle = Math.PI * 0.25;
        var m = { a:Math.cos(angle), b:-Math.sin(angle), c:Math.sin(angle), d:Math.cos(angle) };

        NLStreamForAll(process.inputStream, process, function (item, trace) {
            var b = NLBezierUnbox(item.object);
            var A = transformPoint(b.A, m);
            var B = transformPoint(b.B, m);
            var C = transformPoint(b.C, m);
            var item = NLStreamItem(NLBezier(A.x,A.y,B.x,B.y,C.x,C.y));
            NLStreamOutput(process.outputStream, NLStreamItem(NLBezier(A.x,A.y,B.x,B.y,C.x,C.y)), trace);
            NLTraceAddLineIndexes(trace, [2]);
        });
        
        function transformPoint(p,m) {
            return { x: m.a * p.x + m.c * p.y, y: m.b * p.x + m.d * p.y };
        }
    }
};

NLTypes["StrokeBezierPath"] = {
    "name": "StrokeBezierPath",
    "code": "StrokeBezierPath (w:Real, l:Real, c:Real) : Bezier >> Bezier\n    → SanitizeBezierPath () →\n      DupCat (→ StrokeOneSide (w, l, c),\n              → Reverse () → ReverseBeziers () → StrokeOneSide (w, l, c))",

    "func": function (process) {
        var points = [];
        var beziers = [];
        
        Array.each(process.inputStream, function (item) {
            var bezier = NLBezierUnbox(item.object);
            beziers.push(bezier);
            points.push(bezier.A, bezier.B, bezier.C);
        });
        if (points.length == 0) { return; }
        
        var minPoint = { x:points[0].x, y:points[0].y };
        var maxPoint = { x:points[0].x, y:points[0].y };
        
        Array.each(points, function (point) {
            minPoint.x = Math.min(minPoint.x, point.x);
            minPoint.y = Math.min(minPoint.y, point.y);
            maxPoint.x = Math.max(maxPoint.x, point.x);
            maxPoint.y = Math.max(maxPoint.y, point.y);
        });
        
        var midPoint = { x:0.5*(maxPoint.x + minPoint.x), y:0.5*(maxPoint.y + minPoint.y) };

        function lerp (a,b,t) { return a + (b - a) * t; }

        function transformPoint(p) {
            return { x: lerp(p.x, midPoint.x, 0.3), y: lerp(p.y, midPoint.y, 0.3) };
        }

        NLStreamForAll(process.inputStream, process, function (item, trace) {
            NLStreamOutput(process.outputStream, NLStreamItem(item.object), trace);
        });

        NLStreamForAll(NLStreamReverse(process.inputStream), process, function (item, trace) {
            var b = NLBezierUnbox(item.object);
            var A = transformPoint(b.C);
            var B = transformPoint(b.B);
            var C = transformPoint(b.A);
            NLStreamOutput(process.outputStream, NLStreamItem(NLBezier(A.x,A.y,B.x,B.y,C.x,C.y)), trace);
        });
    }
};


NLTypes["Stroke"] = {
    "name": "Stroke",
    "code": "Stroke (w:Real, l:Real, c:Real) : Bezier >> Bezier\n    → SanitizeBezierPath () →\n      DupCat (→ StrokeOneSide (w, l, c),\n              → Reverse () → ReverseBeziers () → StrokeOneSide (w, l, c))",

    "func": function (process) {
        var points = [];
        var beziers = [];
        
        Array.each(process.inputStream, function (item) {
            var bezier = NLBezierUnbox(item.object);
            beziers.push(bezier);
            points.push(bezier.A, bezier.B, bezier.C);
        });
        if (points.length == 0) { return; }
        
        var minPoint = { x:points[0].x, y:points[0].y };
        var maxPoint = { x:points[0].x, y:points[0].y };
        
        Array.each(points, function (point) {
            minPoint.x = Math.min(minPoint.x, point.x);
            minPoint.y = Math.min(minPoint.y, point.y);
            maxPoint.x = Math.max(maxPoint.x, point.x);
            maxPoint.y = Math.max(maxPoint.y, point.y);
        });
        
        var midPoint = { x:0.5*(maxPoint.x + minPoint.x), y:0.5*(maxPoint.y + minPoint.y) };

        function lerp (a,b,t) { return a + (b - a) * t; }

        function transformPoint(p) {
            return { x: lerp(p.x, midPoint.x, 0.5), y: lerp(p.y, midPoint.y, 0.5) };
        }

        NLStreamForAll(process.inputStream, process, function (item, trace) {
            NLStreamOutput(process.outputStream, NLStreamItem(item.object), trace);
        });

        NLStreamForAll(NLStreamReverse(process.inputStream), process, function (item, trace) {
            var b = NLBezierUnbox(item.object);
            var A = transformPoint(b.C);
            var B = transformPoint(b.B);
            var C = transformPoint(b.A);
            NLStreamOutput(process.outputStream, NLStreamItem(NLBezier(A.x,A.y,B.x,B.y,C.x,C.y)), trace);
        });
    }
};



//------------------------------------------------------------------------------------
//
//  rasterize

NLTypes["Rasterize"] = {
    "name": "Rasterize",
    "code": "Rasterize () : Bezier >> EdgeSpan\n    → DecomposeBeziers () → SortBy (1) → SortBy (2) → CombineEdgeSamples ()",
    "subprocessNames": [ "DecomposeBeziers", "Sort", "CombineEdgeSamples" ],
};


NLTypes["DecomposeBeziers"] = {
    "name": "DecomposeBeziers",
    "code": "DecomposeBeziers () : Bezier >> EdgeSample\n    ϵ = 0.1\n    ∀ (A, B, C)\n        inside = (⌊ A ⌋ = ⌊ C ⌋ ∨ ⌈ A ⌉ = ⌈ C ⌉)\n        if inside.x ∧ inside.y\n            P = ⌊A⌋ ◁ ⌊C⌋\n            (x, y) = P\n            (w, _) = P + 1 - (A ~ C)\n            (_, h) = C - A\n            >> (x + 0.5, y + 0.5, wh, h)\n        else\n            M            = (A ~ B) ~ (B ~ C)\n            ( min,  max) = (⌊M⌋, ⌈M⌉)\n            (Δmin, Δmax) = (M - min, M - max)\n            N = { min, if |Δmin| < ϵ\n                  max, if |Δmax| < ϵ\n                    M,     otherwise }\n            << (N, B ~ C, C) << (A, A ~ B, N)",

    "func": function (process) {
        var ep = 0.1;

        NLStreamForAll(process.inputStream, process, function (item, trace) {
            var Z = NLBezierUnbox(item.object);
            var inside = { x:(Math.floor(Z.A.x) == Math.floor(Z.C.x) || Math.ceil(Z.A.x) == Math.ceil(Z.C.x)),
                           y:(Math.floor(Z.A.y) == Math.floor(Z.C.y) || Math.ceil(Z.A.y) == Math.ceil(Z.C.y)) };
            if (inside.x && inside.y) {
                var P = { x:Math.floor(Math.min(Z.A.x, Z.C.x)), y:Math.floor(Math.min(Z.A.y, Z.C.y)) };
                var w = P.x + 1 - midPoint(Z.A,Z.C).x;
                var h = Z.C.y - Z.A.y;
                var edgeSample = NLEdgeSample(P.x + 0.5,P.y + 0.5, w*h, h);
                NLStreamOutput(process.outputStream, NLStreamItem(edgeSample), trace);
                NLTraceAddLineIndexes(trace, [3,4,5,6,7,8,9]);
            }
            else {
                var M = midPoint(midPoint(Z.A,Z.B), midPoint(Z.B,Z.C));
                var min = { x:Math.floor(M.x), y:Math.floor(M.y) };
                var max = { x:Math.ceil(M.x), y:Math.ceil(M.y) };
                var dmin = { x:M.x - min.x, y:M.y - min.y };
                var dmax = { x:M.x - max.x, y:M.y - max.y };
                var N = {};
                N.x = (Math.abs(dmin.x) < ep) ? min.x : (Math.abs(dmax.x) < ep) ? max.x : M.x;
                N.y = (Math.abs(dmin.y) < ep) ? min.y : (Math.abs(dmax.y) < ep) ? max.y : M.y;

                var AB = midPoint(Z.A,Z.B);
                var BC = midPoint(Z.B,Z.C);
                NLStreamPush(process.inputStream, NLStreamItem(NLBezier(N.x,N.y,BC.x,BC.y,Z.C.x,Z.C.y), item.recursionDepth + 1), trace);
                NLStreamPush(process.inputStream, NLStreamItem(NLBezier(Z.A.x,Z.A.y,AB.x,AB.y,N.x,N.y), item.recursionDepth + 1), trace);
                NLTraceAddLineIndexes(trace, [3,4,11,12,13,14,15,16,17]);
            }
        });

        function midPoint(p,q) {
            return { x:0.5*(p.x + q.x), y:0.5*(p.y + q.y) };
        }
    }
};

NLTypes["Sort"] = {
    "name": "Sort",
    "code": "",

    "func": function (process) {
        var itemsAndTraces = [];

        NLStreamForAll(process.inputStream, process, function (item, trace) {
            itemsAndTraces.push({ item:item, trace:trace });
        });
        
        itemsAndTraces.sort(function (a,b) {
            var pa = NLPointUnbox(a.item.object);
            var pb = NLPointUnbox(b.item.object);
            return (pa.y - pb.y) || (pa.x - pb.x);
        });
        
        Array.each(itemsAndTraces, function (a) {
            NLStreamOutput(process.outputStream, NLStreamItem(a.item.object), a.trace);
        });
    }
};

NLTypes["CombineEdgeSamples"] = {
    "name": "CombineEdgeSamples",
    "code": "CombineEdgeSamples () : EdgeSample >> SpanCoverage\n    (x, y, A, H) = (0, 0, 0, 0)\n    ∀ (x', y', a, h)\n        if y' = y\n            if x' = x\n                (A', H') = (A + a, H + h)\n            else\n                (A', H') = (H + a, H + h)\n                >> (x,     y, |A| ◁ 1,          1)\n                >> (x + 1, y, |H| ◁ 1, x' - x - 1)\n        else\n            (A', H') = (a, h)\n            >> (x, y, |A| ◁ 1, 1)\n    >> (x, y, |A| ◁ 1, 1)",

    "func": function (process) {
        var x = 0, y = 0, A = 0, H = 0;
        var lastTrace = null;
        NLStreamForAll(process.inputStream, process, function (item, trace) {
            var edgeSample = NLEdgeSampleUnbox(item.object);
            var newX = edgeSample.x, newY = edgeSample.y, a = edgeSample.area, h = edgeSample.height;
            var newA = A, newH = H;
            NLTraceAddLineIndexes(trace, [3]);
            if (newY == y) {
                NLTraceAddLineIndexes(trace, [4]);
                if (newX == x) {
                    newA = A + a;
                    newH = H + h;
                    NLTraceAddLineIndexes(trace, [5]);
                }
                else {
                    newA = H + a;
                    newH = H + h;
                    NLStreamOutput(process.outputStream, NLStreamItem(NLSpanCoverage(x,  y,Math.min(Math.abs(A),1), 1)), trace);
                    NLStreamOutput(process.outputStream, NLStreamItem(NLSpanCoverage(x+1,y,Math.min(Math.abs(H),1), newX - x - 1)), trace);
                    NLTraceAddLineIndexes(trace, [7,8,9]);
                }
            }
            else {
                newA = a;
                newH = h;
                NLStreamOutput(process.outputStream, NLStreamItem(NLSpanCoverage(x,y,Math.min(Math.abs(A),1), 1)), trace);
                NLTraceAddLineIndexes(trace, [11,12]);
            }

            x = newX; y = newY; A = newA; H = newH;
            lastTrace = trace;
        });
        NLStreamOutput(process.outputStream, NLStreamItem(NLSpanCoverage(x,y,Math.min(Math.abs(A),1), 1)), lastTrace);
        NLTraceAddLineIndexes(lastTrace, [13]);
    }
};



//------------------------------------------------------------------------------------
//
//  texture

NLTypes["Texture"] = {
    "name": "Texture",
    "code": "Texture (A:ColorStop, B:ColorStop) : EdgeSpan >> (Color, PointCoverage)\n    → ExpandSpans () → DupZip (→ ProjectLinearGradient (A.P, B.P) -> PadGradient () -> GradientSpan (A.C, B.C),\n                               → PassThrough ())",
    "subprocessNames": [ "ExpandSpans", "ProjectLinearGradient", "PadGradient", "GradientSpan", "ZipPixels" ],
};

NLTypes["ExpandSpans"] = {
    "name": "ExpandSpans",
    "code": "ExpandSpans () : SpanCoverage >> PointCoverage\n    ∀ (x, y, c, l)\n        if c > 0 ∧ l > 0\n            >> (x, y, c)\n            << (x + 1, y, c, l - 1)",

    "func": function (process) {
        NLStreamForAll(process.inputStream, process, function (item, trace) {
            var span = NLSpanCoverageUnbox(item.object);
            NLTraceAddLineIndexes(trace, [2]);
            if (span.coverage > 0 && span.length > 0) {
                NLStreamOutput(process.outputStream, NLStreamItem(NLPointCoverage(span.x,span.y,span.coverage)), trace);
                NLStreamPush(process.inputStream, NLStreamItem(NLSpanCoverage(span.x + 1, span.y, span.coverage, span.length - 1), item.recursionDepth + 1), trace);
                NLTraceAddLineIndexes(trace, [3,4]);
            }
        });
    }
};

NLTypes["ProjectLinearGradient"] = {
    "name": "ProjectLinearGradient",
    "code": "ProjectLinearGradient (A:Point, B:Point) : PointCoverage >> Real\n    v   = B - A\n    Δs  = v / (v ∙ v)\n    s00 = A ∙ Δs\n    ∀ (P,_)\n        >> P ∙ Δs - s00",

    "func": function (process) {
        var A = {x:1, y:4}, B = {x:4, y:2};
        var v = { x:B.x - A.x, y:B.y - A.y };
        var vn = v.x * v.x + v.y * v.y;
        var delS = { x:v.x / vn, y:v.y / vn };
        var s00 = A.x * delS.x + A.y * delS.y;
        NLStreamForAll(process.inputStream, process, function (item, trace) {
            var pointCoverage = NLPointCoverageUnbox(item.object);
            var value = (pointCoverage.x * delS.x + pointCoverage.y * delS.y) - s00;
            NLStreamOutput(process.outputStream, NLStreamItem(NLReal(value)), trace);
            NLTraceAddLineIndexes(trace, [5]);
        });
    }
};

NLTypes["PadGradient"] = {
    "name": "PadGradient",
    "code": "PadGradient () : Point >> Point\n    ∀ s\n        >> 0 ▷ s ◁ 1",

    "func": function (process) {
        NLStreamForAll(process.inputStream, process, function (item, trace) {
            var s = NLRealUnbox(item.object);
            var value = Math.max(0, Math.min(1, s));
            NLStreamOutput(process.outputStream, NLStreamItem(NLReal(value)), trace);
            NLTraceAddLineIndexes(trace, [2]);
        });
    }
};

NLTypes["GradientSpan"] = {
    "name": "GradientSpan",
    "code": "GradientSpan (A:Color, B:Color) : Real >> Color\n    ∀ s\n        >> sA + (1 - s)B",

    "func": function (process) {
        var A = {r:0, g:1, b:1, a:1}, B = {r:0, g:0, b:0, a:1};
        NLStreamForAll(process.inputStream, process, function (item, trace) {
            var s = NLRealUnbox(item.object);
            var C = { r:lerp(A.r, B.r, s), g:lerp(A.g, B.g, s), b:lerp(A.b, B.b, s), a:lerp(A.a, B.a, s) };
            NLStreamOutput(process.outputStream, NLStreamItem(NLColor(C.r,C.g,C.b,C.a)), trace);
            NLTraceAddLineIndexes(trace, [2]);
        });

        function lerp (a,b,t) { return a + (b - a) * t; }
    }
};

NLTypes["ZipPixels"] = {
    "name": "ZipPixels",
    "code": "ZipPixels () : (PointCoverage, Color) >> Pixel\n    ∀ ((x, y, coverage), (r, g, b, a))\n        >> ((x, y), (r, g, b, a * coverage))",
    "auxInputIndex": 0,

    "func": function (process) {
        NLStreamZipWith(process.inputStream, process.auxInputStream, process, function (item1, item2, trace) {
            var color = NLColorUnbox(item1.object);
            var pointCoverage = NLPointCoverageUnbox(item2.object);
            var pixel = NLPixel(pointCoverage.x, pointCoverage.y, color.r, color.g, color.b, color.a * pointCoverage.coverage);
            NLStreamOutput(process.outputStream, NLStreamItem(pixel), trace);
            NLTraceAddLineIndexes(trace, [2]);
        });
    }
};



//------------------------------------------------------------------------------------
//
//  test

NLTypes["Test"] = {
    "name": "Test",
    "code": "",
    "subprocessNames": [ "Test1", "Test1", "Test1" ],
};

NLTypes["Test1"] = {
    "name": "Test1",
    "code": "",
    "subprocessNames": [ "Test2", "Test2" ],
};

NLTypes["Test2"] = {
    "name": "Test2",
    "code": "",
    "subprocessNames": [ "Test3", "Test3" ],
};

NLTypes["Test3"] = {
    "name": "Test3",
    "code": "",
    "subprocessNames": [],

    "func": function (process) {
        NLStreamForAll(process.inputStream, process, function (item, trace) {
            NLStreamOutput(process.outputStream, NLStreamItem(item.object), trace);
        });
    }
};


