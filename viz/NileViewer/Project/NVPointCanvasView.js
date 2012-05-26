//
//  NVPointCanvasView.js
//  NileViewer
//
//  Created by Bret Victor on 5/23/12.
//


//====================================================================================
//
//  NVPointCanvasView
//

var NVPointCanvasView = new Class({
    
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

        this.points = this.extractFromStream(NLObjectExtractPoints);
        this.beziers = this.extractFromStream(NLObjectExtractBeziers);
        
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
    
    extractFromStream: function (extract) {
        var things = [];
        Array.each(this.stream, function (item) {
            var objectThings = extract(item.object);
            Array.each(objectThings, function (thing) {
                thing.item = item;
                things.push(thing);
            }, this);
        }, this);
        return things;
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
//  NVInteractivePointCanvasView
//

var NVInteractivePointCanvasView = new Class({

    Extends: NVPointCanvasView,
    
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
        this.helpElement.set("text","Drag points to change initial input.");
    },

    destroy: function () {
        this.element.removeEvents();
    },
    

    //--------------------------------------------------------------------------------
    //
    //  translate object
    
    translatePointInStream: function (point, dx, dy) {
        var oldStream = this.pipelineView.initialInputStream;
        var newStream = NLStream();
        
        for (var i = 0; i < oldStream.length; i++) {
            var object = oldStream[i].object;
            var translatedObject = NLObjectMovePoint(object, point.x, point.y, point.x + dx, point.y + dy);
            newStream.push(NLStreamItem(translatedObject));
        }
        
        this.pipelineView.setInitialInputStream(newStream);
    },
    
    subdivideItem: function (item) {
        var oldStream = this.pipelineView.initialInputStream;
        var newStream = NLStream();
        
        for (var i = 0; i < oldStream.length; i++) {
            var object = oldStream[i].object;
            if (item == oldStream[i]) {
                var objects = NLObjectSubdivide(object);
                Array.each(objects, function (o) { newStream.push(NLStreamItem(o)); });
            }
            else {
                newStream.push(NLStreamItem(object));
            }
        }
        
        this.pipelineView.setInitialInputStream(newStream);
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
        
        if (!this.isEditable) { this.animateHelpOpacity(1,100); }
        
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
                this.translatePointInStream(this.selectedPoint, dx / this.scale, -dy / this.scale);
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
        
        if (!this.isEditable) { this.animateHelpOpacity(0,1000); }
        
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

        if (this.isEditable && this.selectedPoint && this.selectedPoint.item && this.stream.length == this.beziers.length) {
            this.subdivideItem(this.selectedPoint.item);
        }
        else {
            this.animateResetTransform();
        }
    },


    //--------------------------------------------------------------------------------
    //
    //  hover

    mouseEnter: function (event) {
        this.element.getDocument().addEvent("mousemove", this.mouseMoveBound);
        if (this.isEditable) { this.animateHelpOpacity(1,100); }
    },

    mouseMove: function (event) {
        if (this.isEditing) { return; }
        var elementPosition = this.element.getPosition();
        var canvasPoint = { x:event.page.x - elementPosition.x, y:event.page.y - elementPosition.y };
        var point = this.getPointNearCanvasPoint(canvasPoint, 10);
        this.setSelectedPoint(point);
    },

    mouseLeave: function (event) {
        if (this.isEditable) { this.animateHelpOpacity(0,400); }
        if (this.isEditing) { return; }
        this.setSelectedPoint(null);
        this.element.getDocument().removeEvent("mousemove", this.mouseMoveBound);
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
        if (this.helpOpacity == targetOpacity) { return; }
        
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

