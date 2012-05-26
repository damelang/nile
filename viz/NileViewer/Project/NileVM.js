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

function NLRealUnbox (r) {
    return r.value;
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

function NLObjectClone (obj) {
    var clone = {};
    Object.each(obj, function (value, key) { clone[key] = value; });  // shallow
    return clone;
}

function NLObjectGetTypeName (obj) {
    return obj._type.name;
}

function NLObjectRebox(obj,unboxed) {
    var clone = NLObjectClone(obj);

    if (typeof(unboxed) === "number") {
        if (obj.value !== undefined) {
            clone.value = unboxed;
        }
    }
    else {
        Object.each(unboxed, function (value, key) {
            if (obj[key] !== undefined) {
                clone[key] = NLObjectRebox(obj[key], value);
            }
        });
    }
    return clone;
}

function NLObjectMovePoint (obj, x1,y1, x2,y2) {
    var clone = NLObjectClone(obj);
    move(clone);
    return clone;

    function move (obj) {
        if (obj.x && obj.y && obj.x.value === x1 && obj.y.value === y1) {
            obj.x.value = x2;
            obj.y.value = y2;
        }
        else {
            Object.each(obj, function (obj) {
                if (obj._type) { move(obj); }
            });
        }
    }
}

function NLObjectSubdivide (obj) {
    var bezier = NLBezierUnbox(obj);
    if (bezier.A.x === undefined) { return obj; }

    var AB = midPoint(bezier.A, bezier.B);
    var BC = midPoint(bezier.B, bezier.C);
    var ABBC = midPoint(AB, BC);

    var left = NLObjectRebox(obj, { A:bezier.A, B:AB, C:ABBC });
    var right = NLObjectRebox(obj, { A:ABBC, B:BC, C:bezier.C });
    
    return [ left, right ];
    
    function midPoint(p,q) {
        return { x:0.5*(p.x + q.x), y:0.5*(p.y + q.y) };
    }
}


//====================================================================================
//
//  NLObjectExtract
//

function NLObjectExtractReals (obj) {
    return NLObjectExtract(obj, NLRealUnbox, function (obj) {
        return (obj.value !== undefined);
    });
}

function NLObjectExtractPoints (obj) {
    return NLObjectExtract(obj, NLPointUnbox, function (obj) {
        return (obj.x && obj.y && obj.x.value !== undefined && obj.y.value !== undefined);
    });
}

function NLObjectExtractBeziers (obj) {
    return NLObjectExtract(obj, NLBezierUnbox, function (obj) {
        return (obj.A && obj.A.x && obj.A.y && obj.B && obj.B.x && obj.B.y && obj.C && obj.C.x && obj.C.y);
    });
}

function NLObjectExtract (obj, unbox, matchesType) {
    var things = [];
    extract(obj);
    return things;
    
    function extract (obj) {
        if (matchesType(obj)) {
            things.push( unbox(obj) );
        }
        else {
            Object.each(obj, function (obj) {
                if (obj._type) { extract(obj); }
            });
        }
    }
}


//====================================================================================
//
//  NLProcess
//

function NLProcess (name) {
    var type = NLTypeForProcessName(name);
    return {
        "_type": type,
        "subpipeline": (type.subprocessNames || []).map(NLProcess),
        "inputStream": null,
        "outputStream": null,
    };
}

function NLProcessClone (process) {
    var name = NLProcessGetName(process);
    return NLProcess(name);
}

function NLProcessGetName (process) {
    return process._type.name;
}

function NLProcessGetCode (process) {
    return process._type.code;
}

function NLProcessRun (process) {
    var subpipeline = process.subpipeline;
    if (subpipeline.length) {
        NLPipelineRun(subpipeline, process.inputStream);
        process.outputStream = NLStreamClone(subpipeline[subpipeline.length - 1].outputStream);
    }
    else {
        var func = process._type.func || NLTypes["default"].func;
        func(process);
    }
}

function NLTypeForProcessName (name) {
    if (!NLTypes[name]) {
        NLTypes[name] = {};
        Object.each(NLTypes["default"], function (value, key) { NLTypes[name][key] = value; });
        NLTypes[name].name = name;
    }
    return NLTypes[name];
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

function NLStreamClone (stream) {  // shallow, same items
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

function NLPipelineClone (pipeline) {
    return pipeline.map(NLProcessClone);
}

function NLPipelineRun (processes, inputStream) {
    var lastStream = inputStream;
    for (var i = 0; i < processes.length; i++) {
        var process = processes[i];
        process.inputStream = NLStreamClone(lastStream);
        process.outputStream = NLStream();
        NLProcessRun(process);
        lastStream = process.outputStream;
    }
}


