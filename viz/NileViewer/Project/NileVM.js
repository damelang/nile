//
//  NileVM.js
//  NileViewer
//
//  Created by Bret Victor on 4/29/12.
//


//====================================================================================
//
//  NLTypes
//

var NLTypes = {
    "Real": { name:"Real" },
    "Point": { name:"Point" },
    "Bezier": { name:"Bezier" },
};

function NLReal (v) {
    return {
        "_type": NLTypes.Real,
        "value": v,
    };
}

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


//====================================================================================
//
//  NLObject
//

function NLObjectGetTypeName (obj) {
    return obj._type.name;
}

function NLObjectExtractPoints (obj) {
    var points = [];
    extract(obj);
    return points;
    
    function extract (obj) {
        if (obj.x && obj.y && obj.x.value !== undefined && obj.y.value !== undefined) {
            points.push( NLPointUnbox(obj) );
        }
        else {
            Object.each(obj, function (obj) {
                if (obj._type) { extract (obj); }
            });
        }
    }
}

function NLObjectExtractBeziers (obj) {
    var beziers = [];
    extract(obj);
    return beziers;
    
    function extract (obj) {
        if (obj.A && obj.A.x && obj.A.y && obj.B && obj.B.x && obj.B.y && obj.C && obj.C.x && obj.C.y) {
            beziers.push( NLBezierUnbox(obj) );
        }
        else {
            Object.each(obj, function (obj) {
                if (obj._type) { extract (obj); }
            });
        }
    }
}


//====================================================================================
//
//  NLProcess
//

function NLProcess (name) {
    if (!NLTypes[name]) {
        NLTypes[name] = {
            "name": name,
            "code": (NLProcessCode[name] || ""),
        }
    }
    return {
        "_type": NLTypes[name],
        "producer": null,
        "consumer": null,
        "inputStream": null,
        "outputStream": null,
    };
}

function NLProcessGetName (process) {
    return process._type.name;
}

function NLProcessGetCode (process) {
    return process._type.code;
}

function NLProcessRun (process) {
    var name = NLProcessGetName(process);
    var func = NLProcessFunctions[name] || NLProcessFunctions["default"];
    func(process);
}


//====================================================================================
//
//  NLTrace
//

function NLTrace (process,iteration) {
    return {
        "process": process,
        "iteration": iteration,
        "consumedItem": null,
        "producedItems": [],
        "pushedItems": [],
        "lineIndexes": [],
    };
}

function NLTraceAddLineIndexes (trace, indexes) {
    for (var i = 0; i < indexes.length; i++) {
        trace.lineIndexes.push(indexes[i]);
    }
}


//====================================================================================
//
//  NLStream
//

function NLStream () {
    return [];
}

function NLStreamItem (obj,recursionDepth) {
    return {
        "object":obj,
        "producerTrace":null,
        "pusherTrace":null,
        "consumerTraces":[],
        "recursionDepth": (recursionDepth || 0)
    };
}

function NLStreamClone (stream) {
    var s = NLStream();
    for (var i = 0; i < stream.length; i++) {
        s.push(stream[i]);
    }
    return s;
}

function NLStreamReverse (stream) {
    var s = NLStream();
    for (var i = stream.length - 1; i >= 0; i--) {
        s.push(stream[i]);
    }
    return s;
}

function NLStreamForAll (stream, process, f) {
    for (var i = 0; i < stream.length; i++) {
        var item = stream[i];
        var trace = NLTrace(process, i);
        trace.consumedItem = item;
        item.consumerTraces.push(trace);
        
        f(item,trace);
    }
}

function NLStreamOutput (stream, item, trace) {
    item.producerTrace = trace;
    trace.producedItems.push(item);
    stream.push(item);
}

function NLStreamPush (stream, item, trace) {
    item.pusherTrace = trace;
    trace.pushedItems.push(item);
    stream.splice(trace.iteration + 1, 0, item);
}


//====================================================================================
//
//  NLPipeline
//

function NLPipelineRun (processes, inputStream) {
    var lastProcess = null;
    for (var i = 0; i < processes.length; i++) {
        var process = processes[i];
        process.producer = lastProcess;
        if (lastProcess) { lastProcess.consumer = process; }
    }
    
    var lastStream = inputStream;
    for (var i = 0; i < processes.length; i++) {
        var process = processes[i];
        process.inputStream = NLStreamClone(lastStream);
        process.outputStream = NLStream();
        NLProcessRun(process);
        lastStream = process.outputStream;
    }
}


//====================================================================================
//
//  demo process definitions
//

var NLProcessFunctions = {

    "default": function (process) {
        NLStreamForAll(process.inputStream, process, function (item, trace) {
            NLStreamOutput(process.outputStream, NLStreamItem(item.object), trace);
        });
    },

    "MakePolygon": function (process) {
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
    },

    "RoundPolygon": function (process) {
        NLStreamForAll(process.inputStream, process, function (item, trace) {
            var b = NLBezierUnbox(item.object);
            var normal = { x:-(b.C.y - b.A.y), y:b.C.x - b.A.x };
            b.B.x += normal.x * 0.25;
            b.B.y += normal.y * 0.25;
            
            NLStreamOutput(process.outputStream, NLStreamItem(NLBezier(b.A.x,b.A.y,b.B.x,b.B.y,b.C.x,b.C.y)), trace);
            NLTraceAddLineIndexes(trace, [2,3]);
        });
    },

    "SubdivideBeziers": function (process) {
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
    },
    
    "TransformBeziers": function (process) {
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
    },

    "StrokeBezierPath": function (process) {

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
    },
    
};
    

    
//====================================================================================
//
//  demo process code
//

var NLProcessCode = {

    "default": "",
    "MakePolygon": "MakePolygon () : Point >> Bezier\n    p:Point = 0\n    first = true\n    ∀ p'\n        first' = false\n        if ¬first\n            >> (p, p ~ p', p')\n",
    "RoundPolygon": "RoundPolygon () : Bezier >> Bezier\n    ∀ (A, B, C)\n        n = (A ⟂ C) / 4\n        >> (A, B + n, C)\n",
    "TransformBeziers": "TransformBeziers (M:Matrix) : Bezier >> Bezier\n    ∀ (A, B, C)\n        >> (MA, MB, MC)\n",
    "StrokeBezierPath": "StrokeBezierPath (w:Real, l:Real, c:Real) : Bezier >> Bezier\n    → SanitizeBezierPath () →\n      DupCat (→ StrokeOneSide (w, l, c),\n              → Reverse () → ReverseBeziers () → StrokeOneSide (w, l, c))",
    "SubdivideBeziers": "SubdivideBeziers () : Bezier >> Bezier\n    ∀ (A, B, C)\n        if ‖(A - C)‖ < 1\n            >> (A, B, C)\n        else\n            M = (A ~ B) ~ (B ~ C)\n            << (M, B ~ C, C) << (A, A ~ B, M)\n",
    "Rasterize": "Rasterize () : Bezier >> EdgeSpan\n    → DecomposeBeziers () → SortBy (1) → SortBy (2) → CombineEdgeSamples ()",
};
    


