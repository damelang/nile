//
//  NileDummyContent.js
//  NileViewer
//
//  Created by Bret Victor on 5/25/12.
//


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
    "subprocessNames": [],

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
    "subprocessNames": [],

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
    "subprocessNames": [],

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
    "subprocessNames": [],

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
    "subprocessNames": [],

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
    "subprocessNames": [],

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
    "subprocessNames": [],

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
    "subprocessNames": [],

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
    "subprocessNames": [],

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


NLTypes["DecomposeBeziers"] = {
    "name": "DecomposeBeziers",
    "code": "DecomposeBeziers () : Bezier >> EdgeSpan\n    → DecomposeBeziers () → SortBy (1) → SortBy (2) → CombineEdgeSamples ()",
    "subprocessNames": [ "TransformBeziers", "CombineEdgeSamples" ],

    "func": function (process) {
    }
};



NLTypes["Rasterize"] = {
    "name": "Rasterize",
    "code": "Rasterize () : Bezier >> EdgeSpan\n    → DecomposeBeziers () → SortBy (1) → SortBy (2) → CombineEdgeSamples ()",
    "subprocessNames": [ "TransformBeziers", "DecomposeBeziers", "Sort", "CombineEdgeSamples" ],

    "func": function (process) {
    }
};

