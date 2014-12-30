<master>
<property name="title">@page_title@</property>
<property name="main_navbar_label">@main_navbar_label@</property>
<property name="sub_navbar">@sub_navbar;noquote@</property>
<property name="left_navbar">@left_navbar_html;noquote@</property>

<table>
<tr><td>
<div id="resource_level_editor_div" style="overflow: hidden; position:absolute; width:100%; height:100%; bgcolo=red;"></div>
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
    autoLoad:			false,
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
        'assigned_resources',			// Number of full-time resources being a member of this CC
        'available_days',			// Array with J -> available days, starting with start_date
        'assigned_days',			// Array with J -> assigned days, starting with start_date
        'sprite_group'				// Sprite group representing the cost center bar
    ]
});

Ext.define('PO.store.resource_management.CostCenterResourceLoadStore', {
    extend:			'Ext.data.Store',
    storeId:			'costCenterResourceLoadStore',
    model: 			'PO.model.resource_management.CostCenterResourceLoadModel',
    remoteFilter:		true,			// Do not filter on the Sencha side
    autoLoad:			false,
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
    },

    /**
     * Custom load function that accepts a ProjectResourceLoadStore
     * as a parameter with the current start- and end dates of the
     * included projects, overriding the information stored in the
     * ]po[ database.
     */
    loadWithOffset: function(resourceLevelingEditor, projectStore, callback) {
        var me = this;
        console.log('PO.store.resource_management.CostCenterResourceLoadStore.loadWithOffset: starting');
        console.log(this);

        var proxy = this.getProxy();
        proxy.extraParams = {
            format:             'json',
            granularity:	'@report_granularity@',				// 'week' or 'day'
            report_start_date:	resourceLevelingEditor.axisStartDate.toISOString().substring(0,10),		// When to start
            report_end_date:	resourceLevelingEditor.axisEndDate.toISOString().substring(0,10)			// when to end
        };

        // Write the simulation start- and end dates as parameters to the store
        // As a result we will get the resource load with moved projects
        projectStore.each(function(model) {
            var projectId = model.get('project_id');
            var startDate = model.get('start_date').substring(0,10);
            var endDate = model.get('end_date').substring(0,10);
            proxy.extraParams['start_date.'+projectId] = startDate;
            proxy.extraParams['end_date.'+projectId] = endDate;
        });

        this.load(callback);
        console.log('PO.store.resource_management.CostCenterResourceLoadStore.loadWithOffset: finished');
    }
});



/**
 * Like a chart Series, displays a list of projects
 * using Gantt bars.
 */
