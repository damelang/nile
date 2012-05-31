//
//  NileViewer.js
//  NileViewer
//
//  Created by Bret Victor on 4/29/12.
//


//====================================================================================
//
//  gNVPreferences
//

var NVPreferences = {

    isHighContrast: false,

};


//====================================================================================
//
//  NVPipelineView
//

var NVPipelineView = this.NVPipelineView = new Class({
    
    initialize: function (container) {
        container.empty();
        this.element = (new Element("div", { "class":"NVPipeline" })).inject(container);

        if (NVPreferences.isHighContrast) { this.element.addClass("NVPipelineHighContrast"); }

        this.columns = [];
        this.expandedViewIndexes = [];
        this.columnElements = [ this.element ];
    },

    setPipeline: function (pipeline, inputStream) {
        this.pipeline = pipeline;
        this.initialInputStream = inputStream;
        
        NLPipelineRun(pipeline,inputStream);
        
        this.updateProcessViews();
    },
    
    setInitialInputStream: function (newStream) {
        var newPipeline = NLPipelineClone(this.pipeline);
        this.setPipeline(newPipeline, newStream);
    },


    //--------------------------------------------------------------------------------
    //
    //  process views
    
    updateProcessViews: function () {
        this.setPipelineForColumn(this.pipeline, 0);
        this.columns[0][0].setInitialInputStream(this.initialInputStream);

        Array.each(this.expandedViewIndexes, function (viewIndex, columnIndex) {
            var processView = this.columns[columnIndex][viewIndex];
            if (processView && processView.process) {
                this.setPipelineForColumn(processView.process.subpipeline, columnIndex + 1);
            }
        }, this);
    },

    forEachProcessView: function (f, bind) {
        Array.each(this.columns, function (processViews) {
            Array.each(processViews, f, bind);
        }, this);
    },
    
    getPreviousProcessView: function (processView) {
        var column = this.columns[processView.columnIndex];
        var index = column.indexOf(processView);
        if (index >= 1) {
            return column[index - 1];
        }
        
        if (processView.columnIndex > 0) {
            column = this.columns[processView.columnIndex - 1];
            index = this.expandedViewIndexes[processView.columnIndex - 1];
            if (index >= 1) {
                return column[index - 1];
            }
        }

        return null;
    },


    //--------------------------------------------------------------------------------
    //
    //  columns
    
    setPipelineForColumn: function (pipeline, columnIndex) {
        while (this.columns.length <= columnIndex) { this.columns.push( [] ); }
        
        var column = this.columns[columnIndex];
        var processViewOffset = (columnIndex == 0) ? 1 : 0;  // first column has initial input
        var viewCount = pipeline.length + processViewOffset;

        while (column.length < viewCount) { column.push(new NVProcessView(this, columnIndex)); }
        while (column.length > viewCount) { column.pop().destroy(); }
        
        Array.each(pipeline, function (process, i) {
            column[i + processViewOffset].setProcess(process);
        }, this);

        this.setCodeViewsShowingForColumn(false, columnIndex - 1);
        this.setCodeViewsShowingForColumn(true, columnIndex);
    },
    
    removeColumn: function (columnIndex) {
        while (this.columns.length > columnIndex) {
            var column = this.columns[this.columns.length - 1];
            while (column.length > 0) { column.pop().destroy(); }
            this.columns.pop();
        }
        this.setCodeViewsShowingForColumn(true, columnIndex - 1);
    },
    
    getColumnCount: function () {
        return this.columns.length;
    },
    
    toggleProcessViewExpanded: function (processView) {
        var columnIndex = processView.columnIndex
        var column = this.columns[columnIndex];
        
        var viewIndex = column.indexOf(processView);
        if (viewIndex < 0) { return; }
        
        var shouldExpand = (this.expandedViewIndexes[columnIndex] !== viewIndex);
        while (this.expandedViewIndexes.length > columnIndex) { this.expandedViewIndexes.pop(); }
        
        if (shouldExpand) {
            this.removeColumn(columnIndex + 2);
            this.expandedViewIndexes[columnIndex] = viewIndex;
        }
        else {
            this.removeColumn(columnIndex + 1);
        }
        
        this.updateProcessViews();
        this.updateBracketForColumn(columnIndex);
    },
    
    updateBracketForColumn: function (columnIndex) {
        var container = this.columnElements[columnIndex + 1];
        if (!container) { return; }

        var expandedViewIndex = this.expandedViewIndexes[columnIndex];
        var isExpanded = (expandedViewIndex !== undefined);

        container.getElement(".NVBracket").setStyle("display", isExpanded ? "block" : "none");
        
        Array.each(this.columns[columnIndex], function (processView, i) {
            processView.setExpandedAppearance(expandedViewIndex === i);
        }, this);
        
        if (!isExpanded) { return; }

        var column = this.columns[columnIndex + 1];
        var subviewCount = column.length;
        var processHeight = column[0].element.getHeight();
        
        var topElement = container.getElement(".NVBracketTop");
        var bottomElement = container.getElement(".NVBracketBottom");
        
        topElement.setStyle("height", Math.round((expandedViewIndex + 0.5) * processHeight) - 38);
        bottomElement.setStyle("height", Math.round((Math.max(0, subviewCount - expandedViewIndex - 1) + 0.5) * processHeight) - 38);
    },

    setCodeViewsShowingForColumn: function (showing, columnIndex) {
        Array.each(this.columns[columnIndex] || [], function (processView) {
            processView.setCodeViewShowing(showing);
        }, this);
    },

    getContainerForColumn: function (columnIndex) {
        if (!this.columnElements[columnIndex]) {
            var previousContainer = this.getContainerForColumn(columnIndex - 1);
            var templateElement = $("NVTemplates").getElement(".NVSubpipeline");
            this.columnElements[columnIndex] = templateElement.clone().inject(previousContainer, "top");
        }
        return this.columnElements[columnIndex];
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
        this.forEachProcessView(function (processView) {
            processView.canvasView.selectedItems = [];
            processView.canvasView.hotItem = null;
        }, this);
    },

    highlightStreamItemBackward: function (streamItem, isHighlighted, isHot) {
        var color = !isHighlighted ? false : isHot ? "hot" : true;
        Array.each(streamItem.iconViews || [], function (iconView) { iconView.setHighlight(color); });

        if (streamItem.producerTrace) {
            Array.each(streamItem.producerTrace.consumedItems, function (item) {
                this.highlightStreamItemBackward(item, isHighlighted);
                if (isHighlighted) { this.addItemToCanvasSelectedItems(item); }
            }, this);
        }
    }, 
    
    highlightStreamItemForward: function (streamItem, isHighlighted, isHot) {
        var color = !isHighlighted ? false : isHot ? "hot" : true;
        Array.each(streamItem.iconViews || [], function (iconView) { iconView.setHighlight(color); });

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
        var canvasViews = this.getCanvasViewsForStreamItem(item, isHot);
        Array.each(canvasViews, function (canvasView) {
            if (isHot) { canvasView.hotItem = item; }
            else { canvasView.selectedItems.push(item); }
        }, this);
    },
    
    getCanvasViewsForStreamItem: function (streamItem, isHot) {
        var canvasViews = [];
        Array.each(streamItem.iconViews || [], function (iconView) {
            if (!iconView.isInput) { canvasViews.include(iconView.parentView.parentView.canvasView); }
        }, this);

        if (canvasViews.length || !isHot) { return canvasViews; }

        Array.each(streamItem.iconViews || [], function (iconView) {
            if (iconView.isInput) {
                var previousProcessView = this.getPreviousProcessView(iconView.parentView.parentView);
                if (previousProcessView) { canvasViews.include(previousProcessView.canvasView); }
            }
        }, this);
        
        return canvasViews;
    },
    
    renderAllCanvases: function () {
        this.forEachProcessView(function (processView) {
            processView.canvasView.render();
        }, this);
    },

    highlightCodeWithStreamItem: function (highlighted, streamItem, isInput) {
        var trace = isInput ? streamItem.consumerTraces[0] : streamItem.producerTrace;
        if (!trace) { return; }
        
        var processView = trace.process.processView;
        if (!processView) { return; }
        
        processView.codeView.setHighlightedLineIndexes( highlighted ? trace.lineIndexes : [] );
    },
    
});


