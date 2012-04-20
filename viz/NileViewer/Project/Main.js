//
//  Main.js
//  NileViewer
//
//  Created by Bret Victor on 4/29/12.
//


(function(){


//====================================================================================
//
//  domready
//

window.addEvent('domready', function () {

    var pipeline = NLDemoPipeline2();
    var inputStream = NLDemoStream2();
    
    NLPipelineRun(pipeline,inputStream);
    
    var container = $("myViewer");
    new NVPipelineView(container, pipeline, inputStream);
});



//====================================================================================
//
//  demo data
//

function NLDemoStream () {
    return [
        NLBezier(0,0, -1,1, 0,2),
        NLBezier(0,2,  1,3, 2,3),
        NLBezier(2,3,  3,3, 3,2),
        NLBezier(3,2,  2,0, 0,0),
    ].map(function (x) { return NLStreamItem(x); });
}

function NLDemoPipeline () {
    return [
        NLProcess("TransformBeziers"),
        NLProcess("SubdivideBeziers"),
        NLProcess("StrokeBezierPath"),
    ];
}


//====================================================================================
//
//  demo data
//

function NLDemoStream2 () {
    return [
        NLPoint(0,0, 0,2),
        NLPoint(0,2, 2,3),
        NLPoint(2,3, 3,2),
        NLPoint(3,2, 0,0),
        NLPoint(0,0, 0,2),
    ].map(function (x) { return NLStreamItem(x); });
}

function NLDemoPipeline2 () {
    return [
        NLProcess("MakePolygon"),
        NLProcess("RoundPolygon"),
        NLProcess("TransformBeziers"),
        NLProcess("SubdivideBeziers"),
        NLProcess("StrokeBezierPath"),
    ];
}


//====================================================================================

})();

