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
    
    initialize: function (container) {
        container.empty();
        this.element = (new Element("div", { "class":"NVPipeline" })).inject(container);
        this.processViews = [];
    },

    setPipeline: function (pipeline, inputStream) {
        this.pipeline = pipeline;
        this.initialInputStream = inputStream;

        while (this.processViews.length < pipeline.length + 1) { this.processViews.push(new NVProcessView(this)); }
        while (this.processViews.length > pipeline.length + 1) { this.processViews.pop().destroy(); }

        NLPipelineRun(this.pipeline, this.initialInputStream);

        this.processViews[0].setInitialInputStream(inputStream);

        Array.each(pipeline, function (process, i) {
            this.processViews[i+1].setProcess(process);
        }, this);
    },
    
    replaceStreamItemWithItem: function (oldItem, newItem) {
        var index = this.initialInputStream.indexOf(oldItem);
        if (index < 0) { return; }
        
        var newStream = NLStreamClone(this.initialInputStream);
        newStream[index] = newItem;
        
        var newPipeline = NLPipelineClone(this.pipeline);

        this.setPipeline(newPipeline, newStream);
    },


    //--------------------------------------------------------------------------------
    //
    //  process views
    
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
    
    initialize: function (parentView) {
        this.pipelineView = parentView;
        this.parentView = parentView;
        
        var container = parentView.element;
        var templateElement = $("templates").getElement(".NVProcess");
        
        this.element = templateElement.clone();
        this.element.inject(container);

        this.canvasView = new NVInteractiveCanvasView(this);
        this.codeView = new NVCodeView(this);

        this.inputStreamView = new NVStreamView(this, true);
        this.outputStreamView = new NVStreamView(this, false);
    },
    
    setProcess: function (process) {
        this.process = process;

        this.element.getElement(".NVProcessName").set("text", NLProcessGetName(process));
        this.element.getElement(".NVProcessParameters").set("text", "( )");
        
        this.canvasView.setStream(process.outputStream);
        this.codeView.setCode(NLProcessGetCode(process));
        
        this.inputStreamView.setStream(process.inputStream);
        this.outputStreamView.setStream(process.outputStream);
    },
    
    destroy: function () {
        this.element.destroy();
    },
    
    setInitialInputStream: function (stream) {
        this.element.getElement(".NVProcessName").set("text", "initial input");
        this.element.getElement(".NVProcessParameters").set("text", "");
        
        this.canvasView.setStream(stream);
        this.codeView.setCode("");
        
        this.inputStreamView.setStream([]);
        this.outputStreamView.setStream(stream, true);
        
        this.canvasView.setEditable(true);
    },
    
    getPreviousView: function () {
        var index = this.parentView.processViews.indexOf(this);
        if (index < 1) { return null; }
        return this.parentView.processViews[index - 1];
    },
});


//====================================================================================
//
//  NVStreamView
//