Ext.define('PO.view.resource_management.ResourceLevelingEditor', {

    extend: 'Ext.draw.Component',

    requires: [
        'Ext.draw.Component',
        'Ext.draw.Surface',
        'Ext.layout.component.Draw'
    ],

    // surface						// Inherited from draw.Component

    debug: 1,
    granularity: '@report_granularity@',		// 'week' or 'day' currently
    granularityWorkDays: 1,				// 1 for daily interval, 5 for weekly

    projectPanel: null,					// Needs to be set during init

    dndBasePoint: null,					// Drag-and-drop starting point
    dndBaseSprite: null,				// DnD sprite being draged
    dndShadowSprite: null,				// DnD shadow generated for BaseSprite

    barHeight: 0,
    barStartHash: {},   				// Hash array from object_ids -> Start/end point
    barEndHash: {},   					// Hash array from object_ids -> Start/end point
    taskModelHash: {},

    // Start of the date axis
    axisStartTime: 0,
    axisStartX: 0,
    axisEndTime: 0,
    axisEndX: 290,					// End of the date axis
    axisHeight: 20,					// Height of each of the two axis levels
    axisScale: 'month',					// Default scale for the time axis

    // Size of the Gantt diagram
    ganttWidth: 1500,
    ganttHeight: 300,

    reportStartDate: null,				// Needs to be set during init
    reportEndDate: null,				// Needs to be set during init

    projectMainStore: null,				// Needs to be set during init
    projectResourceLoadStore: null,			// Needs to be set during init
    costCenterResourceLoadStore: null,			// Needs to be set during init

    projectGrid: null,					// Needs to be set during init
    costCenterGrid: null,				// Needs to be set during init

    /**
     * Starts the main editor panel as the right-hand side
     * of a project grid and a cost center grid for the departments
     * of the resources used in the projects.
     */
    initComponent: function() {
        var me = this;
        this.callParent(arguments);

        me.dndBasePoint = null;				// Drag-and-drop starting point
        me.dndBaseSprite = null;			// DnD sprite being draged
        me.dndShadowSprite = null;			// DnD shadow generated for BaseSprite

        me.barHeight = 15;
        me.barStartHash = {};     			// Hash array from object_ids -> Start/end point
        me.barEndHash = {};     			// Hash array from object_ids -> Start/end point
        me.taskModelHash = {};

        var items = me.surface;

        // Drag & Drop on the "surface"
        me.on({
            'mousedown': me.onMouseDown,
            'mouseup': me.onMouseUp,
            'mouseleave': me.onMouseUp,
            'mousemove': me.onMouseMove,
            'scope': this
        });

        // Catch the moment when the "view" of the CostCenter grid
        // is ready in order to draw the GanttBars for the first time.
        // The view seems to take a while...
        me.costCenterGrid.on({
            'viewready': me.onProjectGridViewReady,
            'sortchange': me.onProjectGridSelectionChange,
            'scope': this
        });

        // Redraw Cost Center load whenever the store has new data
        me.costCenterResourceLoadStore.on({
            'load': me.onCostCenterResourceLoadStoreLoad,
            'scope': this
        });

        me.projectGrid.on({
            'selectionchange': me.onProjectGridSelectionChange,
            'sortchange': me.onProjectGridSelectionChange,
            'scope': this
        });

        // Determine the maximum and minimum date for the horizontal axis
        me.axisEndTime = new Date('2000-01-01').getTime();
        me.axisStartTime = new Date('2099-12-31').getTime();
        me.projectResourceLoadStore.each(function(model) {
            var startTime = new Date(model.get('start_date')).getTime();
            var endTime = new Date(model.get('end_date')).getTime();
            if (startTime < me.axisStartTime) { me.axisStartTime = startTime; }
            if (endTime > me.axisEndTime) { me.axisEndTime = endTime; }
        });

        me.axisStartDate = me.prevMonth(new Date(me.axisStartTime));
        me.axisEndDate = me.nextMonth(new Date(me.axisEndTime));

        // Granularity
        switch(me.granularity) {
        case 'week':
            me.granularityWorkDays = 5;
            break;
        case 'day':
            me.granularityWorkDays = 1;
            break;
        default:
            alert('Undefined granularity: '+me.granularity);
        }


    },

    /**
     * The list of projects is (finally...) ready to be displayed.
     * We need to wait until this one-time event in in order to
     * set the width of the surface and to perform the first redraw().
     */
    onProjectGridViewReady: function() {
        var me = this;
        console.log('PO.class.GanttDrawComponent.onProjectGridViewReady');
        me.surface.setSize(1500, me.surface.height);
        
        me.costCenterResourceLoadStore.loadWithOffset(me, me.projectResourceLoadStore, {
            callback: function() {
                console.log('PO.store.resource_management.CostCenterResourceLoadStore: loaded with parameters');
            }
        });

        var selModel = me.projectGrid.getSelectionModel();
        selModel.selectAll(true);
        me.redraw();
    },

    onProjectGridSelectionChange: function() {
        var me = this;
        console.log('PO.class.GanttDrawComponent.onProjectGridSelectionChange');
        me.redraw();
    },

    /**
     * New data have arrived about the CostCenter load.
     * Redraw the CC bars
     */
    onCostCenterResourceLoadStoreLoad: function() {
        var me = this;
        console.log('PO.class.GanttDrawComponent.onCostCenterResourceLoadStoreLoad');
        me.redraw();
    },

    /**
     * Move the project forward or backward in time.
     * This function is called by onMouseUp as a
     * successful "drop" action of a drag-and-drop.
     */
    onProjectMove: function(baseSprite, projectModel, xDiff) {
        var me = this;
        console.log('PO.class.GanttDrawComponent.onProjectMove: '+projectModel.get('id') + ', ' + xDiff);

        var bBox = me.dndBaseSprite.getBBox();
        var diffTime = Math.floor(1.0 * xDiff * (me.axisEndTime - me.axisStartTime) / (me.axisEndX - me.axisStartX));

        var startTime = new Date(projectModel.get('start_date')).getTime();
        var endTime = new Date(projectModel.get('end_date')).getTime();

        startTime = startTime + diffTime;
        endTime = endTime + diffTime;

        var startDate = new Date(startTime);
        var endDate = new Date(endTime);

        projectModel.set('start_date', startDate.toISOString());
        projectModel.set('end_date', endDate.toISOString());

        me.redraw();
    },



    /**
     * The user starts a drag operation.
     */
    onMouseDown: function(e) {
        var me = this;
        var point = me.getMousePoint(e);

        // Now using offsetX/offsetY instead of getXY()
        var baseSprite = me.getSpriteForPoint(point);
        console.log('PO.class.GanttDrawComponent.onMouseDown: '+point+' -> ' + baseSprite);
        if (baseSprite == null) { return; }

        var bBox = baseSprite.getBBox();
        var surface = me.surface;
        var spriteShadow = surface.add({
            type: 'rect',
            x: bBox.x,
            y: bBox.y,
            width: bBox.width,
            height: bBox.height,
            radius: 3,
            stroke: 'red',
            'stroke-width': 1
        }).show(true);

        me.dndBasePoint = point;
        me.dndBaseSprite = baseSprite;
        me.dndShadowSprite = spriteShadow;
    },

    /**
     * "Translate" the entire diagram when dragging around.
     */
    onMouseMove: function(e) {
        var me = this;
        if (me.dndBasePoint == null) { return; }				// Only if we are dragging
        var point = me.getMousePoint(e);

        me.dndShadowSprite.setAttributes({
            translate: {
                x: point[0] - me.dndBasePoint[0],
                y: 0
            }
        }, true);

//        if (me.debug) { console.log('PO.class.GanttDrawComponent.onMouseMove: '+point); }
    },

    onMouseUp: function(e) {
        var me = this;
        if (me.dndBasePoint == null) { return; }
        var point = me.getMousePoint(e);
        console.log('PO.class.GanttDrawComponent.onMouseUp: '+point);

        // Reset the offset when just clicking
        console.log('oldX='+me.dndBasePoint[0]+', newX='+point[0]);
        var xDiff = point[0] - me.dndBasePoint[0];
        if (0 == xDiff) {
            // Single click - nothing
        } else {
            // Tell the project that it has been moved by some pixels
            var projectModel = me.dndBaseSprite.model;
            me.onProjectMove(me.dndBaseSprite, projectModel, xDiff);
        }

        me.dndBasePoint = null;					// Stop dragging
        me.dndBaseSprite = null;
        me.dndShadowSprite.destroy();
        me.dndShadowSprite = null;
    },

    getMousePoint: function(mouseEvent) {
        var point = [mouseEvent.browserEvent.offsetX, mouseEvent.browserEvent.offsetY];		// Coordinates relative to surface (why?)
        return point;
    },

    /**
     * Returns the item for a x/y mouse coordinate
     */
    getSpriteForPoint: function(point) {
        var me = this,
            x = point[0],
            y = point[1];

        if (y <= me.axisHeight) { return 'axis1'; }
        if (y > me.axisHeight && y <= 2*me.axisHeight) { return 'axis2'; }

        var items = me.surface.items.items;
        for (var i = 0, ln = items.length; i < ln; i++) {
            if (items[i] && me.isSpriteInPoint(x, y, items[i], i)) {
                return items[i];
            }
        }
        return null;
    },

    /**
     * Checks for mouse inside the BBox
     */
    isSpriteInPoint: function(x, y, sprite, i) {
        var spriteType = sprite.type;
        var bbox = sprite.getBBox();
        return bbox.x <= x && bbox.y <= y
            && (bbox.x + bbox.width) >= x
            && (bbox.y + bbox.height) >= y;
    },


    /**
     * Draw all Gantt bars
     */
    redraw: function() {
        console.log('PO.ResourceLevelingEditor.redraw: Starting');
        var me = this;
        me.surface.removeAll();
	me.drawAxis();					// Draw the top axis

        // Draw project bars
        var projectStore = me.projectResourceLoadStore;
        var projectGridView = me.projectGrid.getView();		// The "view" for the GridPanel, containing HTML elements
        var projectSelModel = me.projectGrid.getSelectionModel();
        projectStore.each(function(model) {
            var viewNode = projectGridView.getNode(model);	// DIV with project name on the ProjectGrid for Y coo
            if (viewNode == null) { return; }			// hidden nodes/models don't have a viewNode
            if (!projectSelModel.isSelected(model)) {
                return;
            }
            me.drawProjectBar(model, viewNode);
        });

        // Draw CostCenter bars
        var costCenterStore = me.costCenterResourceLoadStore;
        var costCenterGridView = me.costCenterGrid.getView();	// The "view" for the GridPanel, containing HTML elements
        costCenterStore.each(function(model) {
            var viewNode = costCenterGridView.getNode(model);	// DIV with costCenter name on the CostCenterGrid for Y coo
            if (viewNode == null) { return; }			// hidden nodes/models don't have a viewNode
            me.drawCostCenterBar(model, viewNode);
        });

        console.log('PO.ResourceLevelingEditor.redraw: Finished');
    },


    /**
     * Draw a single bar for a project or task
     */
    drawProjectBar: function(project, viewNode) {
        var me = this;
        if (me.debug) { console.log('PO.class.GanttDrawComponent.drawProjectBar: Starting'); }
        var projectGridView = me.projectGrid.getView();			// The "view" for the GridPanel, containing HTML elements
        var surface = me.surface;
        var panelY = me.projectGrid.getY() - 30;

        var project_name = project.get('project_name');
        var start_date = project.get('start_date').substring(0,10);
        var end_date = project.get('end_date').substring(0,10);
        var startTime = new Date(start_date).getTime();
        var endTime = new Date(end_date).getTime();

        // Used for grouping all sprites into one group
        var spriteGroup = Ext.create('Ext.draw.CompositeSprite', {
            surface: surface,
            autoDestroy: true
        });

        var projectY = projectGridView.getNode(project).getBoundingClientRect().top;
        var x = me.date2x(startTime);
        var y = projectY - panelY;
        var w = Math.floor( me.ganttWidth * (endTime - startTime) / (me.axisEndTime - me.axisStartTime));
        var h = me.barHeight; 							// Height of the bars
        var d = Math.floor(h / 2.0) + 1;    				// Size of the indent of the super-project bar

        var spriteBar = surface.add({
            type: 'rect',
            x: x,
            y: y,
            width: w,
            height: h,
            radius: 3,
            fill: 'url(#gradientId)',
            stroke: 'blue',
            'stroke-width': 0.3,
            listeners: {						// Highlight the sprite on mouse-over
                mouseover: function() { this.animate({duration: 500, to: {'stroke-width': 1.0}}); },
                mouseout: function()  { this.animate({duration: 500, to: {'stroke-width': 0.3}}); }
            }
        }).show(true);

        spriteBar.model = project;					// Store the task information for the sprite
        spriteGroup.add(spriteBar);

        // Store the start and end points of the bar
        var id = project.get('id');
        me.barStartHash[id] = [x,y];					// Move the start of the bar 5px to the right
        me.barEndHash[id] = [x+w, y+h];					// End of the bar is in the middle of the bar

        if (me.debug) { console.log('PO.class.GanttDrawComponent.drawProjectBar: Finished'); }
    },


    /**
     * Draw a date axis on the top of the diagram
     */
    drawAxis: function() {
        var me = this;
        if (me.debug) { console.log('PO.class.GanttDrawComponent.drawAxis: Starting'); }

	// Draw Yearly blocks
	var startYear = new Date(me.axisStartTime).getFullYear();
	var endYear = new Date(me.axisEndTime).getFullYear();
	for (var year = startYear; year <= endYear; year++) {
            var x = me.date2x(new Date(year+"-01-01"));
            var xEnd = me.date2x(new Date(year+"-12-31"));
            var w = xEnd - x;
            var y = 0;
            var h = me.barHeight; 							// Height of the bars
	    
            var axisBar = me.surface.add({
		type: 'rect',
		x: x,
		y: y,
		width: w,
		height: h,
		fill: '#cdf',               // '#ace'
		stroke: 'grey'
            }).show(true);

            var axisText = me.surface.add({
		type: 'text',
		text: ""+year,
		x: x + 2,
		y: y + (me.barHeight / 2),
		fill: '#000',
		font: "10px Arial"
            }).show(true);
	}

	// Draw Yearly blocks
	var startMonth = new Date(me.axisStartTime).getMonth();
	var endMonth = new Date(me.axisEndTime).getMonth();
	var yea = startYear;
	var mon = startMonth;
	while (yea * 100 + mon <= endYear * 100 + endMonth) {

	    var xEndMon = mon+1;
	    var xEndYea = yea;
	    if (xEndMon > 11) { xEndMon = 0; xEndYea = xEndYea + 1; }

            var x = me.date2x(new Date(yea+"-"+(mon+1)+"-01"));
            var xEnd = me.date2x(new Date(xEndYea+"-"+(xEndMon+1)+"-01"));
            var w = xEnd - x;
            var y = me.barHeight;
            var h = me.barHeight; 							// Height of the bars
	    
            var axisBar = me.surface.add({
		type: 'rect',
		x: x,
		y: y,
		width: w,
		height: h,
		fill: '#cdf',               // '#ace'
		stroke: 'grey'
            }).show(true);

            var axisText = me.surface.add({
		type: 'text',
		text: ""+(mon+1),
		x: x + 2,
		y: y + (me.barHeight / 2),
		fill: '#000',
		font: "9px Arial"
            }).show(true);

	    mon = mon + 1;
	    if (mon > 11) {
		mon = 0;
		yea = yea + 1;
	    }
	}

        if (me.debug) { console.log('PO.class.GanttDrawComponent.drawAxis: Finished'); }
    },



    /**
     * Draw a single bar for a cost center
     */
    drawCostCenterBar: function(costCenter, viewNode) {
        var me = this;
        if (me.debug) { console.log('PO.class.GanttDrawComponent.drawCostCenterBar: Starting'); }
        var costCenterGridView = me.costCenterGrid.getView();			// The "view" for the GridPanel, containing HTML elements
        var surface = me.surface;

        var start_date = me.axisStartDate.toISOString().substring(0,10);
        var end_date = me.axisEndDate.toISOString().substring(0,10);
        var startTime = new Date(start_date).getTime();
        var endTime = new Date(end_date).getTime();

        // Used for grouping all sprites into one group
        var spriteGroup = Ext.create('Ext.draw.CompositeSprite', {
            surface: surface,
            autoDestroy: true
        });

        // Calculate the Y position for the bar, depending on
        var costCenterPanelY = me.costCenterGrid.getBox().top;
        var projectPanelY = me.projectGrid.getBox().top;
        var surfacePanelY = me.getBox().top;
        var costCenterDivY = costCenterGridView.getNode(costCenter).getBoundingClientRect().top;

        var y = (costCenterPanelY - surfacePanelY) + (costCenterDivY - costCenterPanelY) + 5;

        var x = me.date2x(startTime);
        var w = Math.floor( me.ganttWidth * (endTime - startTime) / (me.axisEndTime - me.axisStartTime));
        var h = me.barHeight; 							// Height of the bars
        var d = Math.floor(h / 2.0) + 1;    				// Size of the indent of the super-costCenter bar

        var spriteBar = surface.add({
            type: 'rect',
            x: x,
            y: y,
            width: w,
            height: h,
            radius: 3,
            fill: 'url(#gradientId)',
            stroke: 'blue',
            'stroke-width': 0.3,
            listeners: {						// Highlight the sprite on mouse-over
                mouseover: function() { this.animate({duration: 500, to: {'stroke-width': 1.0}}); },
                mouseout: function()  { this.animate({duration: 500, to: {'stroke-width': 0.3}}); }
            }
        }).show(true);

        spriteBar.model = costCenter;					// Store the task information for the sprite
        spriteGroup.add(spriteBar);

        // Store the start and end points of the bar
        var id = costCenter.get('id');
        me.barStartHash[id] = [x,y];					// Move the start of the bar 5px to the right
        me.barEndHash[id] = [x+w, y+h];					// End of the bar is in the middle of the bar

        // -----------------------------------------------------------
        // Draw availability percentage
        //
        var availableDays = costCenter.get('available_days');
        var len = availableDays.length;
        var weekStartDate = new Date(me.axisStartDate);
        var weekStartX, weekEndX, weekY, weekEndDate;
        weekStartX = me.date2x(weekStartDate);
        weekY = Math.floor(y + availableDays[0]);
        var path = "M"+weekStartX+" "+weekY;                            // Start point for path
        // ToDo: Reset startDate to the start of the start of the respective week
        for (var i = 0; i < len; i++) {
            weekEndDate = new Date(weekStartDate.getTime() + 1000.0 * 3600 * 24 * 7);
            // Convert start and end date of the interval to x coordinates
            weekStartX = me.date2x(weekStartDate);
            weekEndX = me.date2x(weekEndDate);

            var actualAvailableDaysPerInterval = availableDays[i];
            var daysPerInterval = me.granularityWorkDays * costCenter.get('assigned_resources');
            var costCenterLoadPercentage = 100.0 * actualAvailableDaysPerInterval / daysPerInterval

            weekY = Math.floor(y + me.barHeight * (1 - costCenterLoadPercentage / 100.0));
            path = path + " L" + weekEndX + " " + weekY;
            // The former end of the week becomes the start for the next week
            weekStartDate = weekEndDate;
        }

        var spritePath = surface.add({
            type: 'path',
            stroke: 'blue',
            'stroke-width': 1,
            path: path
        }).show(true);
        spriteGroup.add(spritePath);



        // -----------------------------------------------------------
        // Draw assignment percentage
        //
        var assignedDays = costCenter.get('assigned_days');
        var len = assignedDays.length;
        var weekStartDate = new Date(me.axisStartDate);
        var weekStartX, weekEndX, weekY, weekEndDate;
        weekStartX = me.date2x(weekStartDate);
        weekY = Math.floor(y + assignedDays[0]);
        var path = "M"+weekStartX+" "+weekY;                            // Start point for path
        // ToDo: Reset startDate to the start of the start of the respective week
        for (var i = 0; i < len; i++) {
            weekEndDate = new Date(weekStartDate.getTime() + 1000.0 * 3600 * 24 * 7);
            // Convert start and end date of the interval to x coordinates
            weekStartX = me.date2x(weekStartDate);
            weekEndX = me.date2x(weekEndDate);

            var actualAssignedDaysPerInterval = assignedDays[i];
            var daysPerInterval = me.granularityWorkDays * costCenter.get('assigned_resources');
            var costCenterLoadPercentage = 100.0 * actualAssignedDaysPerInterval / daysPerInterval

            weekY = Math.floor(y + me.barHeight * (1 - costCenterLoadPercentage / 100.0));
            path = path + " L" + weekEndX + " " + weekY;
            // The former end of the week becomes the start for the next week
            weekStartDate = weekEndDate;
        }

        var spritePath = surface.add({
            type: 'path',
            stroke: 'red',
            'stroke-width': 1,
            path: path
        }).show(true);
        spriteGroup.add(spritePath);



        if (me.debug) { console.log('PO.class.GanttDrawComponent.drawCostCenterBar: Finished'); }
    },

    /**
     * Convert a date object into the corresponding X coordinate.
     * Returns NULL if the date is out of the range.
     */
    date2x: function(date) {
        var me = this;

        var t = typeof date;
        var dateMilliJulian = 0;

        if ("number" == t) {
            dateMilliJulian = date;
        } else if ("object" == t) {
            if (date instanceof Date) {
                dateMilliJulian = date.getTime();
            } else {
                console.error('GanttDrawComponent.date2x: Unknown object type for date argument:'+t);
            }
        } else {
            console.error('GanttDrawComponent.date2x: Unknown type for date argument:'+t);
        }

        var axisWidth = me.axisEndX - me.axisStartX;
        var x = me.axisStartX + Math.floor(1.0 * axisWidth * (1.0 * dateMilliJulian - me.axisStartTime) / (1.0 * me.axisEndTime - me.axisStartTime));
        if (x < 0) { x = 0; }

        return x;
    },


    /**
     * Advance a date to the 1st of the next month
     */
    nextMonth: function(date) {
        var result;
        if (date.getMonth() == 11) {
            result = new Date(date.getFullYear() + 1, 0, 1);
        } else {
            result = new Date(date.getFullYear(), date.getMonth() + 1, 1);
        }
        return result;
    },

    /**
     * Advance a date to the 1st of the prev month
     */
    prevMonth: function(date) {
        var result;
        if (date.getMonth() == 1) {
            result = new Date(date.getFullYear() - 1, 12, 1);
        } else {
            result = new Date(date.getFullYear(), date.getMonth() - 1, 1);
        }
        return result;
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

    var renderDiv = Ext.get('resource_level_editor_div');

    var projectGridHeight = listProjectsAddOnHeight + listCellHeight * numProjects;
    var projectGridSelectionModel = Ext.create('Ext.selection.CheckboxModel');
    var projectGrid = Ext.create('Ext.grid.Panel', {
        title: false,
        region:'center',
        store: 'projectResourceLoadStore',
        height: projectGridHeight,
	scroll: false,
        selModel: projectGridSelectionModel,
        columns: [{
            text: 'Projects',
            dataIndex: 'project_name',
            flex: 1
        },{
            text: 'Start',
            dataIndex: 'start_date',
            width: 80
        },{
            text: 'End',
            dataIndex: 'end_date',
            width: 80,
	    hidden: true
        }],
        shrinkWrap: true
    });

    var costCenterGridHeight = listCostCenterAddOnHeight + listCellHeight * numDepts;
    var costCenterGridSelectionModel = Ext.create('Ext.selection.CheckboxModel');
    var costCenterGrid = Ext.create('Ext.grid.Panel', {
        title: '',
        region:'south',
        height: costCenterGridHeight,
        store: 'costCenterResourceLoadStore',
        // selModel: costCenterGridSelectionModel,                     // We don't need to select departments
        columns: [{
            text: 'Departments',
            dataIndex: 'cost_center_name',
            flex: 1
        },{
            text: 'Resources',
            dataIndex: 'assigned_resources',
            width: 70
        }],
        shrinkWrap: true
    });


    // Drawing area for for Gantt Bars
    var resourceLevelingEditor = Ext.create('PO.view.resource_management.ResourceLevelingEditor', {
        region: 'center',
        viewBox: false,
        gradients: [{
            id: 'gradientId',
            angle: 66,
            stops: {
                0: { color: '#cdf' },
                100: { color: '#ace' }
            }
        }, {
            id: 'gradientId2',
            angle: 0,
            stops: {
                0: { color: '#590' },
                20: { color: '#599' },
                100: { color: '#ddd' }
            }
        }],

        overflowX: 'scroll',				// Allows for horizontal scrolling, but not vertical
        scrollFlags: {x: true},

        projectMainStore: projectMainStore,
        projectResourceLoadStore: projectResourceLoadStore,
        costCenterResourceLoadStore: costCenterResourceLoadStore,

        projectGrid: projectGrid,
        costCenterGrid: costCenterGrid,

        reportStartDate: new Date('@report_start_date@'),
        reportEndDate: new Date('@report_end_date@')
    });


    /*
     * Main Panel that contains the three other panels
     * (projects, departments and gantt bars)
     */
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
            resourceLevelingEditor
        ],
        renderTo: renderDiv
    });

    var onWindowResize = function () {
        // ToDo: Try to find out if there is another onWindowResize Event waiting
        var borderPanelHeight = (listProjectsAddOnHeight + listCostCenterAddOnHeight) + listCellHeight * numProjectsDepts;
        var width = Ext.getBody().getViewSize().width - 350;
        var surface = resourceLevelingEditor.surface;
        borderPanel.setSize(width, borderPanelHeight);

        surface.setSize(1500, surface.height);
        resourceLevelingEditor.redraw();
    };

    Ext.EventManager.onWindowResize(onWindowResize);

};



