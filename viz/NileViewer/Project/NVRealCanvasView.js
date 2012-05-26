//
//  NVRealCanvasView.js
//  NileViewer
//
//  Created by Bret Victor on 5/23/12.
//


//====================================================================================
//
//  NVRealCanvasView
//

var NVRealCanvasView = new Class({
    
    initialize: function (parentView) {
        this.pipelineView = parentView.pipelineView;
        this.parentView = parentView;
        
        this.element = parentView.element.getElement(".NVProcessCanvas");
        this.canvas = this.element.getElement("canvas");
        this.width = parseFloat(this.canvas.getAttribute("width"));
        this.height = parseFloat(this.canvas.getAttribute("height"));

        this.element.setStyle("cursor", "auto");
    },
    
    setStream: function (stream) {
        this.stream = stream;

        this.selectedItems = [];
        this.hotItem = null;
        
        if (!this.isEditing) {
            this.bounds = this.getBoundsForStream(stream);
        }
        this.render();
    },
    
    render: function () {
        var ctx = this.canvas.getContext("2d");
        ctx.clearRect(0,0,this.width,this.height);
        
        if (this.stream.length == 0) { return; }
        
        ctx.save();
        
        var padding = (this.stream.length > this.width/2) ? 0 : 1;
        var barWidth = Math.floor(this.width / this.stream.length) - padding;
        
        Array.each(this.stream, function (item, i) {
            var value = NLRealUnbox(item.object);
            var barHeight = this.height * (value - this.bounds.min) / (this.bounds.max - this.bounds.min);

            var isHighlighted = this.selectedItems.contains(item);
            var isHot = (this.hotItem === item);
            ctx.fillStyle = isHot ? "#ff0000" : isHighlighted ? "#000000" : "rgba(0,0,0,0.1)";

            ctx.fillRect(i * (barWidth + padding), this.height - barHeight, barWidth, barHeight);
        }, this);
        
        ctx.restore();
    },

    getItemNearCanvasPoint: function (canvasPoint) {
        if (this.stream.length == 0) { return null; }
        
        var i = Math.floor(canvasPoint.x / this.width * this.stream.length).limit(0, this.stream.length - 1);
        return this.stream[i];
    },
    
    getBoundsForStream: function (stream) {
        var bounds = { max:-1e99, min:1e99 };
        Array.each(stream, function (item) {
            var value = NLRealUnbox(item.object);
            bounds.max = Math.max(value, bounds.max);
            bounds.min = Math.min(value, bounds.min);
        }, this);
        
        if (bounds.max - bounds.min < 1e-3) { bounds.max = bounds.min + 1e-3; }
        return bounds;
    },

});


//====================================================================================
//
//  NVInteractiveRealCanvasView
//

var NVInteractiveRealCanvasView = new Class({

    Extends: NVRealCanvasView,

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
        this.element.setStyle("cursor", "auto");
        
        this.helpElement = this.element.getElement(".NVProcessCanvasHelp");
        this.helpOpacity = 0;

        this.selectedItem = null;
    },
    
    setStream: function (stream) {
        this.setSelectedItem(null);
        this.parent(stream);
    },

    setEditable: function (editable) {
        this.isEditable = editable;
        this.helpElement.set("text","Drag bars to change initial input.");
    },

    destroy: function () {
        this.element.removeEvents();
    },
    
    adjustItemInStream: function (item, delta) {
        var index = this.stream.indexOf(item);
        var oldStream = this.pipelineView.initialInputStream;
        var newStream = NLStream();
        
        for (var i = 0; i < oldStream.length; i++) {
            var object = oldStream[i].object;
            var adjustedObject = (i != index) ? object : NLReal(NLRealUnbox(object) + delta);
            newStream.push(NLStreamItem(adjustedObject));
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
        
        if (this.isEditable && this.selectedItem) {
            this.isEditing = true;
        }
    },

    mouseDrag: function (event) {
        event.stop();

        var mousePosition = this.getMousePositionWithEvent(event);
        var dx = mousePosition.x - this.lastMousePosition.x;
        var dy = mousePosition.y - this.lastMousePosition.y;
        this.lastMousePosition = mousePosition;
        
        if (this.isEditing && this.selectedItem) {
            var itemIndex = this.stream.indexOf(this.selectedItem);
            this.adjustItemInStream(this.selectedItem, -dy * (this.bounds.max - this.bounds.min) / this.height);
            this.setSelectedItem(this.stream[itemIndex]);
            return;
        }
        
        this.render();
    },

    mouseUp: function (event) {
        event.stop();
        this.element.getDocument().removeEvent("mousemove", this.mouseDragBound);
        this.element.getDocument().removeEvent("mouseup", this.mouseUpBound);
        
        if (this.isEditing) {
            this.isEditing = false;
            this.animateResetBounds();
        }
    },
    
    getMousePositionWithEvent: function (event) {
        var elementPosition = this.element.getPosition();
        return { x:event.page.x - elementPosition.x, y:event.page.y - elementPosition.y };
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
        var item = this.getItemNearCanvasPoint(canvasPoint);
        this.setSelectedItem(item);
    },

    mouseLeave: function (event) {
        if (this.isEditing) { return; }
        this.setSelectedItem(null);
        this.element.getDocument().removeEvent("mousemove", this.mouseMoveBound);
    },
    
    setSelectedItem: function (item) {
        if (this.selectedItem) {
            this.pipelineView.setHighlightedWithStreamItem(false, this.selectedItem);
        }

        this.selectedItem = item;
        if (this.selectedItem) {
            this.pipelineView.setHighlightedWithStreamItem(true, this.selectedItem);
        }
        
        if (this.isEditable) {
            this.element.setStyle("cursor", this.selectedItem ? "row-resize" : "auto");
        }
    },
    
    //--------------------------------------------------------------------------------
    //
    //  animate

    animateResetBounds: function () {
        var bounds = this.getBoundsForStream(this.stream);
        this.animateSetBounds(bounds);
    },

    animateSetBounds: function (targetBounds) {
        var progress = 0;
        var speed = 0.5;
        
        if (this.resetTimer) { clearTimeout(this.resetTimer); }
        
        var timer = this.resetTimer = setInterval( (function () {
            progress += 1/30;
            if (progress > 0.8) { speed = 1; clearTimeout(timer); }

            this.bounds.max += speed * (targetBounds.max - this.bounds.max);
            this.bounds.min += speed * (targetBounds.min - this.bounds.min);
            this.render();
        }).bind(this), 1000/30);
    },

});

