<master>
<property name="title">@page_title@</property>
<property name="main_navbar_label">@main_navbar_label@</property>
<property name="sub_navbar">@sub_navbar;noquote@</property>
<property name="left_navbar">@left_navbar_html;noquote@</property>

<table>
<tr><td>
<div id="chart_div" style="overflow: hidden; position:absolute; width:100%; height:100%; bgcolo=red;"></div>
</td></tr>
</table>

<script>

var report_start_date = '@report_start_date@';
var report_end_date = '@report_end_date@';
var report_project_type_id = '@report_project_type_id@';
var report_program_id = '@report_program_id@';

Ext.Loader.setPath('Ext.ux', '/sencha-v411/examples/ux');
Ext.Loader.setPath('PO.model', '/sencha-core/model');
Ext.Loader.setPath('PO.model.project', '/sencha-core/model/project');
Ext.Loader.setPath('PO.store', '/sencha-core/store');
Ext.Loader.setPath('PO.store.project', '/sencha-core/store/project');
Ext.Loader.setPath('PO.class', '/sencha-core/class');
Ext.Loader.setPath('PO.controller', '/sencha-core/controller');

Ext.require([
    'Ext.data.*',
    'Ext.grid.*',
    'Ext.tree.*',
    'PO.model.project.Project',
    'PO.store.project.ProjectMainStore',
    'PO.controller.StoreLoadCoordinator'
]);



Ext.define('PO.model.resource_management.ProjectResourceLoadModel', {
    extend: 'Ext.data.Model',
    fields: [
        'id',
        'project_id',				// ID of the main project
        'project_name',				// The name of the project
        'start_date',				// '2001-01-01 00:00:00+01'
        'end_date',
        'start_j',				// Julian start date of the project
        'end_j',				// Julian end date of the project
        'percent_completed',			// 0 - 100: Defines what has already been done.
        'on_track_status_id',			// 66=green, 67=yellow, 68=red
        'description',
        'perc',					// Array with J -> % assignments per day, starting with start_date
        'sprite_group',				// Sprite group representing the project bar
        { name: 'end_date_date',		// end_date as Date, required by Chart
          convert: function(value, record) {
              var end_date = record.get('end_date');
              return new Date(end_date);
          }
        }
    ]
});


Ext.define('PO.store.resource_management.ProjectResourceLoadStore', {
    extend:			'Ext.data.Store',
    storeId:			'projectResourceLoadStore',
    model: 			'PO.model.resource_management.ProjectResourceLoadModel',
    remoteFilter:		true,			// Do not filter on the Sencha side
    autoLoad:			true,
    pageSize:			100000,			// Load all projects, no matter what size(?)
    proxy: {
        type:			'rest',			// Standard ]po[ REST interface for loading
        url:			'/intranet-resource-management/resource-leveling-editor/main-projects-forward-load.json',
        timeout:		300000,
	extraParams: {
            format:             'json',
	    start_date:		report_start_date,	// When to start
	    end_date:		report_end_date,	// when to end
	    granularity:	'@report_granularity@',	// 'week' or 'day'
            project_type_id:	report_project_type_id	// Only projects in status "active" (no substates)
        },
        reader: {
            type:		'json',			// Tell the Proxy Reader to parse JSON
            root:		'data',			// Where do the data start in the JSON file?
            totalProperty:	'total'			// Total number of tickets for pagination
        }
    }
});


Ext.define('PO.model.resource_management.CostCenterResourceLoadModel', {
    extend: 'Ext.data.Model',
    fields: [
        'id',
        'cost_center_id',			// ID of the main cost_center
        'cost_center_name',			// The name of the cost_center
        'available_days',			// Array with J -> % assignments per day, starting with start_date
        'sprite_group'				// Sprite group representing the cost center bar
    ]
});


Ext.define('PO.store.resource_management.CostCenterResourceLoadStore', {
    extend:			'Ext.data.Store',
    storeId:			'costCenterResourceLoadStore',
    model: 			'PO.model.resource_management.CostCenterResourceLoadModel',
    remoteFilter:		true,			// Do not filter on the Sencha side
    autoLoad:			true,
    pageSize:			100000,			// Load all cost_centers, no matter what size(?)
    proxy: {
        type:			'rest',			// Standard ]po[ REST interface for loading
        url:			'/intranet-resource-management/resource-leveling-editor/cost-center-resource-availability.json',
        timeout:		300000,
	extraParams: {
            format:             'json',
	    granularity:	'@report_granularity@',	// 'week' or 'day'
	    report_start_date:	report_start_date,	// When to start
	    report_end_date:	report_end_date		// when to end
        },
        reader: {
            type:		'json',			// Tell the Proxy Reader to parse JSON
            root:		'data',			// Where do the data start in the JSON file?
            totalProperty:	'total'			// Total number of tickets for pagination
        }
    }
});



