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

        this.canvasView = new NVCanvasView(this, process.outputStream);
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
        
        this.canvasView = new NVCanvasView(this, stream);
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

        this.element.addEvent("mouseenter", this.mouseEntered.bind(this));
        this.element.addEvent("mouseleave", this.mouseExited.bind(this));
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

    mouseEntered: function () {
        this.pipelineView.setHighlightedWithStreamItem(true, this.streamItem, this.parentView.isInput);
    },
    
    mouseExited: function () {
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
        this.render();
    },
    
    render: function () {
        var ctx = this.canvas.getContext("2d");
        ctx.clearRect(0,0,this.width,this.height);

        if (this.stream.length == 0) { return; }
        
        var points = this.getPoints();
        var beziers = this.getBeziers();
        if (points.length == 0) { return; }
        
        var metrics = this.getMetricsWithPoints(points);
        var scale = this.getScaleWithMetrics(metrics);
        
        ctx.save();
        
        ctx.translate(this.width/2, this.height/2);
        ctx.scale(scale, -scale);
        ctx.translate(-metrics.midPoint.x, -metrics.midPoint.y);
        
        if (beziers.length) {
            this.fillBeziers(beziers);
        }
        
        this.fillPoints(points, scale);
        
        if (this.selectedItems.length) {
            this.highlightItems(this.selectedItems, scale);
        }
        if (this.hotItem) {
            this.highlightItems( [ this.hotItem ], scale, "hot");
        }
        
        ctx.restore();
    },
    

    getPoints: function () {
        var points = [];
        Array.each(this.stream, function (item) {
            var obj = item.object;
            points.append(NLObjectExtractPoints(obj));
        }, this);
        return points;
    },

    getBeziers: function () {
        var beziers = [];
        Array.each(this.stream, function (item) {
            var obj = item.object;
            beziers.append(NLObjectExtractBeziers(obj));
        }, this);
        return beziers;
    },
    
    getMetricsWithPoints: function (points) {
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
    
        var scale = 0.8 * Math.min(widthScale, heightScale);
        return scale;
    },
    
    
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
    
    fillPoints: function (points, scale) {
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
    
    highlightItems: function (items, scale, isHot) {
        var ctx = this.canvas.getContext("2d");

        ctx.fillStyle = isHot ? "#ff0000" : "#000000";
        ctx.strokeStyle = isHot ? "#ff0000" : "#000000";
        ctx.font = 'normal 9px "Helvetica Neue"';

        var shouldAnnotate = (items.length == 1);
        
        Array.each(items, function (item) {
            var bezier = NLObjectExtractBeziers(item.object)[0];
            if (bezier) {
                ctx.beginPath();
                ctx.lineWidth = 0.6 / scale;
                ctx.moveTo(bezier.A.x, bezier.A.y);
                ctx.quadraticCurveTo(bezier.B.x,bezier.B.y,bezier.C.x,bezier.C.y);
                ctx.stroke();
                
                Object.each(bezier, function (point, name) {
                    ctx.save();
                    ctx.translate(point.x,point.y);
                    ctx.scale(1/scale, -1/scale);
        
                    ctx.beginPath();
                    ctx.arc(0, 0, 3, 0, Math.PI*2);
                    ctx.fill();
                    
                    if (shouldAnnotate) {
                        ctx.fillText(name, 6, 3);
                    }
                    
                    ctx.restore();
                }, this);
            }
            else {
                var points = NLObjectExtractPoints(item.object);
                Array.each(points, function (point) {
                    ctx.save();
                    ctx.translate(point.x,point.y);
                    ctx.scale(1/scale, -1/scale);
        
                    ctx.beginPath();
                    ctx.arc(0, 0, 3, 0, Math.PI*2);
                    ctx.fill();

                    ctx.restore();
                }, this);
            }
        }, this);
    },
    
});


//====================================================================================

})();

