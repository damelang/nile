//
//  NileViewer.js
//  NileViewer
//
//  Created by Bret Victor on 4/29/12.
//


(function(){


//====================================================================================
//
//  NVPipelineView
//

var NVPipelineView = this.NVPipelineView = new Class({
    
    initialize: function (container, pipeline, inputStream) {
        container.empty();
    
        this.element = new Element("div", { "class":"NVPipeline" });
        this.element.inject(container);
        
        this.pipeline = pipeline;
        this.inputStream = inputStream;
        
        this.processViews = [];
        this.processViews.push( new NVInitialInputView(this, inputStream) );
        
        Array.each(pipeline, function (process) {
            this.processViews.push( new NVProcessView(this, process) );
        }, this);
    },
    
    getProcessViewForProcess: function (process) {
        for (var i = 0; i < this.processViews.length; i++) {
            if (process == this.processViews[i].process) { return this.processViews[i]; }
        }
        return null;
    },
    
    getPreviousProcessView: function (processView) {
        var index = this.processViews.indexOf(processView);
        if (index <= 1) { return null; }
        return this.processViews[index - 1];
    },
    
    
    //--------------------------------------------------------------------------------
    //
    //  highlighting
    
    setHighlightedWithStreamItem: function (highlighted, streamItem, isInput) {
        this.clearCanvasSelectedItems();
        this.highlightStreamItemBackward(streamItem, highlighted, "hot");
        this.highlightStreamItemForward(streamItem, highlighted, "hot");
        if (highlighted) { this.addItemToCanvasSelectedItems(streamItem, "hot"); }
        
        this.renderAllCanvases();
        this.highlightCodeWithStreamItem(highlighted, streamItem, isInput);
    },
    
    clearCanvasSelectedItems: function () {
        Array.each(this.processViews, function (processView) {
            processView.canvasView.selectedItems = [];
            processView.canvasView.hotItem = null;
        }, this);
    },

    highlightStreamItemBackward: function (streamItem, isHighlighted, isHot) {
        var color = !isHighlighted ? false : isHot ? "hot" : true;
        if (streamItem.inputIconView) { streamItem.inputIconView.setHighlight(color); }
        if (streamItem.outputIconView) { streamItem.outputIconView.setHighlight(color); }

        if (streamItem.producerTrace) {
            var item = streamItem.producerTrace.consumedItem;
            if (item) {
                this.highlightStreamItemBackward(item, isHighlighted);
                if (isHighlighted) { this.addItemToCanvasSelectedItems(item); }
            }
        }
    }, 
    
    highlightStreamItemForward: function (streamItem, isHighlighted, isHot) {
        var color = !isHighlighted ? false : isHot ? "hot" : true;
        if (streamItem.inputIconView) { streamItem.inputIconView.setHighlight(color); }
        if (streamItem.outputIconView) { streamItem.outputIconView.setHighlight(color); }

        var items = [];

        Array.each(streamItem.consumerTraces, function (trace) {
            Array.each(trace.producedItems, function (item) { items.push(item); });
            Array.each(trace.pushedItems, function (item) { items.push(item); });
        }, this);
        
        Array.each(items, function (item) {
            this.highlightStreamItemForward(item, isHighlighted);
            if (isHighlighted) { this.addItemToCanvasSelectedItems(item); }
        }, this);
    },

    addItemToCanvasSelectedItems: function (item, isHot) {
        var canvasView = null;
        if (item.outputIconView) {
            canvasView = item.outputIconView.parentView.parentView.canvasView;
        }
        else if (item.inputIconView && isHot) {
            var previousProcessView = this.getPreviousProcessView(item.inputIconView.parentView.parentView);
            if (previousProcessView) { canvasView = previousProcessView.canvasView; }
        }
        if (!canvasView) { return; }
        
        if (isHot) { canvasView.hotItem = item; }
        else { canvasView.selectedItems.push(item); }
    },
    
    renderAllCanvases: function () {
        Array.each(this.processViews, function (processView) {
            processView.canvasView.render();
        }, this);
    },

    highlightCodeWithStreamItem: function (highlighted, streamItem, isInput) {
        var trace = isInput ? streamItem.consumerTraces[0] : streamItem.producerTrace;
        if (!trace) { return; }
        
        var processView = this.getProcessViewForProcess(trace.process);
        processView.codeView.setHighlightedLineIndexes( highlighted ? trace.lineIndexes : [] );
    },
    
});


//====================================================================================
//
//  NVProcessView
//

var NVProcessView = new Class({
    
    initialize: function (parentView, process) {
        this.pipelineView = parentView;
        this.parentView = parentView;
        this.process = process;
        
        var container = parentView.element;
        var templateElement = $("templates").getElement(".NVProcess");
        
        this.element = templateElement.clone();
        this.element.inject(container);
        
        if (!process) { return; }
        
        this.element.getElement(".NVProcessName").set("text", NLProcessGetName(process));
        this.element.getElement(".NVProcessParameters").set("text", "( )");

        this.canvasView = new NVInteractiveCanvasView(this, process.outputStream);
        this.codeView = new NVCodeView(this, process);
        
        this.inputStreamView = new NVStreamView(this, process.inputStream, "Input");
        this.outputStreamView = new NVStreamView(this, process.outputStream, "Output");
    },
    
    getPreviousView: function () {
        var index = this.parentView.processViews.indexOf(this);
        if (index < 1) { return null; }
        return this.parentView.processViews[index - 1];
    },
});


//====================================================================================
//
//  NVInitialInputView
//

var NVInitialInputView = new Class({

    Extends: NVProcessView,
    
    initialize: function (parentView, stream) {
        this.parent(parentView, null);
        
        this.element.getElement(".NVProcessName").set("text", "initial input");
        this.element.getElement(".NVProcessParameters").set("text", "");
        
        this.inputStreamView = new NVStreamView(this, [], "Input");
        this.outputStreamView = new NVStreamView(this, stream, "");
        
        this.canvasView = new NVInteractiveCanvasView(this, stream);
        this.codeView = new NVCodeView(this, null);
    }
});


//====================================================================================
//
//  NVStreamView
//

var NVStreamView = new Class({
    
    initialize: function (parentView, stream, name) {
        this.pipelineView = parentView.pipelineView;
        this.parentView = parentView;
        
        this.stream = stream;
        this.name = name;
        this.isInput = (name == "Input");
        
        this.element = parentView.element.getElement(".NVProcess" + (this.isInput ? "Input" : "Output"));

        this.element.setStyle("display", stream.length ? "block" : "none");
        if (stream.length == 0) { return; }
        
        var prefix = !name ? "" : this.isInput ? "Processed " : "Output "
        var suffix = NLObjectGetTypeName(stream[0].object) + (stream.length == 1 ? "" : "s");
        var caption = prefix + stream.length + " " + suffix;
        this.element.getElement(".NVProcessIconsCaption").set("text", caption);
        
        var iconWidth = this.getIconWidth();
        this.iconViews = [];
        
        Array.each(stream, function (streamItem) {
            var iconView = new NVIconView(this, streamItem, iconWidth);
            if (this.isInput) { streamItem.inputIconView = iconView; }
            else { streamItem.outputIconView = iconView; }
            this.iconViews.push(iconView);
        }, this);
    },
    
    getIconWidth: function () {
        var totalWidth = 200;
        var padding = 2;
        
        var widths = [16, 12, 8, 6, 4];
        for (var i = 0; i < widths.length; i++) {
            var rowCount = Math.ceil(this.stream.length * (widths[i] + padding) / totalWidth);
            var maxRows = Math.floor(46 / (widths[i] + padding));
            if (rowCount <= maxRows) { return widths[i]; }
        }
        
        return widths[widths.length - 1];
    },

});


//====================================================================================
//
//  NVIconView
//

var NVIconView = new Class({
    
    initialize: function (parentView, streamItem, width) {
        this.pipelineView = parentView.pipelineView;
        this.processView = parentView.parentView;
        this.parentView = parentView;

        this.streamItem = streamItem;
        this.width = width;
        this.height = width;
        
        var container = parentView.element.getElement(".NVProcessIcons");
        
        this.element = (new Element("span", { "class":"NVProcessIcon" })).inject(container);
        this.element.setStyle("width", this.width);
        this.element.setStyle("height", this.height);

        var innerHeight = Math.max(4, Math.ceil(this.height * Math.pow(0.7, streamItem.recursionDepth)));
        this.innerElement = (new Element("span", { "class":"NVProcessIconInner" })).inject(this.element);
        this.innerElement.setStyle("width", this.width);
        this.innerElement.setStyle("height", innerHeight);
        this.innerElement.setStyle("marginTop", this.height - innerHeight);

        this.element.addEvent("mouseenter", this.mouseEnter.bind(this));
        this.element.addEvent("mouseleave", this.mouseLeave.bind(this));
    },
    
    setHighlight: function (color) {
        if (color === "hot") {
            this.innerElement.addClass("NVProcessIconHotSelected");
        }
        else if (color) {
            this.innerElement.addClass("NVProcessIconSelected");
        }
        else {
            this.innerElement.removeClass("NVProcessIconHotSelected");
            this.innerElement.removeClass("NVProcessIconSelected");
        }
    },

    mouseEnter: function () {
        this.pipelineView.setHighlightedWithStreamItem(true, this.streamItem, this.parentView.isInput);
    },
    
    mouseLeave: function () {
        this.pipelineView.setHighlightedWithStreamItem(false, this.streamItem, this.parentView.isInput);
    },
    
});


//====================================================================================
//
//  NVCodeView
//

var NVCodeView = new Class({
    
    initialize: function (parentView, process) {
        this.pipelineView = parentView.pipelineView;
        this.parentView = parentView;
        this.process = process;
        
        this.element = parentView.element.getElement(".NVProcessCode");
        this.element.setStyle("display", process ? "block" : "none");
        if (!process) { return; }
        
        var code = NLProcessGetCode(process) || "";

        this.lineViews = [];
        Array.each(code.split("\n"), function (line) {
            var lineView = new NVCodeLineView(this, line);
            this.lineViews.push(lineView);
        }, this);
    },
    
    setHighlightedLineIndexes: function (indexes) {
        Array.each(this.lineViews, function (lineView, i) {
            lineView.setHighlighted( indexes.contains(i) );
        }, this);
    },

});


//====================================================================================
//
//  NVCodeLineView
//

var NVCodeLineView = new Class({
    
    initialize: function (parentView, line) {
        this.parentView = parentView;
        this.line = line;
        
        this.element = (new Element("div", { "class":"NVProcessCodeLine" })).inject(parentView.element);
        this.element.set("text", line);
        
        this.isHighlighted = false;
    },
    
    setHighlighted: function (highlighted) {
        if (this.isHighlighted == highlighted) { return; }
        this.isHighlighted = highlighted;
        
        if (highlighted) { this.element.addClass("NVProcessCodeLineHot"); }
        else { this.element.removeClass("NVProcessCodeLineHot"); }
    }

});


//====================================================================================
//
//  NVCanvasView
//

var NVCanvasView = new Class({
    
    initialize: function (parentView, stream) {
        this.pipelineView = parentView.pipelineView;
        this.parentView = parentView;
        this.stream = stream;
        
        this.element = parentView.element.getElement(".NVProcessCanvas");
        this.canvas = this.element.getElement("canvas");
        this.width = parseFloat(this.canvas.getAttribute("width"));
        this.height = parseFloat(this.canvas.getAttribute("height"));
        
        this.selectedItems = [];
        this.hotItem = null;

        this.points = this.getPoints();
        this.beziers = this.getBeziers();

        var metrics = this.getMetricsWithPoints(this.points);
        this.translation = this.getTranslationWithMetrics(metrics);
        this.scale = this.getScaleWithMetrics(metrics);
        
        this.render();
    },
    
    render: function () {
        var ctx = this.canvas.getContext("2d");
        ctx.clearRect(0,0,this.width,this.height);

        if (this.points.length == 0) { return; }
        
        ctx.save();
        
        ctx.translate(this.width/2, this.height/2);
        ctx.scale(this.scale, -this.scale);
        ctx.translate(this.translation.x, this.translation.y);
        
        this.drawGrid();
        
        if (this.beziers.length) {
            this.fillBeziers(this.beziers);
        }
        
        this.fillPoints(this.points);
        
        if (this.selectedItems.length) {
            this.highlightItems(this.selectedItems);
        }
        if (this.hotItem) {
            this.highlightItems( [ this.hotItem ], "hot");
        }
        
        ctx.restore();
    },
    

    //--------------------------------------------------------------------------------
    //
    //  points and metrics

    getPoints: function () {
        var points = [];
        Array.each(this.stream, function (item) {
            var objectPoints = NLObjectExtractPoints(item.object);
            Array.each(objectPoints, function (p) {
                p.item = item;
                points.push(p);
            }, this);
        }, this);
        return points;
    },

    getBeziers: function () {
        var beziers = [];
        Array.each(this.stream, function (item) {
            var objectBeziers = NLObjectExtractBeziers(item.object);
            Array.each(objectBeziers, function (b) {
                b.item = item;
                beziers.push(b);
            }, this);
        }, this);
        return beziers;
    },
    
    getMetricsWithPoints: function (points) {
        if (points.length == 0) { points = [ {x:0, y:0} ]; }
    
        var minPoint = { x:points[0].x, y:points[0].y };
        var maxPoint = { x:points[0].x, y:points[0].y };
        
        Array.each(points, function (point) {
            minPoint.x = Math.min(minPoint.x, point.x);
            minPoint.y = Math.min(minPoint.y, point.y);
            maxPoint.x = Math.max(maxPoint.x, point.x);
            maxPoint.y = Math.max(maxPoint.y, point.y);
        }, this);
        
        var midPoint = { x:0.5*(maxPoint.x + minPoint.x), y:0.5*(maxPoint.y + minPoint.y) };
        
        return {
            minPoint: minPoint,
            maxPoint: maxPoint,
            midPoint: midPoint,
        };
    },
    
    getScaleWithMetrics: function (metrics) {
        var pointsWidth = metrics.maxPoint.x - metrics.minPoint.x;
        var pointsHeight = metrics.maxPoint.y - metrics.minPoint.y;
        
        var widthScale = this.width / Math.max(0.01, pointsWidth);
        var heightScale = this.height / Math.max(0.01, pointsHeight);
    
        var scale = 0.75 * Math.min(widthScale, heightScale);
        return scale;
    },
    
    getTranslationWithMetrics: function (metrics) {
        return { x: -metrics.midPoint.x, y:-metrics.midPoint.y };
    },
    
    getPointNearCanvasPoint: function (canvasPoint, radius) {
       var p = { x:((canvasPoint.x - this.width/2)  /  this.scale) - this.translation.x,
                 y:((canvasPoint.y - this.height/2) / -this.scale) - this.translation.y };
       radius = radius / this.scale;
    
       var closestPoint = null;
       var closestDistance = 1e100;

       for (var i = 0; i < this.points.length; i++) {
           var point = this.points[i];
           var distance = Math.sqrt((point.x - p.x) * (point.x - p.x) + (point.y - p.y) * (point.y - p.y));
           if (distance < closestDistance) { closestDistance = distance; closestPoint = point; }
       }
       
       return (closestDistance <= radius) ? closestPoint : null;
    },
    
    
    //--------------------------------------------------------------------------------
    //
    //  drawing

    fillBeziers: function (beziers) {
        var ctx = this.canvas.getContext("2d");
        ctx.fillStyle = "rgba(0,0,0,0.06)";
        ctx.beginPath();

        var lastBezier = { C:{x:1e100,y:1e100} };
        Array.each(beziers, function (bezier) {
            if (bezier.A.x != lastBezier.C.x || bezier.A.y != lastBezier.C.y) {
                ctx.moveTo(bezier.A.x, bezier.A.y);
            }
            ctx.quadraticCurveTo(bezier.B.x,bezier.B.y,bezier.C.x,bezier.C.y);
            lastBezier = bezier;
        }, this);
        
        ctx.fill();
    },
    
    fillPoints: function (points) {
        var scale = this.scale;
        var ctx = this.canvas.getContext("2d");
        ctx.fillStyle = "#53b4ff";

        Array.each(points, function (point) {
            ctx.save();
            ctx.translate(point.x,point.y);
            ctx.scale(1/scale, -1/scale);
            
            ctx.beginPath();
            ctx.arc(0, 0, 2, 0, Math.PI*2);
            ctx.fill();
            ctx.restore();
        }, this);
    },
    
    highlightItems: function (items, isHot) {
        var scale = this.scale;
        var ctx = this.canvas.getContext("2d");

        ctx.fillStyle = isHot ? "#ff0000" : "#000000";
        ctx.strokeStyle = isHot ? "#ff0000" : "#000000";
        ctx.font = 'normal 9px "Helvetica Neue"';

        var shouldAnnotate = (items.length == 1);
        
        Array.each(items, function (item) {
            var bezier = NLObjectExtractBeziers(item.object)[0];
            if (bezier) {
                strokeBezier(bezier);
                Object.each(bezier, function (point, name) {
                    fillPoint(point, shouldAnnotate ? name : null);
                });
            }
            else {
                var points = NLObjectExtractPoints(item.object);
                Array.each(points, function (point) {
                    fillPoint(point);
                });
            }
        });
        
        function strokeBezier (bezier) {
            ctx.beginPath();
            ctx.lineWidth = 0.6 / scale;
            ctx.moveTo(bezier.A.x, bezier.A.y);
            ctx.quadraticCurveTo(bezier.B.x,bezier.B.y,bezier.C.x,bezier.C.y);
            ctx.stroke();
        }
        
        function fillPoint (point, label) {
            ctx.save();
            ctx.translate(point.x,point.y);
            ctx.scale(1/scale, -1/scale);

            ctx.beginPath();
            ctx.arc(0, 0, 3, 0, Math.PI*2);
            ctx.fill();

            if (label) { ctx.fillText(label, 6, 3); }

            ctx.restore();
        }
    },
    
    drawGrid: function () {
        var scale = this.scale;
        var ctx = this.canvas.getContext("2d");
        ctx.save();
        
        ctx.strokeStyle = "#fff";
        ctx.lineWidth = 1 / scale;

        var minX = -0.5 * this.width / scale - this.translation.x;
        var maxX =  0.5 * this.width / scale - this.translation.x;
        var minY = -0.5 * this.height / scale - this.translation.y;
        var maxY =  0.5 * this.height / scale - this.translation.y;
        
        var stepBase = 10;
        var k = Math.round(Math.log((maxX - minX) / 8) / Math.log(stepBase));
        var step = Math.pow(stepBase,k);
        
        for (var x = Math.floor(minX / step) * step; x < maxX; x += step) {
            var snappedX = (Math.floor(x * scale) + 0.5) / scale;
            ctx.beginPath();
            ctx.moveTo(snappedX, minY);
            ctx.lineTo(snappedX, maxY);
            ctx.stroke();
        }
        for (var y = Math.floor(minY / step) * step; y < maxY; y += step) {
            var snappedY = (Math.floor(y * scale) + 0.5) / scale;
            ctx.beginPath();
            ctx.moveTo(minX, snappedY);
            ctx.lineTo(maxX, snappedY);
            ctx.stroke();
        }
        
        ctx.restore();
    },
    
});


//====================================================================================
//
//  NVInteractiveCanvasView
//

var NVInteractiveCanvasView = new Class({

    Extends: NVCanvasView,
    
    initialize: function (parentView, stream) {
        this.parent(parentView, stream);
        
        Array.each(this.element.getChildren(), function (element) {
            element.setStyle("pointerEvents", "none");  // needed so hover events don't bubble up from children
        });
        
        this.mouseMoveBound = this.mouseMove.bind(this);
        this.mouseUpBound = this.mouseUp.bind(this);
        this.hoverMouseMoveBound = this.hoverMouseMove.bind(this);
        
        this.element.addEvent("mousedown", this.mouseDown.bind(this));
        this.element.addEvent("mouseenter", this.mouseEnter.bind(this));
        this.element.addEvent("mouseleave", this.mouseLeave.bind(this));
        this.element.addEvent("dblclick", this.doubleClick.bind(this));
        this.element.setStyle("cursor", "all-scroll");
        
        this.helpElement = this.element.getElement(".NVProcessCanvasHelp");
        this.helpOpacity = 0;

        this.selectedPoint = null;
    },


    //--------------------------------------------------------------------------------
    //
    //  drag
    
    mouseDown: function (event) {
        event.stop();
        this.element.getDocument().addEvent("mousemove", this.mouseMoveBound);
        this.element.getDocument().addEvent("mouseup", this.mouseUpBound);

        this.lastMousePoint = { x:event.page.x, y:event.page.y };
        if (this.resetTimer) { clearInterval(this.resetTimer); this.resetTimer = null; }
        
        this.animateHelpOpacity(1,100);
    },

    mouseMove: function (event) {
        event.stop();

        var dx = event.page.x - this.lastMousePoint.x;
        var dy = event.page.y - this.lastMousePoint.y;
        this.lastMousePoint = { x:event.page.x, y:event.page.y };
        
        if (event.shift) {
            this.scale *= Math.pow(1.01, dx - dy);
        }
        else {
            this.translation.x +=  dx / this.scale;
            this.translation.y += -dy / this.scale;
        }
        
        this.render();
    },

    mouseUp: function (event) {
        event.stop();
        this.element.getDocument().removeEvent("mousemove", this.mouseMoveBound);
        this.element.getDocument().removeEvent("mouseup", this.mouseUpBound);
        this.animateHelpOpacity(0,1000);
    },


    //--------------------------------------------------------------------------------
    //
    //  hover

    mouseEnter: function (event) {
        this.element.getDocument().addEvent("mousemove", this.hoverMouseMoveBound);
    },

    hoverMouseMove: function (event) {
        var elementPosition = this.element.getPosition();
        var canvasPoint = { x:event.page.x - elementPosition.x, y:event.page.y - elementPosition.y };
        var point = this.getPointNearCanvasPoint(canvasPoint, 10);
        this.setSelectedPoint(point);
    },

    mouseLeave: function (event) {
        this.setSelectedPoint(null);
        this.element.getDocument().removeEvent("mousemove", this.hoverMouseMoveBound);
    },
    
    setSelectedPoint: function (point) {
        if (this.selectedPoint && this.selectedPoint.item) {
            this.pipelineView.setHighlightedWithStreamItem(false, this.selectedPoint.item);
        }

        this.selectedPoint = point;
        if (this.selectedPoint && this.selectedPoint.item) {
            this.pipelineView.setHighlightedWithStreamItem(true, this.selectedPoint.item);
        }
    },
    

    //--------------------------------------------------------------------------------
    //
    //  double-click

    doubleClick: function (event) {
        event.stop();
        
        var metrics = this.getMetricsWithPoints(this.points);
        var targetTranslation = this.getTranslationWithMetrics(metrics);
        var targetScale = this.getScaleWithMetrics(metrics);
        
        var progress = 0;
        var speed = 0.3;
        
        var timer = this.resetTimer = setInterval( (function () {
            progress += 1/30;
            if (progress > 0.8) { speed = 1; clearTimeout(timer); }

            this.translation.x += speed * (targetTranslation.x - this.translation.x);
            this.translation.y += speed * (targetTranslation.y - this.translation.y);
            this.scale += speed * (targetScale - this.scale);
            this.render();
        }).bind(this), 1000/30);
    },
    

    //--------------------------------------------------------------------------------
    //
    //  help

    animateHelpOpacity: function (targetOpacity, duration) {
        if (this.helpTimer) { clearTimeout(this.helpTimer); }
        
        var initialOpacity = this.helpOpacity;
        var progress = 0;
        
        this.helpTimer = setInterval( (function () {
            progress = Math.min(1, progress + (1000/30) / duration);
            this.helpOpacity = initialOpacity + (targetOpacity - initialOpacity) * progress;
            
            var colorComponent = "" + Math.round(255 * (0.75 + 0.25 * (1.0 - this.helpOpacity)));
            var color = "rgba(" + colorComponent + "," + colorComponent + "," + colorComponent + ",1)";
            this.helpElement.setStyle("color", color);
            this.helpElement.setStyle("display", this.helpOpacity ? "block" : "none");
            
            if (progress == 1) {
                clearTimeout(this.helpTimer);
                this.helpTimer = null;
            }
        }).bind(this), 1000/30);
    },
    
});


//====================================================================================

})();