/**
 * Like a chart Series, displays a list of projects
 * using Gantt bars.
 */
Ext.define('PO.class.resource_management.ResourceEditor', {
    // x/y/width/height 
    barBaseX: null,				// Start of drawing bars at the start of the X axis
    barBaseY: null,				// Start of drawing bars below the X axis
    barHeight: 15,				// Height of a bar
    barRadius: 3,				// Corner radius of a bar

    // time axis related 
    timeStart: 0,				// Time (Julian date in milliseconds) starting at the left of the date axis
    timeEnd: 0,				// Time end at the right of the date axis

    // Project store info: earliest and latest project.
    // These DO NOT correspond to the start and end of the date axis
    // Pleas see timeStart and timeEnd for these
    minDate: '2099-12-31',
    maxDate: '2000-01-01',

    chart: null,
    projectStore: null,
    costCenterStore: null,

    // Base values when initiating DnD
    dndBaseMouseXY: null,			// 
    dndBaseSprite: null,			// 
    dndFrameSprite: null,			// Sprite representing a dark frame rendered for draging

    // Values while moving
    dndLastButton: -1,				// Mouse button of last onMouseMove for detecting changes
    dndLastMouseXY: null,			// Coordinates of last mouse event

    lastButton: -1,				// During event processing: last button value
    lastMouseXY: null,				// During event processing: last mouse position
    lastSprite: null,
    newButton: -1,				// During event processing: current buttom value
    newMouseXY: null,				// During event processing: current mouse position
    newSprite: null,

    projectGrid: null,
    costCenterGrid: null,

    constructor: function(config) {
        var me = this;
        Ext.apply(me, config);

        return this;
    },

    /**
     * The Chart is responsible for drawing the time axis and
     * to provide the surface etc.
     * The Chart also determines the scaling of bars.
     */
    setChart: function(chart) {
	var me = this;
	me.chart = chart;
	
	// Get Axes information (screen x/y coordinates)
        var axes = chart.axes.items;
        var topAxis = chart.axes.map.top;
        me.barBaseX = topAxis.x;		// Start drawing bars at the start of the X axis
        me.barBaseY = topAxis.y + 5;		// Start drawing bars below the X axis
	me.barLength = topAxis.length;		// Length of the date axis

	// Get the start and end of the axis in the time realm
        var topAxisMinMax = topAxis.getRange();
        var range = Ext.draw.Draw.snapEndsByDateAndStep(new Date(topAxisMinMax.min), new Date(topAxisMinMax.max), [Ext.Date.MONTH, 2]);
	me.timeStart = range.from;
	me.timeEnd = range.to;

    },

    /**
     * The Grid shows the list of projects.
     * It serves to determine the Y position of projects in the projectGrid.
     * We need to listen to change events of the ProjectGrid in order to redraw
     * project bars if there were changes.
     */
    setProjectGrid: function(projectGrid) {
	var me = this;
	me.projectGrid = projectGrid;
    },

    setCostCenterGrid: function(ccGrid) {
	var me = this;
	me.costCenterGrid = ccGrid;
    },

    /**
     * Determine min and max date.
     * Only needs the projectStore to proceed (no chart yet).
     */
    calculateMinMaxDate: function() {
        var me = this;
        var projectStore = me.projectStore;
        var minDate = me.minDate;
        var maxDate = me.maxDate;

        for (var i=0; i < projectStore.getCount(); i++) {
            var model = projectStore.getAt(i);
            var start_date = model.get('start_date').substring(0,10);
            var end_date = model.get('end_date').substring(0,10);
            if (start_date < minDate) { minDate = start_date }
            if (end_date > maxDate) { maxDate = end_date }
        }

        me.minDate = minDate;
        me.maxDate = maxDate;
    },

    /**
     * Draw a a Gantt bar for a single project
     */
    drawProjectBar: function(sur, x, y, w, h, project, tenthArray) {
        var me = this;
        var projectName = project.get('project_name');

        // Used for grouping all sprites into one group
        var spriteGroup = Ext.create('Ext.draw.CompositeSprite', {
            surface: sur,
            autoDestroy: true
        });

        // Draw the backround for the bars, depending on resource load
        for (var i = 0; i < tenthArray.length; i++) {

	    if (typeof tenthArray[i] == 'undefined') { tenthArray[i] = 0.0; }
            var xTenth = x + i * 7;					// Start X for array element
            var wTenth = 7;						// Normal width: 7
            if (xTenth + wTenth > x + w) { wTenth = x+w - xTenth; }	// Last square: Don't exceed bar length

            // Calculate the opacity of the bar depending on resource use
            var opacity = 0.2 + Math.log(1+tenthArray[i]) / 20.0;
            if (opacity > 1.0) { opacity = 1.0; }

            var spriteSegment = sur.add([{
                type: 'rect',
                x: xTenth,
                y: y,
                width: wTenth,
                height: h,
                radius: 0,
                fill: 'blue',
                opacity: opacity
            }])[0];
            spriteSegment.animate({duration: 0});
            spriteGroup.add(spriteSegment);
        }

        var spriteBar = sur.add([{
            type: 'rect',
            x: x,
            y: y,
            width: w,
            height: h,
            radius: me.barRadius,
            stroke: 'blue',
            'stroke-width': 1
        }])[0];
        spriteBar.animate({duration: 0});
        spriteGroup.add(spriteBar);

        // White highlight at the upper part of each bar
        var spritHighlightWidth = w - me.barRadius * 2;	// Don't allow negative width
        if (spritHighlightWidth < 0) { spritHighlightWidth = 1 }
        var spriteHighlight = sur.add([{
            type: 'rect',
            x: x + 2,
            y: y + 1,
            width: spritHighlightWidth,
            height: h / 3.0,
            radius: me.barRadius / 2.0,
            fill: 'white',
            opacity: 0.5
        }])[0];
        spriteHighlight.animate({duration: 0});
        spriteGroup.add(spriteHighlight);

        // Place the text at the right of the sprite
        var spriteText = sur.add([{
            type: 'text',
            text: projectName,
            font: '12px Arial',
            x: x + w + me.barRadius,
            y: y + h / 2.0,
            width: w,
            height: h,
            fill: 'black',
            'stroke-width': 2
        }])[0];
        spriteText.animate({duration: 0});
        spriteGroup.add(spriteText);

        // Add the spriteGroup to the model
        project.set('sprite_group', spriteGroup);
    },


    /**
     * Draw a a Cost Center bar for a single CC
     */
    drawCostCenterBar: function(sur, i, costCenter) {
        var me = this;


	// 
        var projectGridView = me.projectGrid.getView();
        var costCenterGridView = me.costCenterGrid.getView();
        var costCenterName = costCenter.get('cost_center_name');
        var availableDays = costCenter.get('available_days');

	// getBoundingClientRect() - Returns a TextRectangle object that specifies the bounding rectangle of the current element or 
	// TextRange object, in pixels, relative to the upper-left corner of the browser's client area.
	var startYFirstProject = projectGridView.getNode(0, true).getBoundingClientRect().top;
	var startYCostCenter = costCenterGridView.getNode(i, true).getBoundingClientRect().top;

	// surface Y pos is relative to top, 35px below the first project.
	var startY = startYCostCenter - startYFirstProject + 35;

        // Used for grouping all sprites into one group
        var spriteGroup = Ext.create('Ext.draw.CompositeSprite', {
            surface: sur,
            autoDestroy: true
        });

	// Draw a bar across the entire diagram
	// ?? 
        var spriteBar = sur.add([{
            type: 'rect',
            x: me.barBaseX,
            y: startY,
            width: me.barLength,
            height: me.barHeight - me.barRadius,
            radius: me.barRadius,
            stroke: 'green',
            'stroke-width': 1
        }])[0];
        spriteBar.animate({duration: 0});
        spriteGroup.add(spriteBar);

        // Calcuate the tenthArray for the CC
	// 
        var tenthArray = new Array();
        for (var j=0; j < availableDays.length; j++) {
            var tDiff = j * 24.0 * 3600.0 * 1000.0;						// "j" days from the start of the project, tdiff = Seconds past from start_date * 1000
            var xDiff = Math.floor(me.barLength * tDiff / (me.timeEnd - me.timeStart));		// x-position of tDiff
	    var xTenth = Math.floor(xDiff);							// draw a box every 7px
	    // console.log('tDiff:' + tDiff + 'xDiff:' + xDiff + ', xTenth:' + xTenth);
            if (typeof tenthArray[xTenth] == 'undefined') { tenthArray[xTenth] = 0.0; }
            tenthArray[xTenth] = tenthArray[xTenth] + availableDays[j];
	}

	// console.log(JSON.stringify(tenthArray));	


        // Draw the backround for the bars, depending on resource load
	var startTime = me.timeStart;
	var endTime = startTime + 7 * 24.0 * 3600.0 * 1000.0;
        for (var i = 0; i < tenthArray.length; i++) {
	    if (typeof tenthArray[i] == 'undefined') { tenthArray[i] = 0.0; }
            var startXTenth = Math.floor(me.barBaseX + me.barLength * (startTime - me.timeStart) / (me.timeEnd - me.timeStart));
            var endXTenth = Math.floor(me.barBaseX + me.barLength * (endTime - me.timeStart) / (me.timeEnd - me.timeStart));
	    var widthTenth = endXTenth - startXTenth;
	    // PLAY
	    // var heightTenth = tenthArray[i];
	    var heightTenth = tenthArray[i] + 10;

            var spriteSegment = sur.add([{
                type: 'rect',
                x: startXTenth,
                y: startY,
                width: widthTenth,
                height: heightTenth,
                radius: 0,
                fill: 'red'
            }])[0];
            spriteSegment.animate({duration: 0});
            spriteGroup.add(spriteSegment);

	    // Set start and end of the next segment
	    startTime = endTime;
	    endTime = startTime + 7 * 24.0 * 3600.0 * 1000.0;
        }

        // Add the spriteGroup to the model
        costCenter.set('sprite_group', spriteGroup);
    },


    /**
     * Draw a a Gantt bar for a department
     */
    drawSummaryBar: function(sur, x, y, w, h, projectName, tenthArray) {
        var me = this;

        // Used for grouping all sprites into one group
        var spriteGroup = Ext.create('Ext.draw.CompositeSprite', {
            surface: sur,
            autoDestroy: true
        });

        // Draw the backround for the bars, depending on resource load
        for (var i = 0; i < tenthArray.length; i++) {
	    if (typeof tenthArray[i] == 'undefined') { tenthArray[i] = 0.0; }
            var xTenth = x + i * 7;					// Start X for array element
            var wTenth = 7;						// Normal width: 7
            if (xTenth + wTenth > x + w) { wTenth = x+w - xTenth; }	// Last square: Don't exceed bar length

            // Calculate the opacity of the bar depending on resource use
            var opacity = 0.2 + Math.log(1+tenthArray[i]) / 20.0;
            if (opacity > 1.0) { opacity = 1.0; }
	    opacity = 1.0;

	    h = tenthArray[i] / 500.0;
	    var myY = y - h;

	    if (opacity > 0.2) {
		var spriteSegment = sur.add([{
                    type: 'rect',
                    x: xTenth,
                    y: myY,
                    width: wTenth,
                    height: h,
                    radius: 0,
                    fill: 'blue',
                    opacity: opacity
		}])[0];
		spriteSegment.animate({duration: 0});
		spriteGroup.add(spriteSegment);
            }
	}

        // Place the text at the right of the sprite
        var spriteText = sur.add([{
            type: 'text',
            text: projectName,
            font: '12px Arial',
            x: x + w + me.barRadius,
            y: y + h / 2.0,
            width: w,
            height: h,
            fill: 'black',
            'stroke-width': 2
        }])[0];
        spriteText.animate({duration: 0});
        spriteGroup.add(spriteText);

    },

    removeAll: function() {
        var me = this;
        var surface = me.chart.surface;
	surface.removeAll();
    },

    redrawBars: function(scope) {
        var me = this;
	if (scope) { me = scope; }
	if (!me.chart) { return; }
        var surface = me.chart.surface;
	surface.removeAll();
	me.drawProjectBars();
    },

    drawProjectBars: function(scope) {
        // ?? What is this good for? 
        var me = this;
	if (scope) { me = scope; }
	if (!me.chart) { return; }

        var surface = me.chart.surface;
	var projectGridView = me.projectGrid.getView();
	var startYProjectGrid = me.projectGrid.getY();
	var firstProject = projectGridView.getNode(0, true);
	if (!firstProject) { return; }
	var startYFirstProject = projectGridView.getNode(0, true).getBoundingClientRect().top;

	// Summary of resource load across all projects
	var tenthSummaryArray = new Array();

        // Loop through the projectStore projects
        for (var i=0; i < me.projectStore.getCount(); i++) {
            var model = me.projectStore.getAt(i);
            var startDate = new Date(model.get('start_date').substring(0,10));
            var endDate = new Date(model.get('end_date').substring(0,10));

            var startX = Math.floor(me.barBaseX + me.barLength * (startDate.getTime() - me.timeStart) / (me.timeEnd - me.timeStart));
	    var startYProject = projectGridView.getNode(i, true).getBoundingClientRect().top;
	    var startY = startYProject - startYFirstProject + 85;
            // var startY = Math.floor(me.barBaseY + i * me.barHeight);

            var width = Math.floor((endDate.getTime() - startDate.getTime()) * me.barLength / (me.timeEnd - me.timeStart));
            if (width < 1) { width = 5; }
            var height = me.barHeight - me.barRadius;

            // Calculate tenthArray - an indication of resource use during the project
            var perc = model.get('perc');
            var baseTime = startDate.getTime();
            var tenthArray = new Array();
            for (var j=0; j < perc.length; j++) {

		// Calcuate the tenthArray of the project
                var tDiff = j * 24.0 * 3600.0 * 1000.0;							// "j" days from the start of the project
                var xDiff = Math.floor(me.barLength * tDiff / (me.timeEnd - me.timeStart));		// x-position of tDiff
                var xTenth = Math.floor(xDiff / 7.0);							// draw a box every 7px
                if (typeof tenthArray[xTenth] == 'undefined') { tenthArray[xTenth] = 0.0; }
        	tenthArray[xTenth] = tenthArray[xTenth] + perc[j];

		// Summary tenthArray
                var xSummaryDiff = Math.floor(startX + me.barLength * tDiff / (me.timeEnd - me.timeStart));	// x-position of tDiff
                var xSummaryTenth = Math.floor(xSummaryDiff / 7.0);								// draw a box every 7px
                if (typeof tenthSummaryArray[xSummaryTenth] == 'undefined') { tenthSummaryArray[xSummaryTenth] = 0.0; }
        	tenthSummaryArray[xSummaryTenth] = tenthSummaryArray[xSummaryTenth] + perc[j];

            }
            me.drawProjectBar(surface, startX, startY, width, height, model, tenthArray);
        }

	// Draw a summary bar
/*
	var startY = Math.floor(me.barBaseY + (i+2) * me.barHeight);
	var deptModel = Ext.create('PO.model.resource_management.ProjectResourceLoadModel', {
	    'project_name': 'Summary Bar',
	    'start_date': me.minDate,
	    'end_date': me.maxDate
	});
        me.drawSummaryBar(surface, me.barBaseX, startY, me.barLength, height, "Summary", tenthSummaryArray);
*/

    },

    drawCostCenterBars: function(scope) {
        var me = this;
	if (scope) { me = scope; }
	if (!me.chart) { return; }

        var surface = me.chart.surface;
	var costCenterGridView = me.costCenterGrid.getView();
	var startYCostCenterGrid = me.costCenterGrid.getY();
	var firstCostCenter = costCenterGridView.getNode(0, true);
	if (!firstCostCenter) { return; }
	var startYFirstCostCenter = costCenterGridView.getNode(0, true).getBoundingClientRect().top;

        // For all Cost Centers
	// PLAY: var i=0; i < me.costCenterStore.getCount(); i++
        for (var i=0; i < 1; i++) {
            var model = me.costCenterStore.getAt(i);
            me.drawCostCenterBar(surface, i, model);
        }

    },

    /**
     * Destroy a single bar composed of several sprites
     */
    destroyBar: function(spriteGroup) {
        var me = this;
        var surface = me.chart.surface;

        spriteGroup.each(function(o) {
            surface.remove(o);
            spriteGroup.remove(o);
            o.destroy();
        });

        spriteGroup.destroy();
    },

    /**
     * Destroy all bars
     */
    destroyBars: function() {
        var me = this;
        var surface = me.chart.surface;

        // Loop through the projectStore projects
        for (var i=0; i < me.projectStore.getCount(); i++) {
            var model = me.projectStore.getAt(i);
            var spriteGroup = model.get('sprite_group');
            if (spriteGroup != null) {
                me.destroyBar(spriteGroup);
            }
        }
    },

    /**
     * Checks for mouse inside the BBox
     */  
    isItemInPoint: function(x, y, item, i) {
        var spriteType = item.type;
        if (0 != "rect".localeCompare(spriteType)) { 
	    return false;					// We are only looking for bars...
	}
	if (item.radius == 0) { 
	    return false;					// ... with round corners.
	}
        var bbox = item.getBBox();
        return bbox.x <= x && bbox.y <= y
            && (bbox.x + bbox.width) >= x
            && (bbox.y + bbox.height) >= y;
    },

    /**
     * Returns the item for a x/y mouse coordinate
     */  
    getItemForPoint: function(x, y) {
        var me = this;
        var surface = me.chart.surface;
        var items = surface.items.items;
        for (var i = 0, ln = items.length; i < ln; i++) {
            if (items[i] && me.isItemInPoint(x, y, items[i], i)) {
                return items[i];
            }
        }
        return null;
    },

    
    // -----------------------------------------------------------------
    // Event Processing
    // -----------------------------------------------------------------

    onMouseUp: function(e, eOpts) { 
        var me = this;
        me.onMouseChange(e,'onMouseDown'); 
    },

    onMouseDown: function(e, eOpts) { 
        var me = this;
        me.onMouseChange(e,'onMouseDown'); 
    },

    onMouseMove: function(e, eOpts) { 
        var me = this;
        me.onMouseChange(e,'onMouseMove');
    },

    onMouseChange: function(e, eventName) {
        var me = this;
        
        var surface = me.chart.surface;
        var sprites = surface.items;

        // Get Base information
        me.newButton = e.button;
        me.lastButton = me.dndLastButton;
        me.dndLastButton = me.newButton;

        me.newMouseXY = e.getXY();
        me.newMouseXY[0] = e.browserEvent.offsetX;
        me.newMouseXY[1] = e.browserEvent.offsetY;
        me.lastMouseXY = me.dndLastMouseXY;
        me.dndLastMouseXY = me.newMouseXY;

        // Get the sprite under the mouse pointer
        me.newSprite = me.getItemForPoint(me.newMouseXY[0],me.newMouseXY[1]);

        if (me.newButton != me.lastButton) {
            console.log(eventName+': MouseButton: '+me.lastButton+' -> '+me.newButton);
            // The button status has changed.
            // Call corresponding events
            switch(me.newButton) {
            case 0: me.onMouseButtonDown(e);
                break
            case -1: me.onMouseButtonUp(e);
                break
            default: console.log(eventName+': MouseButton Change: '+me.lastButton+' -> '+me.newButton);
                break
            }
        } else {
            switch(me.newButton) {
            case 0: 
                // Left button ist pressed - check for a drag movement
                if (me.newMouseXY[0] != me.lastMouseXY[0] || me.newMouseXY[1] != me.lastMouseXY[1]) {
                    // left button is pressed - drag movement
                    // console.log(eventName+': MouseButton Change: ('+me.lastMouseXY[0]+','+me.lastMouseXY[1]+') -> ('+me.newMouseXY[0]+','+me.newMouseXY[1]+')');
                    me.onMouseDrag(e);
                }
                break
            case -1:
                // No button is pressed - update the cursor
                if (me.newSprite) {
                    Ext.getBody().setStyle("cursor", "e-resize");
                } else {
                    Ext.getBody().setStyle("cursor", "auto");
                }
                break
            default:
                // ignore everything else
                break
            }
        }

        me.lastSprite = me.newSprite;
    },

    /*
     * Mouse button pressed.
     * Initialize drag movement and draw dark DnD frame sprite
     */
    onMouseButtonDown: function(e) {
        var me = this;
        if (!me.newSprite) { return; }		// No object to drag?
        me.dndBaseMouseXY = me.lastMouseXY;	// Mark base position for drag
        me.dndBaseSprite = me.newSprite;	// Get the item below the mouse and store as DnD base
        
        // Create a sprite with dark frame if not yet there
        if (!me.dndFrameSprite) {
            var baseBbox = me.dndBaseSprite.getBBox();
            // Create a black frame sprite indicating the DnD position visually
            me.dndFrameSprite = me.chart.surface.add([{
                type: 'rect',
                width: baseBbox.width,
                height: baseBbox.height,
                stroke: 'black',
                'stroke-width': 2
            }])[0];
            
            // Move the sprite to the right position
            me.dndFrameSprite.animate({
                duration: 0,
                to: {
                    translate: {
                        x: baseBbox.x,
                        y: baseBbox.y
                    }
                }
            });
        }
    },

    /*
     * Drag movement with pressed left mouse button.
     * Just move the dark DnD frame along with the mouse.
     */
    onMouseDrag: function(e) {
        var me = this;
        if (!me.dndBaseSprite) { return; }				// No object to drag?
        var baseBbox = me.dndBaseSprite.getBBox();			// Get the bounding box of the original sprite

        // Calculate the difference between the initial and current pos
        var diffX = me.newMouseXY[0] - me.dndBaseMouseXY[0];
        var diffY = me.newMouseXY[1] - me.dndBaseMouseXY[1];

        // Move the frame according to the dragged distance
        me.dndFrameSprite.setAttributes({
                translate: {
                    x: baseBbox.x + diffX,
                    y: baseBbox.y + diffY
                }
        }, true);
    },

    /*
     * End of the DnD gesture.
     * Check if it was successful and update the chart.
     */
    onMouseButtonUp: function(e) {
        var me = this;
        if (!me.newMouseXY || !me.dndBaseMouseXY || !me.dndBaseSprite) { return; }	// Skip on right mouse button etc.
        var diffX = me.newMouseXY[0] - me.dndBaseMouseXY[0];				// How much did move the bar? Ignore Y value

        // var scaleX = me.dndBaseSprite.series.getBounds().scale; 			// scale from the "bounds" of the series
        // var diffXValue = diffX / scaleX;			 			// Calculate how much to move the bar
        var storeItem = me.dndBaseSprite.storeItem;		 			// store with sprite base information

        var startX = Math.floor(me.barBaseX + me.barLength * (startDate.getTime() - me.timeStart) / (me.timeEnd - me.timeStart));
        var startY = Math.floor(me.barBaseY + i * me.barHeight);
        var width = Math.floor((endDate.getTime() - startDate.getTime()) * me.barLength / (me.timeEnd - me.timeStart));

        // Shift projects only by full days in order to avoid problems with working time calendars
        var diffXValueRounded = Math.round(diffXValue / 1000.0 / 86400.0);
        diffXValue = diffXValueRounded * 1000.0 * 86400.0;

        // Update the start_ and end_date
        var d = new Date(new Date(storeItem.get('start_date')).getTime() + diffXValue);
        var df = d.getFullYear() + '-' + ("00" + (d.getMonth() + 1)).slice(-2) + "-" + ("00" + d.getDate()).slice(-2);
        storeItem.set('start_date', df);

        var d = new Date(new Date(storeItem.get('end_date')).getTime() + diffXValue);
        var df = d.getFullYear() + '-' + ("00" + (d.getMonth() + 1)).slice(-2) + "-" + ("00" + d.getDate()).slice(-2);
        storeItem.set('end_date', df);

        // Stop DnD action - either with success or without
        me.dndBaseSprite = null;
        if (me.dndFrameSprite) {
            me.dndFrameSprite.destroy();
            me.dndFrameSprite = null;
        }
    }

});



