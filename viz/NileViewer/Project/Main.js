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

    Array.each($$(".DemoLink"), function (link) {
        var name = link.getAttribute("data-name");
        link.addEvent("click", function () { showDemoWithName(name); return false; });
    });
    
    showDemoWithName("Beziers");
});


function showDemoWithName (name) {
    
    this.demos = this.demos || getDemos();
    this.pipelineView = this.pipelineView || new NVPipelineView($("myViewer"));
    
    var demo = this.demos[name];

    this.pipelineView.setPipeline(demo.pipeline, demo.stream);
}



//====================================================================================
//
//  demo data
//

function getDemos () {

    return {

        "Beziers": {
            stream: [
                NLBezier(0,0, -1,1, 0,2),
                NLBezier(0,2,  1,3, 2,3),
                NLBezier(2,3,  3,3, 3,2),
                NLBezier(3,2,  2,0, 0,0),
            ].map(function (x) { return NLStreamItem(x); }),
            
            pipeline: [
                NLProcess("TransformBeziers"),
                NLProcess("SubdivideBeziers"),
                NLProcess("StrokeBezierPath"),
            ],
        },
        
        "Points": {
            stream: [
                NLPoint(0,0, 0,2),
                NLPoint(0,2, 2,3),
                NLPoint(2,3, 3,2),
                NLPoint(3,2, 0,0),
                NLPoint(0,0, 0,2),
            ].map(function (x) { return NLStreamItem(x); }),
            
            pipeline: [
                NLProcess("MakePolygon"),
                NLProcess("RoundPolygon"),
                NLProcess("TransformBeziers"),
                NLProcess("SubdivideBeziers"),
                NLProcess("StrokeBezierPath"),
            ],
        },
    };
};


//====================================================================================

})();

