//
//  NileVM.js
//  NileViewer
//
//  Created by Bret Victor on 4/29/12.
//


var NLTypes = {};


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

function NLObjectUnbox (obj, template, allOrAny) {
    if (typeof(template) == "number") {
        return obj.value;
    }
    else if (typeof(template) == "object") {
        var matchesAll = true;
        var thing = { };
        for (var key in template) {
            if (!template.hasOwnProperty(key)) { continue; }
            
            var unboxedValue = obj[key] && NLObjectUnbox(obj[key], template[key], "all");
            if (unboxedValue !== undefined) {
                thing[key] = unboxedValue;
            }
            else {
                matchesAll = false;
            }
        }
        return (matchesAll || allOrAny == "any") ? thing : undefined;
    }
}

function NLObjectExtract (obj, template, allOrAny) {
    var things = [];
    extract(obj);
    return things;
    
    function extract (obj) {
        var thing = NLObjectUnbox(obj, template, allOrAny);
        if (thing !== undefined) {
            things.push(thing);
        }
        else {
            Object.each(obj, function (obj) {
                if (obj._type) { extract(obj); }
            });
        }
    }
}

function NLObjectGetDescription (obj, isSubObject) {
    if (obj._type.fields) {
        var fieldDescriptions = obj._type.fields.map(function (field) {
            return (isSubObject ? "" : (field + ": ")) + NLObjectGetDescription(obj[field], true);
        });
        var joined = fieldDescriptions.join(", ");
        return isSubObject ? ("(" + joined + ")") : joined;
    }
    else {
        var v = obj.value;
        var string = "0";

        if (Math.abs(v) >= 1e-4) {
            var precision = (-Math.floor(Math.log(Math.abs(v)) / Math.LN10) + 1).limit(0,3);
            string = sprintf("%." + precision + "f", v);
            string = string.replace(/(\.[1-9]*)0+$/, "$1");
            string = string.replace(/\.$/, "");
        }

        return "<b>" + string + "</b>";
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
        "auxInputStream": null,
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

function NLProcessGetAuxInputIndex (process) {
    return process._type.auxInputIndex;
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
        "consumedItems": [],
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
        trace.consumedItems.push(item);
        item.consumerTraces.push(trace);
        
        f(item,trace);
    }
}

function NLStreamZipWith (stream1, stream2, process, f) {
    var length = Math.min(stream1.length, stream2.length);
    for (var i = 0; i < length; i++) {
        var trace = NLTrace(process, i);

        var item1 = stream1[i];
        trace.consumedItems.push(item1);
        item1.consumerTraces.push(trace);

        var item2 = stream2[i];
        trace.consumedItems.push(item2);
        item2.consumerTraces.push(trace);
        
        f(item1,item2,trace);
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
        
        var auxInputIndex = NLProcessGetAuxInputIndex(process);
        if (auxInputIndex !== undefined) { process.auxInputStream = NLStreamClone(processes[auxInputIndex].outputStream); }
        
        NLProcessRun(process);
        lastStream = process.outputStream;
    }
}