Ext.onReady(function() {
    Ext.QuickTips.init();

    // Show splash screen while the stores are loading
    var renderDiv = Ext.get('resource_level_editor_div');
    var splashScreen = renderDiv.mask('Loading data');
    var task = new Ext.util.DelayedTask(function() {
        splashScreen.fadeOut({duration: 100, remove: true});			// fade out the body mask
        splashScreen.next().fadeOut({duration: 100, remove: true});		// fade out the message
    });

    var projectMainStore = Ext.create('PO.store.project.ProjectMainStore');
    var projectResourceLoadStore = Ext.create('PO.store.resource_management.ProjectResourceLoadStore');
    var costCenterResourceLoadStore = Ext.create('PO.store.resource_management.CostCenterResourceLoadStore');

    var coo = Ext.create('PO.controller.StoreLoadCoordinator', {
        debug: 0,
        stores: [
            'projectMainStore',
            'projectResourceLoadStore'
        ],
        listeners: {
            load: function() {
                // Launch the actual application.
                console.log('PO.controller.StoreLoadCoordinator: launching Application');
                task.delay(100);						// Fade out the splash screen
                launchApplication();						// launch the actual application
            }
        }
    });

    // Load only open main projects that are not closed.
    projectMainStore.getProxy().extraParams = {
        format: "json",
        query: "parent_id is NULL and project_type_id not in (select * from im_sub_categories(81)) @project_main_store_where;noquote@"
    };
    projectMainStore.load({
        callback: function() { console.log('PO.store.project.ProjectMainStore: loaded'); }
    });

    projectResourceLoadStore.load({
        callback: function() {
            console.log('PO.store.resource_management.ProjectResourceLoadStore: loaded');
        }
    });

    // Load CC load with default parameters in order to get the list of CCs.
    costCenterResourceLoadStore.load({
        callback: function() {
            console.log('PO.store.resource_management.CostCenterResourceLoadStore: loaded');
        }
    });

});

</script>