var NVStreamView = new Class({
    
    initialize: function (parentView, isInput) {
        this.pipelineView = parentView.pipelineView;
        this.parentView = parentView;
        
        this.isInput = isInput;
        this.element = parentView.element.getElement(".NVProcess" + (this.isInput ? "Input" : "Output"));

        this.iconViews = [];
    },
    
    setStream: function (stream, isSolo) {
        this.stream = stream;

        this.element.setStyle("display", stream.length ? "block" : "none");
        if (stream.length == 0) { return; }
        
        var prefix = isSolo ? "" : this.isInput ? "Processed " : "Output "
        var suffix = NLObjectGetTypeName(stream[0].object) + (stream.length == 1 ? "" : "s");
        var caption = prefix + stream.length + " " + suffix;
        this.element.getElement(".NVProcessIconsCaption").set("text", caption);

        var iconWidth = this.getIconWidth();
        
        while (this.iconViews.length < stream.length) { this.iconViews.push(new NVIconView(this)); }
        while (this.iconViews.length > stream.length) { this.iconViews.pop().destroy(); }

        Array.each(stream, function (streamItem, i) {
            var iconView = this.iconViews[i];
            iconView.setStreamItem(streamItem, iconWidth);
            if (this.isInput) { streamItem.inputIconView = iconView; }
            else { streamItem.outputIconView = iconView; }
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
    
    initialize: function (parentView) {
        this.pipelineView = parentView.pipelineView;
        this.processView = parentView.parentView;
        this.parentView = parentView;

        var container = parentView.element.getElement(".NVProcessIcons");
        
        this.element = (new Element("span", { "class":"NVProcessIcon" })).inject(container);
        this.innerElement = (new Element("span", { "class":"NVProcessIconInner" })).inject(this.element);

        this.element.addEvent("mouseenter", this.mouseEnter.bind(this));
        this.element.addEvent("mouseleave", this.mouseLeave.bind(this));
    },
    
    setStreamItem: function (streamItem, width) {
        width = width || 16;
        
        this.streamItem = streamItem;
        this.width = width;
        this.height = width;

        this.element.setStyle("width", this.width);
        this.element.setStyle("height", this.height);

        var innerHeight = Math.max(4, Math.ceil(this.height * Math.pow(0.7, streamItem.recursionDepth)));
        this.innerElement.setStyle("width", this.width);
        this.innerElement.setStyle("height", innerHeight);
        this.innerElement.setStyle("marginTop", this.height - innerHeight);
        
        this.setHighlight(false);
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
    
    destroy: function () {
        this.element.destroy();
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
        this.element = parentView.element.getElement(".NVProcessCode");

        this.lineViews = [];
        this.code = "";
    },
    
    setCode: function (code) {
        if (code == this.code) { return; }
        this.code = code;
        
        var lines = code.split("\n");

        while (this.lineViews.length < lines.length) { this.lineViews.push(new NVCodeLineView(this)); }
        while (this.lineViews.length > lines.length) { this.lineViews.pop().destroy(); }
    
        Array.each(lines, function (line, i) {
            this.lineViews[i].setLine(line);
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
    
    initialize: function (parentView) {
        this.parentView = parentView;
        this.element = (new Element("div", { "class":"NVProcessCodeLine" })).inject(parentView.element);
    },
    
    destroy: function () {
        this.element.destroy();
    },
    
    setLine: function (line) {
        this.line = line;
        this.element.set("text", line);
        this.setHighlighted(false);
    },
    
    setHighlighted: function (highlighted) {
        if (this.isHighlighted === highlighted) { return; }
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
    
    initialize: function (parentView) {
        this.pipelineView = parentView.pipelineView;
        this.parentView = parentView;
        
        this.element = parentView.element.getElement(".NVProcessCanvas");
        this.canvas = this.element.getElement("canvas");
        this.width = parseFloat(this.canvas.getAttribute("width"));
        this.height = parseFloat(this.canvas.getAttribute("height"));
    },
    
    setStream: function (stream) {
        this.stream = stream;

        this.selectedItems = [];
        this.hotItem = null;

        this.points = this.getPoints();
        this.beziers = this.getBeziers();
        
        if (!this.isEditing) {
            var metrics = this.getMetricsWithPoints(this.points);
            this.translation = this.getTranslationWithMetrics(metrics);
            this.scale = this.getScaleWithMetrics(metrics);
        }
        
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
    
    initialize: function (parentView) {
        this.parent(parentView);
        
        Array.each(this.element.getChildren(), function (element) {
            element.setStyle("pointerEvents", "none");  // needed so hover events don't bubble up from children
        });
        
        this.mouseDragBound = this.mouseDrag.bind(this);
        this.mouseUpBound = this.mouseUp.bind(this);
        this.mouseMoveBound = this.mouseMove.bind(this);
        
        this.element.addEvent("mousedown", this.mouseDown.bind(this));
        this.element.addEvent("mouseenter", this.mouseEnter.bind(this));
        this.element.addEvent("mouseleave", this.mouseLeave.bind(this));
        this.element.addEvent("dblclick", this.doubleClick.bind(this));
        this.element.setStyle("cursor", "all-scroll");
        
        this.helpElement = this.element.getElement(".NVProcessCanvasHelp");
        this.helpOpacity = 0;

        this.selectedPoint = null;
    },
    
    setStream: function (stream) {
        this.setSelectedPoint(null);
        this.parent(stream);
    },

    setEditable: function (editable) {
        this.isEditable = editable;
    },
    

    //--------------------------------------------------------------------------------
    //
    //  drag
    
    mouseDown: function (event) {
        event.stop();
        this.element.getDocument().addEvent("mousemove", this.mouseDragBound);
        this.element.getDocument().addEvent("mouseup", this.mouseUpBound);

        this.lastMousePosition = this.getMousePositionWithEvent(event);
        if (this.resetTimer) { clearInterval(this.resetTimer); this.resetTimer = null; }
        
        this.animateHelpOpacity(1,100);
        
        if (this.isEditable && this.selectedPoint) {
            this.isEditing = true;
        }
    },

    mouseDrag: function (event) {
        event.stop();

        var mousePosition = this.getMousePositionWithEvent(event);
        var dx = mousePosition.x - this.lastMousePosition.x;
        var dy = mousePosition.y - this.lastMousePosition.y;
        this.lastMousePosition = mousePosition;
        
        if (this.isEditing) {
            if (this.selectedPoint && this.selectedPoint.item) {
                var pointIndex = this.points.indexOf(this.selectedPoint);

                var draggedObject = NLObjectTranslate(this.selectedPoint.item.object, dx / this.scale, -dy / this.scale);
                this.pipelineView.replaceStreamItemWithItem(this.selectedPoint.item, NLStreamItem(draggedObject));
                
                this.setSelectedPoint(this.points[pointIndex]);
                return;
            }
        }
        else if (event.shift) {
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
        this.element.getDocument().removeEvent("mousemove", this.mouseDragBound);
        this.element.getDocument().removeEvent("mouseup", this.mouseUpBound);
        this.animateHelpOpacity(0,1000);
        
        if (this.isEditing) {
            this.isEditing = false;
            this.animateResetTransform();
        }
    },
    
    getMousePositionWithEvent: function (event) {
        var elementPosition = this.element.getPosition();
        return { x:event.page.x - elementPosition.x, y:event.page.y - elementPosition.y };
    },

    doubleClick: function (event) {
        event.stop();
        this.animateResetTransform();
    },


    //--------------------------------------------------------------------------------
    //
    //  hover

    mouseEnter: function (event) {
        this.element.getDocument().addEvent("mousemove", this.mouseMoveBound);
    },

    mouseMove: function (event) {
        if (this.isEditing) { return; }
        var elementPosition = this.element.getPosition();
        var canvasPoint = { x:event.page.x - elementPosition.x, y:event.page.y - elementPosition.y };
        var point = this.getPointNearCanvasPoint(canvasPoint, 10);
        this.setSelectedPoint(point);
    },

    mouseLeave: function (event) {
        if (this.isEditing) { return; }
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
        
        if (this.isEditable) {
            this.element.setStyle("cursor", this.selectedPoint ? "crosshair" : "all-scroll");
        }
    },
    

    //--------------------------------------------------------------------------------
    //
    //  animate

    animateResetTransform: function () {
        var metrics = this.getMetricsWithPoints(this.points);
        var targetTranslation = this.getTranslationWithMetrics(metrics);
        var targetScale = this.getScaleWithMetrics(metrics);
        
        this.animateSetTranslationAndScale(targetTranslation, targetScale);
    },

    animateSetTranslationAndScale: function (targetTranslation, targetScale) {
        var progress = 0;
        var speed = 0.3;
        
        if (this.resetTimer) { clearTimeout(this.resetTimer); }
        
        var timer = this.resetTimer = setInterval( (function () {
            progress += 1/30;
            if (progress > 0.8) { speed = 1; clearTimeout(timer); }

            this.translation.x += speed * (targetTranslation.x - this.translation.x);
            this.translation.y += speed * (targetTranslation.y - this.translation.y);
            this.scale += speed * (targetScale - this.scale);
            this.render();
        }).bind(this), 1000/30);
    },

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