/**
 * Create a diagram and draw bars
 */  
function launchApplication(){
    
    var projectMainStore = Ext.StoreManager.get('projectMainStore');
    var projectResourceLoadStore = Ext.StoreManager.get('projectResourceLoadStore');
    var costCenterResourceLoadStore = Ext.StoreManager.get('costCenterResourceLoadStore');

    var numProjects = projectResourceLoadStore.getCount();
    var numDepts = costCenterResourceLoadStore.getCount();
    var numProjectsDepts = numProjects + numDepts;

    var listCellHeight = 27;
    var listProjectsAddOnHeight = 60;
    var listCostCenterAddOnHeight = 55;

    var renderDiv = Ext.get('chart_div');

    // A container for Gantt Bars
    var resourceEditor = Ext.create('PO.class.resource_management.ResourceEditor', {
        projectStore: projectResourceLoadStore,
	costCenterStore: costCenterResourceLoadStore
    });

    // Calculate min and maximum date from the ResourceEditor store
    resourceEditor.calculateMinMaxDate();
    resourceEditor.minDate = report_start_date;
    resourceEditor.maxDate = report_end_date;
    
    // Create a new chart with min/maxDate from ResourceEditor
    var chart = Ext.create('Ext.chart.Chart', {
        // renderTo: renderDiv,
	id: 'projectChart',
        width: Ext.getBody().getViewSize().width - 350,
        height: 40 + listCellHeight * numProjectsDepts,
	region: 'center',
        resizable: false,
        animate: true,
        store: projectMainStore,    // why do we need a store for this?
        axes: [{
	    // this is the top bar showing Calendar (days/months) 
            type: 'Time',
            position: 'top',
            fields: ['end_date'],
            title: 'Day',
            dateFormat: 'M y',
            grid: true,
            step: [Ext.Date.MONTH, 6],
            constrain: false,
            adjustMinimumByMajorUnit: true,
            adjustMaximumByMajorUnit: true,
            fromDate: new Date(resourceEditor.minDate),
            toDate: new Date(resourceEditor.maxDate)
        }]
    });


    var projectGridHeight = listProjectsAddOnHeight + listCellHeight * numProjects;
    var projectGridSelectionModel = Ext.create('Ext.selection.CheckboxModel');
    var projectGrid = Ext.create('Ext.grid.Panel', {
	title: false,
        region:'center',
	store: 'projectResourceLoadStore',
	height: projectGridHeight,
	selModel: projectGridSelectionModel,
	columns: [{ 
	    text: 'Name',  
	    dataIndex: 'project_name',
	    flex: 1
	}],
	shrinkWrap: true,
	viewConfig: {
            listeners: {
		viewready: function(gridview) {
                    console.log('onViewReady');
		    resourceEditor.redrawBars(resourceEditor);
		},
		resize: function(gridview) {
                    console.log('onResize');
		    resourceEditor.redrawBars(resourceEditor);
		}
            }
	}
    });


    var costCenterGridHeight = listCostCenterAddOnHeight + listCellHeight * numDepts;
    var costCenterGridSelectionModel = Ext.create('Ext.selection.CheckboxModel');
    var costCenterGrid = Ext.create('Ext.grid.Panel', {
	title: 'Departments',
        region:'south',
	height: costCenterGridHeight,
	store: 'costCenterResourceLoadStore',
	selModel: costCenterGridSelectionModel,
	columns: [{ 
	    text: 'Dept',  
	    dataIndex: 'cost_center_name',
	    flex: 1
	}],
	shrinkWrap: true,
	viewConfig: {
            listeners: {
		viewready: function(gridview) {
                    console.log('onViewReady');
		    resourceEditor.drawCostCenterBars(resourceEditor);
		},
		resize: function(gridview) {
                    console.log('onResize');
		    resourceEditor.drawCostCenterBars(resourceEditor);
		}
            }
	}
    });


    var borderPanelHeight = (listProjectsAddOnHeight + listCostCenterAddOnHeight) + listCellHeight * numProjectsDepts;
    var borderPanelWidth = Ext.getBody().getViewSize().width - 350;
    var borderPanel = Ext.create('Ext.panel.Panel', {
	width: borderPanelWidth,
	height: borderPanelHeight,
	title: false,
	layout: 'border',
	defaults: {
	    collapsible: true,
	    split: true,
	    bodyPadding: 0
	},
	items: [
	    {
		title: 'Projects',
		region: 'west',
		xtype: 'panel',
		layout: 'border',
		shrinkWrap: true,
		width: 300,
		split: true,
		items: [
		    projectGrid, 
		    costCenterGrid
		]
	    },
	    chart
	],

	renderTo: renderDiv
    });


    resourceEditor.setProjectGrid(projectGrid);
    resourceEditor.setCostCenterGrid(costCenterGrid);
    resourceEditor.setChart(chart);

    // Initialize event processing for the chart "surface"
    var surface = chart.surface;
    surface.on({
        mousemove: function(e, f) { resourceEditor.onMouseMove(e, f); },
        mousup: function(e, f) { resourceEditor.onMouseMove(e, f); },
        mousdown: function(e, f) { resourceEditor.onMouseDown(e, f); }
    });

    Ext.EventManager.onWindowResize(function () {
	// ToDo: Try to find out if there is another onWindowResize Event waiting
        // var height = chart.getSize().height;
	var borderPanelHeight = (listProjectsAddOnHeight + listCostCenterAddOnHeight) + listCellHeight * numProjectsDepts;
        var width = Ext.getBody().getViewSize().width - 350;
	borderPanel.setSize(width, borderPanelHeight);

        chart.setSize(width, borderPanelHeight);
	resourceEditor.setChart(chart);

	// resourceEditor.removeAll();
	// resourceEditor.drawBars(resourceEditor);
    });
};



Ext.onReady(function() {
    Ext.QuickTips.init();
    var projectMainStore = Ext.create('PO.store.project.ProjectMainStore');
    var projectResourceLoadStore = Ext.create('PO.store.resource_management.ProjectResourceLoadStore');
    var costCenterResourceLoadStore = Ext.create('PO.store.resource_management.CostCenterResourceLoadStore');

    var coo = Ext.create('PO.controller.StoreLoadCoordinator', {
        debug: 0,
        stores: [
            'projectMainStore',
            'projectResourceLoadStore',
	    'costCenterResourceLoadStore'
        ],
        listeners: {
            load: function() {
                // Launch the actual application.
                launchApplication();
            }
        }
    });

    // Load only open main projects that are not closed.
    projectMainStore.getProxy().extraParams = { 
	format: "json",
	query: "parent_id is NULL and project_type_id not in (select * from im_sub_categories(81)) @project_main_store_where;noquote@" 
    };
    projectMainStore.load({
	callback: function() {
            console.log('PO.store.project.ProjectMainStore: loaded');
        }
    });


});



</script>