//====================================================================================
//
//  NVProcessView
//

var NVProcessView = new Class({
    
    initialize: function (parentView, columnIndex) {
        this.pipelineView = parentView;
        this.parentView = parentView;
        this.columnIndex = columnIndex;
        
        var container = parentView.getContainerForColumn(columnIndex);
        var templateElement = $("NVTemplates").getElement(".NVProcess");
        
        this.element = templateElement.clone();
        this.element.inject(container);

        this.canvasView = new NVInteractiveCanvasView(this);
        this.codeView = new NVCodeView(this);

        this.inputStreamView = new NVStreamView(this, true);
        this.outputStreamView = new NVStreamView(this, false);
    },
    
    setProcess: function (process) {
        this.detachFromProcess();
    
        this.process = process;
        process.processView = this;
        
        var nameElement = this.element.getElement(".NVProcessName");
        nameElement.set("text", NLProcessGetName(process));
        this.updateTitleTriangle();
        
        if (process.subpipeline.length) {
            nameElement.addClass("NVProcessNameClickable");
            nameElement.removeEvents("click");
            nameElement.addEvent("click", this.nameWasClicked.bind(this));
        }
        else {
            nameElement.removeClass("NVProcessNameClickable");
            nameElement.removeEvents("click");
        }
        
        this.element.getElement(".NVProcessParameters").set("text", "( )");
        
        this.canvasView.setStream(process.outputStream);
        this.codeView.setCode(NLProcessGetCode(process));
        
        this.inputStreamView.setStream(process.inputStream);
        this.outputStreamView.setStream(process.outputStream);
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
    
    detachFromProcess: function () {
        if (!this.process) { return; }

        this.inputStreamView.detachFromStreamItems();
        this.outputStreamView.detachFromStreamItems();
        
        this.process.processView = null;
        this.process = null;
    },
    
    destroy: function () {
        this.detachFromProcess();
        this.element.destroy();
    },

    setCodeViewShowing: function (showing) {
        this.codeView.setShowing(showing);
    },
    
    setExpandedAppearance: function (expanded) {
        this.isExpanded = expanded;
        this.element[expanded ? "addClass" : "removeClass"]("NVProcessExpanded");
        this.updateTitleTriangle();
    },
    
    updateTitleTriangle: function () {
        var character = (!this.process || !this.process.subpipeline.length) ? "" : this.isExpanded ? "&#9660;" : "&#9654;";
        this.element.getElement(".NVProcessTitleTriangle").set("html", character);
    },
    
    nameWasClicked: function (event) {
        event.stop();
        this.parentView.toggleProcessViewExpanded(this, this.process.subpipeline);
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
        
        var prefix = isSolo ? "" : this.isInput ? "processed " : "output "
        var suffix = NLObjectGetTypeName(stream[0].object) + (stream.length == 1 ? "" : "s");
        var caption = prefix + stream.length + " " + suffix;
        this.element.getElement(".NVProcessIconsCaption").set("text", caption);

        var iconWidth = this.getIconWidth();
        
        while (this.iconViews.length < stream.length) { this.iconViews.push(new NVIconView(this)); }
        while (this.iconViews.length > stream.length) { this.iconViews.pop().destroy(); }

        Array.each(stream, function (streamItem, i) {
            this.iconViews[i].setStreamItem(streamItem, iconWidth);
        }, this);
    },

    detachFromStreamItems: function () {
        Array.each(this.iconViews, function (iconView) { 
            iconView.detachFromStreamItem();
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

        this.isInput = parentView.isInput;

        this.element.addEvent("mouseenter", this.mouseEnter.bind(this));
        this.element.addEvent("mouseleave", this.mouseLeave.bind(this));
    },
    
    setStreamItem: function (streamItem, width) {
        width = width || 16;
        
        this.streamItem = streamItem;
        this.width = width;
        this.height = width;
        
        if (!streamItem.iconViews) { streamItem.iconViews = []; }
        streamItem.iconViews.include(this);

        this.element.setStyle("width", this.width);
        this.element.setStyle("height", this.height);

        var innerHeight = Math.max(4, Math.ceil(this.height * Math.pow(0.7, streamItem.recursionDepth)));
        this.innerElement.setStyle("width", this.width);
        this.innerElement.setStyle("height", innerHeight);
        this.innerElement.setStyle("marginTop", this.height - innerHeight);
        
        this.setHighlight(false);
    },

    detachFromStreamItem: function () {
        if (this.streamItem && this.streamItem.iconViews) {
            this.streamItem.iconViews.erase(this);
        }
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

    setShowing: function (showing) {
        this.element.setStyle("display", showing ? "block" : "none");
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

        var leadingSpaceMatch = line.match(/^ */);
        this.indentCount = leadingSpaceMatch ? Math.min(8, leadingSpaceMatch[0].length) : 0;
        
        this.element.set("text", line.substr(this.indentCount));
        this.element.setStyle("marginLeft", this.indentCount * 7);
        
        this.setHighlighted(false);
    },
    
    setHighlighted: function (highlighted) {
        if (this.isHighlighted === highlighted) { return; }
        this.isHighlighted = highlighted;
        
        this.element[highlighted ? "addClass" : "removeClass"]("NVProcessCodeLineHot");
    },

});

