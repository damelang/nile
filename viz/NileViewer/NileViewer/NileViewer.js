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
//  NVProgramView
//

var NVProgramView = this.NVProgramView = new Class({
    
    initialize: function (container) {
        container.empty();
        this.element = (new Element("div", { "class":"NVProgram" })).inject(container);
        
        if (NVPreferences.isHighContrast) { this.element.addClass("NVHighContrast"); }
        
        this.pipelineViews = [];
    },

    setPipeline: function (pipeline, inputStream) {
        this.pipeline = pipeline;
        this.initialInputStream = inputStream;
        
        NLPipelineRun(pipeline,inputStream);
        
        this.setPipelineAtColumnIndex(pipeline, 0);
        this.pipelineViews[0].setInitialInputStream(inputStream);
    },
    
    setInitialInputStream: function (newStream) {
        var newPipeline = NLPipelineClone(this.pipeline);
        this.setPipeline(newPipeline, newStream);
    },


    //--------------------------------------------------------------------------------
    //
    //  pipeline views
    
    getColumnCount: function () {
        return this.pipelineViews.length;
    },
    
    getPipelineViewAtColumnIndex: function (columnIndex) {
        return this.pipelineViews[columnIndex];
    },
    
    setPipelineAtColumnIndex: function (pipeline, columnIndex) {
        while (this.pipelineViews.length <= columnIndex) { 
            this.pipelineViews.push(new NVPipelineView(this, this.pipelineViews.length));
        }
        
        this.pipelineViews[columnIndex].setPipeline(pipeline);
        this.updateCodeViewsShowing();
    },
    
    removeColumnsAfterIndex: function (columnIndex) {
        while (this.pipelineViews.length > columnIndex + 1) {
            this.pipelineViews.pop().destroy();
        }
        this.updateCodeViewsShowing();
    },
    
    updateCodeViewsShowing: function () {
        var lastColumnIndex = this.pipelineViews.length - 1;
        Array.each(this.pipelineViews, function (pipelineView, columnIndex) {
            pipelineView.setCodeViewsShowing(columnIndex == lastColumnIndex);
        }, this);
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
            if (!iconView.isInput) { canvasViews.include(iconView.processView.canvasView); }
        }, this);

        if (canvasViews.length || !isHot) { return canvasViews; }

        Array.each(streamItem.iconViews || [], function (iconView) {
            if (iconView.isInput) {
                var previousProcessView = this.getPreviousProcessView(iconView.processView);
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


    //--------------------------------------------------------------------------------
    //
    //  process views
    
    forEachProcessView: function (f, bind) {
        Array.each(this.pipelineViews, function (pipelineView) {
            Array.each(pipelineView.processViews, f, bind);
        }, this);
    },
    
    getPreviousProcessView: function (processView) {
        var siblingProcessViews = processView.pipelineView.processViews;
        var index = siblingProcessViews.indexOf(processView);
        if (index >= 1) {
            return siblingProcessViews[index - 1];
        }
        
        var previousPipelineView = this.pipelineViews[processView.pipelineView.columnIndex - 1];
        if (previousPipelineView) {
            return previousPipelineView.processViews[previousPipelineView.expandedViewIndex - 1];
        }

        return null;
    },
    
});



//====================================================================================
//
//  NVPipelineView
//

var NVPipelineView = new Class({
    
    initialize: function (programView, columnIndex) {
        this.programView = programView;
        this.columnIndex = columnIndex;

        this.element = new Element("div", { "class":"NVPipeline", "html":this.getTemplateHTML() });
        this.element.inject(programView.element);
        this.element.setStyle("left", this.columnIndex * this.element.offsetWidth);

        this.processViews = [];
        this.expandedViewIndex = -1;
        this.hasInitialInput = (columnIndex == 0);
        
        this.updateBracket();
    },

    setPipeline: function (pipeline) {
        this.pipeline = pipeline;
    
        var processViewOffset = this.hasInitialInput ? 1 : 0;
        var viewCount = pipeline.length + processViewOffset;

        while (this.processViews.length < viewCount) { this.processViews.push(new NVProcessView(this)); }
        while (this.processViews.length > viewCount) { this.processViews.pop().destroy(); }
        
        Array.each(pipeline, function (process, i) {
            this.processViews[i + processViewOffset].setProcess(process);
        }, this);
        
        if (this.expandedViewIndex >= 0) {
            var processView = this.processViews[this.expandedViewIndex];
            if (processView && processView.process) {
                this.programView.setPipelineAtColumnIndex(processView.process.subpipeline, this.columnIndex + 1);
            }
        }
    },
        
    setInitialInputStream: function (stream) {
        if (!this.hasInitialInput) { return; }
        this.processViews[0].setInitialInputStream(stream);
    },

    destroy: function () {
        while (this.processViews.length) {
            this.processViews.pop().destroy();
        }
        this.element.destroy();
    },


    //--------------------------------------------------------------------------------
    //
    //  expansion
    
    isProcessViewExpanded: function (processView) {
        var viewIndex = this.processViews.indexOf(processView);
        return (viewIndex >= 0) && (this.expandedViewIndex == viewIndex);
    },

    toggleProcessViewExpanded: function (processView) {
        var shouldExpand = !this.isProcessViewExpanded(processView);
        this.setProcessViewExpanded(processView, shouldExpand);
    },
    
    setProcessViewExpanded: function (processView, shouldExpand) {
        var viewIndex = this.processViews.indexOf(processView);
        if (viewIndex < 0) { return; }
        if (shouldExpand == this.isProcessViewExpanded(processView)) { return; }

        this.expandedViewIndex = shouldExpand ? viewIndex : -1;
        this.programView.removeColumnsAfterIndex(this.columnIndex);
        
        if (shouldExpand) {
            this.programView.setPipelineAtColumnIndex(processView.process.subpipeline, this.columnIndex + 1);
        }

        this.updateBracket();
    },
    
    updateBracket: function () {
        var hasBracket = (this.expandedViewIndex >= 0);
        this.element.getElement(".NVBracket").setStyle("display", hasBracket ? "block" : "none");
        
        Array.each(this.processViews, function (processView, i) {
            processView.setExpandedAppearance(this.expandedViewIndex === i);
        }, this);
        
        if (!hasBracket) { return; }
        
        var subpipelineView = this.programView.getPipelineViewAtColumnIndex(this.columnIndex + 1);
        var subviewCount = subpipelineView.processViews.length;
        var processHeight = subviewCount ? subpipelineView.processViews[0].element.getHeight() : 0;
        
        var topElement = this.element.getElement(".NVBracketTop");
        var bottomElement = this.element.getElement(".NVBracketBottom");
        
        topElement.setStyle("height", Math.round((this.expandedViewIndex + 0.5) * processHeight) - 38);
        bottomElement.setStyle("height", Math.round((Math.max(0, subviewCount - this.expandedViewIndex - 1) + 0.5) * processHeight) - 38);
    },

    setCodeViewsShowing: function (showing) {
        Array.each(this.processViews, function (processView) {
            processView.setCodeViewShowing(showing);
        }, this);
    },
    
    getTemplateHTML: function () {
        return ''
        +' <div class="NVBracket">'
        +'     <div class="NVBracketTop"></div>'
        +'     <div class="NVBracketBottom"></div>'
        +' </div>'
    },
    
});


//====================================================================================
//
//  NVProcessView
//

var NVProcessView = new Class({
    
    initialize: function (pipelineView) {
        this.pipelineView = pipelineView;
        
        this.element = new Element("div", { "class":"NVProcess", "html":this.getTemplateHTML() });
        this.element.inject(pipelineView.element);

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
        
        nameElement.removeEvents("click");

        if (process.subpipeline.length) {
            nameElement.addClass("NVProcessNameClickable");
            nameElement.addEvent("click", this.nameWasClicked.bind(this));
        }
        else {
            nameElement.removeClass("NVProcessNameClickable");
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
        this.pipelineView.toggleProcessViewExpanded(this, this.process.subpipeline);
    },
    
    getTemplateHTML: function () {
        return ''
        +' <div class="NVProcessBackground"></div>'
        +' <div class="NVProcessHeader">'
        +'     <div class="NVProcessTitle">'
        +'         <span class="NVProcessTitleTriangle"></span>'
        +'         <span class="NVProcessName">StrokeBezierPath</span>'
        +'         <span class="NVProcessParameters">(4,0,0)</span>'
        +'     </div>'
        +'     <div class="NVProcessInput">'
        +'         <div class="NVProcessIcons"></div>'
        +'         <div class="NVProcessIconsCaption">Input: 4 Beziers</div>'
        +'     </div>'
        +'     <div class="NVProcessOutput">'
        +'         <div class="NVProcessIcons"></div>'
        +'         <div class="NVProcessIconsCaption">Output: 6 Beziers</div>'
        +'     </div>'
        +' </div>'
        +' <div class="NVProcessCanvas">'
        +'     <canvas width="200" height="150"></canvas>'
        +'     <div class="NVProcessCanvasHelp">zoom: shift-drag<br>reset: double-click</div>'
        +'     <div class="NVProcessCanvasCaption"></div>'
        +' </div>'
        +' <div class="NVProcessCode"></div>'
    },
    
});


//====================================================================================
//
//  NVStreamView
//

var NVStreamView = new Class({
    
    initialize: function (processView, isInput) {
        this.processView = processView;
        this.pipelineView = processView.pipelineView;
        
        this.isInput = isInput;
        this.element = processView.element.getElement(".NVProcess" + (this.isInput ? "Input" : "Output"));

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
    
    initialize: function (streamView) {
        this.streamView = streamView;
        this.processView = streamView.processView;
        this.pipelineView = streamView.pipelineView;
        
        var container = streamView.element.getElement(".NVProcessIcons");
        
        this.element = (new Element("span", { "class":"NVProcessIcon" })).inject(container);
        this.innerElement = (new Element("span", { "class":"NVProcessIconInner" })).inject(this.element);

        this.isInput = streamView.isInput;

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
        this.pipelineView.programView.setHighlightedWithStreamItem(true, this.streamItem, this.streamView.isInput);
    },
    
    mouseLeave: function () {
        this.pipelineView.programView.setHighlightedWithStreamItem(false, this.streamItem, this.streamView.isInput);
    },
    
});


//====================================================================================
//
//  NVCodeView
//

var NVCodeView = new Class({
    
    initialize: function (processView, process) {
        this.processView = processView;

        this.element = processView.element.getElement(".NVProcessCode");

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
    
    initialize: function (codeView) {
        this.codeView = codeView;
        this.element = (new Element("div", { "class":"NVProcessCodeLine" })).inject(codeView.element);
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

