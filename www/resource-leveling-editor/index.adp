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

var report_start_date = '@report_start_date@'.substring(0,10);
var report_end_date = '@report_end_date@'.substring(0,10);
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
        'assigned_days',			// Array with J -> % assignments per day, starting with start_date
        'max_assigned_days',			// Maximum of assignment for a single unit (day or week)
        'projectGridSelected',			// Did the user check the project in the ProjectGrid?
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
    model:			'PO.model.resource_management.ProjectResourceLoadModel',
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
        'assigned_days'			// Array with J -> assigned days, starting with start_date
    ]
});

Ext.define('PO.store.resource_management.CostCenterResourceLoadStore', {
    extend:			'Ext.data.Store',
    storeId:			'costCenterResourceLoadStore',
    model:			'PO.model.resource_management.CostCenterResourceLoadModel',
    remoteFilter:		true,			// Do not filter on the Sencha side
    autoLoad:			false,
    pageSize:			100000,			// Load all cost_centers, no matter what size(?)
    proxy: {
        type:			'rest',			// Standard ]po[ REST interface for loading
        url:			'/intranet-resource-management/resource-leveling-editor/cost-center-resource-availability.json',
        timeout:		300000,
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
    loadWithProjectData: function(projectStore, callback) {
        var me = this;
        console.log('PO.store.resource_management.CostCenterResourceLoadStore.loadWithProjectData: starting');
        console.log(this);

        var proxy = this.getProxy();
        proxy.extraParams = {
            format:             'json',
            granularity:	'@report_granularity@',				// 'week' or 'day'
            report_start_date:	report_start_date,				// When to start
            report_end_date:	report_end_date					// when to end
        };

        // Write the simulation start- and end dates as parameters to the store
        // As a result we will get the resource load with moved projects
        projectStore.each(function(model) {
            var enabled = model.get('projectGridSelected');
            if (0 === enabled) {
                return;
            }

            var projectId = model.get('project_id');
            var startDate = model.get('start_date').substring(0,10);
            var endDate = model.get('end_date').substring(0,10);
            proxy.extraParams['start_date.'+projectId] = startDate;
            proxy.extraParams['end_date.'+projectId] = endDate;
        });

        this.load(callback);
        console.log('PO.store.resource_management.CostCenterResourceLoadStore.loadWithProjectData: finished');
    }
});






/********************************************************
 * Base class for various types of graphical editors using
 * Gantt bars including: GanttEditor, Project part of the
 * ResourceLevelEditor and the Department part of the
 * ResourceLevelEditor.
 */
Ext.define('PO.view.resource_management.AbstractGanttEditor', {

    extend: 'Ext.draw.Component',

    requires: [
        'Ext.draw.Component',
        'Ext.draw.Surface',
        'Ext.layout.component.Draw'
    ],

    // surface						// Inherited from draw.Component
    debug: 0,

    objectPanel: null,					// Set during init: Reference to grid or tree panel at the left
    objectStore: null,					// Set during init: Reference to store (tree or flat)
    preferenceStore: null,				// Set during init: Reference to store with user preferences

    // Drag-and-drop state variables
    dndEnabled: true,					// Enable drag-and-drop at all?
    dndBasePoint: null,					// Drag-and-drop starting point
    dndBaseSprite: null,				// DnD sprite being draged
    dndShadowSprite: null,				// DnD shadow generated for BaseSprite

    // Size of the Gantt diagram
    ganttSurfaceWidth: 1500,
    ganttSurfaceHeight: 300,
    ganttBarHeight: 15,

    // Start of the date axis
    reportStartDate: null,				// Needs to be set during init
    reportEndDate: null,				// Needs to be set during init
    axisStartDate: null,
    axisEndDate: null,
    axisStartX: 0,
    axisEndX: 0,					// End of the axis. ToDo: Adapt to screen width
    axisHeight: 11,					// Height of each of the two axis levels
    axisScale: 'month',					// Default scale for the time axis

    granularity: '@report_granularity@',		// 'week' or 'day' currently
    granularityWorkDays: 1,				// 1 for daily interval, 5 for weekly

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

        me.axisStartX = 0;
        me.axisEndX = me.ganttSurfaceWidth;
        me.axisStartDate = me.reportStartDate;
        me.axisEndDate = me.reportEndDate;

        // New Event: Drag-and-Drop for a Gantt bar
        this.addEvents('objectdnd');

        // Drag & Drop on the "surface"
        me.on({
            'mousedown': me.onMouseDown,
            'mouseup': me.onMouseUp,
            'mouseleave': me.onMouseUp,
            'mousemove': me.onMouseMove,
            'scope': this
        });

    },

    /**
     * Get the Mouse position on the sufrace.
     * Returns Coordinates relative to surface (why?)
     */
    getMousePoint: function(mouseEvent) {
        var point = [mouseEvent.browserEvent.offsetX, mouseEvent.browserEvent.offsetY];
        return point;
    },

    /**
     * Drag-and-drop:
     * The user starts a drag operation.
     */
    onMouseDown: function(e) {
        var me = this;
        if (!me.dndEnabled) { return; }

        // Now using offsetX/offsetY instead of getXY()
        var point = me.getMousePoint(e);
        var baseSprite = me.getSpriteForPoint(point);
        console.log('PO.view.resource_management.AbstractGanttEditor.onMouseDown: '+point+' -> ' + baseSprite);
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
     * Drag-and-drop:
     * Move the shadow of the selected sprite according to mouse
     */
    onMouseMove: function(e) {
        var me = this;
        if (!me.dndEnabled) { return; }

        if (me.dndBasePoint == null) { return; }				// Only if we are dragging
        var point = me.getMousePoint(e);
        me.dndShadowSprite.setAttributes({
            translate: {
                x: point[0] - me.dndBasePoint[0],
                y: 0
            }
        }, true);
    },

    /**
     * Drag-and-drop:
     * End the DnD and call the function to update the underlying object
     */
    onMouseUp: function(e) {
        var me = this;
        if (!me.dndEnabled) { return; }

        if (me.dndBasePoint == null) { return; }
        var point = me.getMousePoint(e);
        console.log('PO.view.resource_management.AbstractGanttEditor.onMouseUp: '+point);

        // Reset the offset when just clicking
        var xDiff = point[0] - me.dndBasePoint[0];
        if (0 == xDiff) {
            // Single click - nothing
        } else {
            // Fire event in order to notify listerns about the move
            var model = me.dndBaseSprite.model;
            me.fireEvent('objectdnd', me.dndBaseSprite, model, xDiff);
        }

        me.dndBasePoint = null;					// Stop dragging
        me.dndBaseSprite = null;
        me.dndShadowSprite.destroy();
        me.dndShadowSprite = null;
    },

    /**
     * Returns the item for a x/y mouse coordinate
     */
    getSpriteForPoint: function(point) {
        var me = this,
            x = point[0],
            y = point[1];

        var result = [];

        if (y <= me.axisHeight) { return 'axis1'; }
        if (y > me.axisHeight && y <= 2*me.axisHeight) { return 'axis2'; }

        var items = me.surface.items.items;
        console.log('getSpriteForPoint: items.length='+items.length);

        for (var i = 0, ln = items.length; i < ln; i++) {
            var sprite = items[i];
            if (!sprite) continue;
            if ("rect" != sprite.type) continue;

            var bbox = sprite.getBBox();
            if (bbox.x > x) continue;
            if (bbox.y > y) continue;
            if (bbox.x + bbox.width < x) continue;
            if (bbox.y + bbox.height < y) continue;

            return sprite;
        }

        return null;
    },

    /**
     * Draw all Gantt bars
     */
    redraw: function() {
        console.log('PO.view.resource_management.AbstractGanttEditor.redraw: Needs to be overwritten');
        var me = this;
        me.surface.removeAll();
        me.drawAxis();							// Draw the top axis
    },

    /**
     * Calculate the Y-position of a Gantt bar,
     * based on the Y position of the project or CC
     * in the grid at the left.
     */
    calcGanttBarYPosition: function(model) {
        var me = this;
        var objectPanelView = me.objectPanel.getView();						// The "view" for the GridPanel, containing HTML elements
        var projectNodeHeight = objectPanelView.getNode(0).getBoundingClientRect().height;	// Height of a project node
        var projectYFirstProject = objectPanelView.getNode(0).getBoundingClientRect().top;	// Y position of the very first project
        var centerOffset = (projectNodeHeight - me.ganttBarHeight) / 2.0;			// Small offset in order to center Gantt
        var projectY = objectPanelView.getNode(model).getBoundingClientRect().top;		// Y position of current project
        var y = projectY - projectYFirstProject + 2 * me.axisHeight + centerOffset;
        return y;
    },


    /**
     * Draws a graph on a Gantt bar that consists of:
     * - ganttSprite is the actual sprite for the bar and defines the base coordinates
     * - graphArray is an array for the individual values
     * - maxGraphArray is the max value of the graphArray ("100%")
     * - startDate corresponds to ganttSprite.x
     * The graph will range between 0 (bottom of the Gantt bar) and
     * maxGraphArray (top of the Gantt bar).
     */
    graphOnGanttBar: function(ganttSprite, model, graphArray, maxGraphArray, spriteBarStartDate, colorConf, tooltipTemplate) {
        var me = this;
        var surface = me.surface;
        if (me.debug) { console.log('PO.view.resource_management.AbstractGanttEditor.graphOnGanttBar'); }

        // Add a -1 at the end of the graphArray, "-1" indicates the end of the array
        if (graphArray[graphArray.length-1] != -1) {
            graphArray.push(-1);
        }

        // Granularity
        var oneDayMilliseconds = 1000.0 * 3600 * 24 * 1.0;
        var intervalTimeMilliseconds;
        switch(me.granularity) {
        case 'week': intervalTimeMilliseconds = oneDayMilliseconds * 7.0; break;	// One week
        case 'day':  intervalTimeMilliseconds = oneDayMilliseconds * 1.0; break;	// One day
        default:     alert('Undefined granularity: '+me.granularity);
        }

        // Calculate the biggest element of the graphArray
        var i;
        var len = graphArray.length;
        if (null === maxGraphArray || 0.0 == maxGraphArray) {
            maxGraphArray = 0.0;
            for (i = 0; i < len; i++) {
                if (graphArray[i] > maxGraphArray) { maxGraphArray = graphArray[i]; };
            }
        }

        var spriteBarStartX = ganttSprite.x;
        var spriteBarEndX = ganttSprite.x + ganttSprite.width;
        var spriteBarBaseY = ganttSprite.y + ganttSprite.height;
        var spriteBarHeight = ganttSprite.height - 1;

        var intervalStartDate = spriteBarStartDate;
        var segmentStartDate = spriteBarStartDate;
        var intervalStartX =  me.date2x(intervalStartDate);
        var lastIntervalStartDate = spriteBarStartDate;
        var lastIntervalEndDate = new Date(spriteBarStartDate.getTime() + intervalTimeMilliseconds);

        var intervalY = Math.floor(spriteBarBaseY - (graphArray[0] / maxGraphArray) * spriteBarHeight) + 0.5;
        var lastIntervalY = intervalY;
        var intervalEndDate, intervalEndX;

        var path = "M" + intervalStartX + " " + intervalY;		// Start point for path

        var value = graphArray[0];
        var lastValue = graphArray[0];
        for (i = 0; i < len; i++) {
            value = graphArray[i];
            intervalY = Math.floor(spriteBarBaseY - (value / maxGraphArray) * spriteBarHeight) + 0.5;

            intervalEndDate = new Date(intervalStartDate.getTime() + intervalTimeMilliseconds);
            intervalEndX = me.date2x(intervalEndDate);
            if (intervalEndX > spriteBarEndX) { intervalEndX = spriteBarEndX; }		// Fix the last interval to stop at the bar

            if (lastIntervalY != intervalY) {
                // A new segment starts with a new Y coordinate
                // Finish off the previous segment.
                path = path + " L" + intervalStartX + " " + lastIntervalY;

                if (intervalStartX < spriteBarEndX) {
                    path = path + " L" + intervalStartX + " " + intervalY;
                }
                var spritePath = surface.add({
                    type: 'path',
                    stroke: colorConf,
                    'stroke-width': 2,
                    path: path
                }).show(true);

                // Format a ToolTip based on the provided template,
                // the values of the current segment 
                // and the model of the object shown.
                if (undefined !== tooltipTemplate) {
                    var data = {};
                    for (var v in model.data) { data[v] = model.data[v]; }
                    data['value'] = lastValue;
                    data['maxValue'] = maxGraphArray;
                    data['startDate'] = segmentStartDate.toISOString().substring(0,10);
                    data['endDate'] = new Date(lastIntervalEndDate.getTime() - oneDayMilliseconds).toISOString().substring(0,10);
                    var tip = Ext.create("Ext.tip.ToolTip", {
                        target: spritePath.el,
                        width: 250,
                        html: tooltipTemplate.apply(data)                 // Replace {0} in the template with value
                    });
                }

                path = "M" + intervalStartX + " " + intervalY;              // Start point for path

                // A new segment will start here.
                segmentStartDate = intervalStartDate;

            } else {
                // Nothing - still on the same Y coordinates
            }

            // Remember the values of the last iteration
            lastValue = value;
            lastIntervalY = intervalY;
            lastIntervalStartDate = intervalStartDate;
            lastIntervalEndDate = intervalEndDate;

            // The former end of the interval becomes the start for the next interval
            intervalStartDate = intervalEndDate;
            intervalStartX = intervalEndX;

        }
    },

    /**
     * Draw a date axis on the top of the diagram
     */
    drawAxis: function() {
        var me = this;
        if (me.debug) { console.log('PO.view.resource_management.AbstractGanttEditor.drawAxis: Starting'); }
        me.drawAxisYear();
        me.drawAxisMonth();
        if (me.debug) { console.log('PO.view.resource_management.AbstractGanttEditor.drawAxis: Finished'); }
    },

    /**
     * Draw a date axis on the top of the diagram
     */
    drawAxisYear: function() {
        var me = this;
        if (me.debug) { console.log('PO.view.resource_management.AbstractGanttEditor.drawAxisYear: Starting'); }

        // Draw Yearly blocks
        var startYear = me.axisStartDate.getFullYear();
        var endYear = me.axisEndDate.getFullYear();
        var y = 0;
        var h = me.axisHeight;					// Height of the bars

        for (var year = startYear; year <= endYear; year++) {
            var x = me.date2x(new Date(year+"-01-01"));
            var xEnd = me.date2x(new Date((year+1)+"-01-01"));
            var w = xEnd - x;

            var axisBar = me.surface.add({
                type: 'rect',
                x: x,
                y: y,
                width: w,
                height: h,
                fill: '#cdf',						// '#ace'
                stroke: 'grey'
            }).show(true);

           var axisText = me.surface.add({
                type: 'text',
                text: ""+year,
                x: x + 2,
                y: y + (me.axisHeight / 2),
                fill: '#000',
                font: "10px Arial"
            }).show(true);
        }
        if (me.debug) { console.log('PO.view.resource_management.AbstractGanttEditor.drawAxisYear: Finished'); }
    },

    /**
     * Draw a date axis on the top of the diagram
     */
    drawAxisMonth: function() {
        var me = this;
        if (me.debug) { console.log('PO.view.resource_management.AbstractGanttEditor.drawAxisMonth: Starting'); }

        // Draw monthly blocks
        var startYear = me.axisStartDate.getFullYear();
        var endYear = me.axisEndDate.getFullYear();
        var startMonth = me.axisStartDate.getMonth();
        var endMonth = me.axisEndDate.getMonth();
        var yea = startYear;
        var mon = startMonth;

        var y = me.axisHeight;
        var h = me.axisHeight;						// Height of the bars

        while (yea * 100 + mon <= endYear * 100 + endMonth) {

            var xEndMon = mon+1;
            var xEndYea = yea;
            if (xEndMon > 11) { xEndMon = 0; xEndYea = xEndYea + 1; }
            var x = me.date2x(new Date(yea+"-"+  ("0"+(mon+1)).slice(-2)  +"-01"));
            var xEnd = me.date2x(new Date(xEndYea+"-"+  ("0"+(xEndMon+1)).slice(-2)  +"-01"));
            var w = xEnd - x;

            var axisBar = me.surface.add({
                type: 'rect',
                x: x,
                y: y,
                width: w,
                height: h,
                fill: '#cdf',						// '#ace'
                stroke: 'grey'
            }).show(true);

            var axisText = me.surface.add({
                type: 'text',
                text: ""+(mon+1),
                x: x + 2,
                y: y + (me.axisHeight / 2),
                fill: '#000',
                font: "9px Arial"
            }).show(true);

            mon = mon + 1;
            if (mon > 11) {
                mon = 0;
                yea = yea + 1;
            }
        }

        if (me.debug) { console.log('PO.view.resource_management.AbstractGanttEditor.drawAxisMonth: Finished'); }
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

        var axisStartTime = me.axisStartDate.getTime();
        var axisEndTime = me.axisEndDate.getTime();

        var x = me.axisStartX + Math.floor(1.0 * axisWidth *
                (1.0 * dateMilliJulian - axisStartTime) /
                (1.0 * axisEndTime - axisStartTime)
        );

        // Allow for negative starts:
        // Projects are determined by start_date + width,
        // so projects would be shifted to the right
        // if (x < 0) { x = 0; }


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



/*****************************************************
 * Like a chart Series, displays a list of projects
 * using Gantt bars.
 */
Ext.define('PO.view.resource_management.ResourceLevelingEditorProjectPanel', {

    extend: 'PO.view.resource_management.AbstractGanttEditor',
    requires: ['PO.view.resource_management.AbstractGanttEditor'],

    costCenterResourceLoadStore: null,				// Reference to cost center store, set during init
    skipGridSelectionChange: false,				// Temporaritly disable updates

    /**
     * Starts the main editor panel as the right-hand side
     * of a project grid and a cost center grid for the departments
     * of the resources used in the projects.
     */
    initComponent: function() {
        var me = this;
        this.callParent(arguments);

        // Catch the event that the object got moved
        me.on({
            'objectdnd': me.onProjectMove,
            'resize': me.redraw,
            'scope': this
        });

        // Catch the moment when the "view" of the Project grid
        // is ready in order to draw the GanttBars for the first time.
        // The view seems to take a while...
        me.objectPanel.on({
            'viewready': me.onProjectGridViewReady,
            'selectionchange': me.onProjectGridSelectionChange,
            'sortchange': me.onProjectGridSelectionChange,
            'scope': this
        });

    },


    /**
     * The list of projects is (finally...) ready to be displayed.
     * We need to wait until this one-time event in in order to
     * set the width of the surface and to perform the first redraw().
     */
    onProjectGridViewReady: function() {
        var me = this;
        console.log('PO.view.resource_management.ResourceLevelingEditorProjectPanel.onProjectGridViewReady');
        var selModel = me.objectPanel.getSelectionModel();

	var atLeastOneProjectSelected = false
        me.objectStore.each(function(model) {
            var projectId = model.get('project_id');
            var sel = me.preferenceStore.getPreferenceBoolean('project_selected.' + projectId, true);
            if (sel) { 
		me.skipGridSelectionChange = true;
                selModel.select(model, true); 
		me.skipGridSelectionChange = false;
		atLeastOneProjectSelected = true;
            }
        });

	if (!atLeastOneProjectSelected) {
            selModel.selectAll(true);
	}
        me.redraw();
    },

    onProjectGridSelectionChange: function(selModel, models, eOpts) {
        var me = this;
	if (me.skipGridSelectionChange) { return; }
        console.log('PO.view.resource_management.ResourceLevelingEditorProjectPanel.onProjectGridSelectionChange');

        me.objectStore.each(function(model) {
            var projectId = model.get('project_id');
            var prefSelected = me.preferenceStore.getPreferenceBoolean('project_selected.' + projectId, true);
            if (selModel.isSelected(model)) {
                model.set('projectGridSelected', 1);
                if (!prefSelected) { 
                    me.preferenceStore.setPreference('@page_url@', 'project_selected.' + projectId, 'true');
                }
            } else {
                model.set('projectGridSelected', 0);
                if (prefSelected) {
                    me.preferenceStore.setPreference('@page_url@', 'project_selected.' + projectId, 'false'); 
                }
            }
        })

        // Reload the Cost Center Resource Load Store with the new selected/changed projects
        me.costCenterResourceLoadStore.loadWithProjectData(me.objectStore);

        me.redraw();
    },


    /**
     * Move the project forward or backward in time.
     * This function is called by onMouseUp as a
     * successful "drop" action of a drag-and-drop.
     */
    onProjectMove: function(baseSprite, projectModel, xDiff) {
        var me = this;
        if (!projectModel) return;
        console.log('PO.view.resource_management.ResourceLevelingEditorProjectPanel.onProjectMove: '+projectModel.get('id') + ', ' + xDiff);

        var bBox = me.dndBaseSprite.getBBox();
        var diffTime = Math.floor(1.0 * xDiff * (me.axisEndDate.getTime() - me.axisStartDate.getTime()) / (me.axisEndX - me.axisStartX));

        var startTime = new Date(projectModel.get('start_date')).getTime();
        var endTime = new Date(projectModel.get('end_date')).getTime();

        startTime = startTime + diffTime;
        endTime = endTime + diffTime;

        var startDate = new Date(startTime);
        var endDate = new Date(endTime);

        projectModel.set('start_date', startDate.toISOString().substring(0,10));
        projectModel.set('end_date', endDate.toISOString().substring(0,10));

        // Reload the Cost Center Resource Load Store with the new selected/changed projects
        me.costCenterResourceLoadStore.loadWithProjectData(me.objectStore);

        me.redraw();
    },

    /**
     * Draw all Gantt bars
     */
    redraw: function() {
        console.log('PO.view.resource_management.ResourceLevelingEditorProjectPanel.redraw: Starting');
        var me = this;

        if (undefined === me.surface) { return; }
        me.surface.removeAll();
        me.surface.setSize(me.ganttSurfaceWidth, me.surface.height);	// Set the size of the drawing area
        me.drawAxis();							// Draw the top axis

        // Draw project bars
        var objectPanelView = me.objectPanel.getView();			// The "view" for the GridPanel, containing HTML elements
        var projectSelModel = me.objectPanel.getSelectionModel();
        me.objectStore.each(function(model) {
            var viewNode = objectPanelView.getNode(model);		// DIV with project name on the ProjectGrid for Y coo
            if (viewNode == null) { return; }				// hidden nodes/models don't have a viewNode
            if (!projectSelModel.isSelected(model)) {
                return;
            }
            me.drawProjectBar(model);
        });

        console.log('PO.view.resource_management.ResourceLevelingEditorProjectPanel.redraw: Finished');
    },

    /**
     * Draw a single bar for a project or task
     */
    drawProjectBar: function(project) {
        var me = this;
        var surface = me.surface;

        var project_name = project.get('project_name');
        var start_date = project.get('start_date').substring(0,10);
        var end_date = project.get('end_date').substring(0,10);
        var startTime = new Date(start_date).getTime();
        var endTime = new Date(end_date).getTime() + 1000.0 * 3600 * 24;	// plus one day

        if (me.debug) { console.log('PO.view.resource_management.ResourceLevelingEditorProjectPanel.drawProjectBar: project_name='+project_name+', start_date='+start_date+", end_date="+end_date); }

        // Calculate the other coordinates
        var x = me.date2x(startTime);
        var y = me.calcGanttBarYPosition(project);
        var w = Math.floor(me.ganttSurfaceWidth * (endTime - startTime) / (me.axisEndDate.getTime() - me.axisStartDate.getTime()));
        var h = me.ganttBarHeight;						// Height of the bars
        var d = Math.floor(h / 2.0) + 1;					// Size of the indent of the super-project bar

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
            listeners: {							// Highlight the sprite on mouse-over
                mouseover: function() { this.animate({duration: 500, to: {'stroke-width': 1.0}}); },
                mouseout: function()  { this.animate({duration: 500, to: {'stroke-width': 0.3}}); }
            }
        }).show(true);
        spriteBar.model = project;						// Store the task information for the sprite

        // Draw availability percentage
        if (me.preferenceStore.getPreferenceBoolean('show_project_resource_load', true)) {
            var assignedDays = project.get('assigned_days');
            var colorConf = 'blue';
            var template = new Ext.Template("<div><b>Project Assignment</b>:<br>There are {value} resources assigned to project '{project_name}' and it's subprojects between {startDate} and {endDate}.<br></div>");
            me.graphOnGanttBar(spriteBar, project, assignedDays, null, new Date(startTime), colorConf, template);
        }

        if (me.debug) { console.log('PO.view.resource_management.ResourceLevelingEditorProjectPanel.drawProjectBar: Finished'); }
    }

});


/*************************************************
 * Like a chart Series, displays a list of projects
 * using Gantt bars.
 */
Ext.define('PO.view.resource_management.ResourceLevelingEditorCostCenterPanel', {
    extend: 'PO.view.resource_management.AbstractGanttEditor',
    requires: ['PO.view.resource_management.AbstractGanttEditor'],

    /**
     * Starts the main editor panel as the right-hand side
     * of a project grid and a cost center grid for the departments
     * of the resources used in the projects.
     */
    initComponent: function() {
        var me = this;
        this.callParent(arguments);

        // Catch the event that the object got moved
        me.on({
            'resize': me.redraw,
            'scope': this
        });


        // Catch the moment when the "view" of the CostCenter grid
        // is ready in order to draw the GanttBars for the first time.
        // The view seems to take a while...
        me.objectPanel.on({
            'viewready': me.onCostCenterGridViewReady,
            'sortchange': me.onCostCenterGridSelectionChange,
            'scope': this
        });

        // Redraw Cost Center load whenever the store has new data
        me.objectStore.on({
            'load': me.onCostCenterResourceLoadStoreChange,
            'scope': this
        });

    },

    /**
     * The data in the CC store have changed - redraw
     */
    onCostCenterResourceLoadStoreChange: function() {
        var me = this;
        console.log('PO.view.resource_management.ResourceLevelingEditorCostCenterPanel.onCostCenterResourceLoadStoreChange');
        me.redraw();
    },


    /**
     * The list of cost centers is (finally...) ready to be displayed.
     * We need to wait until this one-time event in in order to
     * set the width of the surface and to perform the first redraw().
     */
    onCostCenterGridViewReady: function() {
        var me = this;
        console.log('PO.view.resource_management.ResourceLevelingEditorCostCenterPanel.onCostCenterGridViewReady');
        me.redraw();
    },

    onCostCenterGridSelectionChange: function() {
        var me = this;
        console.log('PO.view.resource_management.ResourceLevelingEditorCostCenterPanel.onCostCenterGridSelectionChange');
        me.redraw();
    },

    /**
     * Draw all Gantt bars
     */
    redraw: function() {
        console.log('PO.view.resource_management.ResourceLevelingEditorCostCenterPanel.redraw: Starting');
        var me = this;

        if (undefined === me.surface) { return; }

        me.surface.removeAll();
        me.surface.setSize(me.ganttSurfaceWidth, me.surface.height);	// Set the size of the drawing area
        me.drawAxis();							// Draw the top axis

        // Draw CostCenter bars
        var costCenterStore = me.objectStore;
        var costCenterGridView = me.objectPanel.getView();		// The "view" for the GridPanel, containing HTML elements
        me.objectStore.each(function(model) {
            var viewNode = costCenterGridView.getNode(model);		// DIV with costCenter name on the CostCenterGrid for Y coo
            if (viewNode == null) { return; }				// hidden nodes/models don't have a viewNode
            me.drawCostCenterBar(model);
        });

        console.log('PO.view.resource_management.ResourceLevelingEditorCostCenterPanel.redraw: Finished');
    },

    /**
     * Draw a single bar for a cost center
     */
    drawCostCenterBar: function(costCenter) {
        var me = this;
        if (me.debug) { console.log('PO.view.resource_management.ResourceLevelingEditorCostCenterPanel.drawCostCenterBar: Starting'); }
        var costCenterGridView = me.objectPanel.getView();		// The "view" for the GridPanel, containing HTML elements
        var surface = me.surface;

        // Calculate auxillary start- and end dates
        var start_date = me.axisStartDate.toISOString().substring(0,10);
        var end_date = me.axisEndDate.toISOString().substring(0,10);
        var startTime = new Date(start_date).getTime();
        var endTime = new Date(end_date).getTime();

        // Calculate the start and end of the cost center bars
        var costCenterPanelView = me.objectPanel.getView();                                     // The "view" for the GridPanel, containing HTML elements
        var firstCostCenterBBox = costCenterPanelView.getNode(0).getBoundingClientRect();
        var costCenterBBox = costCenterPanelView.getNode(costCenter).getBoundingClientRect();

        // *************************************************
        // Draw the main bar
        var y = costCenterBBox.top - firstCostCenterBBox.top + 23;
        var h = costCenterBBox.height;
        var x = me.date2x(startTime);
        var w = Math.floor( me.ganttSurfaceWidth * (endTime - startTime) / (me.axisEndDate.getTime() - me.axisStartDate.getTime()));
        var d = Math.floor(h / 2.0) + 1;				// Size of the indent of the super-costCenter bar

        var spriteBar = surface.add({
            type: 'rect',
            x: x, y: y, width: w, height: h,
            // radius: 0,
            fill: 'url(#gradientId)',
            // stroke: 'blue',
            // 'stroke-width': 0.3,
            listeners: {						// Highlight the sprite on mouse-over
//                mouseover: function() { this.animate({duration: 500, to: {'stroke-width': 1.0}}); },
//                mouseout: function()  { this.animate({duration: 500, to: {'stroke-width': 0.3}}); }
            }
        }).show(true);
        spriteBar.model = costCenter;					// Store the task information for the sprite

        // *************************************************
        // Draw availability percentage
        var availableDays = costCenter.get('available_days');		// Array of available days since report_start_date
        if (me.preferenceStore.getPreferenceBoolean('show_dept_available_resources', true)) {
            var maxAvailableDays = parseFloat(""+costCenter.get('assigned_resources')); // Should be the maximum of availableDays
            var template = new Ext.Template("<div><b>Resource Capacity</b>:<br>{value} out of {maxValue} resources are available in department '{cost_center_name}' between {startDate} and {endDate}.<br></div>");
            me.graphOnGanttBar(spriteBar, costCenter, availableDays, maxAvailableDays, new Date(startTime), 'blue', template);
        }

        // *************************************************
        // Draw assignment percentage
        var assignedDays = costCenter.get('assigned_days');
        if (me.preferenceStore.getPreferenceBoolean('show_dept_assigned_resources', true)) {
            var maxAssignedDays = parseFloat(""+costCenter.get('assigned_resources'));
            var template = new Ext.Template("<div><b>Resource Assignment</b>:<br>{value} out of {maxValue} resources are assigned to projects in department '{cost_center_name}' between {startDate} and {endDate}.<br></div>");
            me.graphOnGanttBar(spriteBar, costCenter, assignedDays, maxAssignedDays, new Date(startTime), 'red', template);
        }

        // *************************************************
        // Draw load percentage
        if (me.preferenceStore.getPreferenceBoolean('show_dept_percent_work_load', true)) {
            var len = availableDays.length;
            if (assignedDays.length < len) { len = assignedDays.length; }
            var loadDays = [];
            var maxLoadPercentage = 0;
            for (var i = 0; i < len; i++) {
                if (assignedDays[i] == 0.0) {    // Zero assigned => zero
                    loadDays.push(0);
                    continue;
                }
                if (availableDays[i] == 0.0) {   // Avoid division by zero
                    loadDays.push(0);
                    continue;
                }
                var loadPercentage = Math.round(100.0 * 100.0 * assignedDays[i] / availableDays[i]) / 100.0
                if (loadPercentage > maxLoadPercentage) { maxLoadPercentage = loadPercentage; }
                loadDays.push(loadPercentage);
            }
            var template = new Ext.Template("<div><b>Work Load</b>:<br>The work load is at {value}% out of 100% available in department {cost_center_name} beween {startDate} and {endDate}.<br></div>");
            me.graphOnGanttBar(spriteBar, costCenter, loadDays, maxLoadPercentage, new Date(startTime), 'green', template);
        }
        
        // *************************************************
        // Accumulated Load percentage
        if (me.preferenceStore.getPreferenceBoolean('show_dept_accumulated_overload', true)) {
            var accLoad = 0.0
            var accLoadDays = [];
            var maxAccLoad = 0.0
            for (var i = 0; i < len; i++) {
                var assigned = assignedDays[i];
                var available = availableDays[i];
                accLoad = accLoad + assigned - available;
                if (accLoad < 0.0) { accLoad = 0.0; }
                accLoadDays.push(Math.round(100.0 * accLoad) / 100.0);
                if (accLoad > maxAccLoad) { maxAccLoad = accLoad; }
            }
            var template = new Ext.Template("<div><b>Accumulated Overload</b>:<br>There are {value} days of planned work not yet finished in department {cost_center_name} on {startDate}.<br></div>");
            me.graphOnGanttBar(spriteBar, costCenter, accLoadDays, maxAccLoad, new Date(startTime), 'purple', template);
        }
    }
});


/**
 * Create the four panels and
 * handle external resizing events
 */
function launchApplication(){

    var renderDiv = Ext.get('resource_level_editor_div');

    var projectResourceLoadStore = Ext.StoreManager.get('projectResourceLoadStore');
    var costCenterResourceLoadStore = Ext.StoreManager.get('costCenterResourceLoadStore');
    var senchaPreferenceStore = Ext.StoreManager.get('senchaPreferenceStore');

    var numProjects = projectResourceLoadStore.getCount();
    var numCostCenters = costCenterResourceLoadStore.getCount();
    var numProjectsPlusCostCenters = numProjects + numCostCenters;

    var gridWidth = 300;

    // Height of grids and Gantt Panels
    var projectCellHeight = 27;
    var costCenterCellHeight = 39;
    var listProjectsAddOnHeight = 11;
    var listCostCenterAddOnHeight = 11;
    var projectGridHeight = listProjectsAddOnHeight + projectCellHeight * (1 + numProjects);
    var costCenterGridHeight = listCostCenterAddOnHeight + costCenterCellHeight * (1 + numCostCenters);

    var projectGridSelectionModel = Ext.create('Ext.selection.CheckboxModel');
    var projectGrid = Ext.create('Ext.grid.Panel', {
        title: false,
        region: 'west',
        width: gridWidth,
        store: 'projectResourceLoadStore',
        autoScroll: true,
        overflowX: false,
        overflowY: false,
        selModel: projectGridSelectionModel,
        columns: [{
            text: 'Projects',
            dataIndex: 'project_name',
            flex: 1
        },{
            text: 'Start',
            dataIndex: 'start_date',
            width: 100
        },{
            text: 'End',
            dataIndex: 'end_date',
            width: 80,
            hidden: true
        }],
        shrinkWrap: true
    });

    var costCenterGrid = Ext.create('Ext.grid.Panel', {
        title: false,
        width: gridWidth,
        region: 'west',
        store: 'costCenterResourceLoadStore',
        autoScroll: true,
        overflowX: false,
        overflowY: false,
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
    var resourceLevelingEditorCostCenterPanel = Ext.create('PO.view.resource_management.ResourceLevelingEditorCostCenterPanel', {
        title: false,
        region: 'center',
        viewBox: false,
        dndEnabled: false,				// Disable drag-and-drop for cost centers
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
        objectStore: costCenterResourceLoadStore,
        objectPanel: costCenterGrid,
        reportStartDate: new Date(report_start_date),
        reportEndDate: new Date(report_end_date),
        preferenceStore: senchaPreferenceStore
    });

    // Drawing area for for Gantt Bars
    var resourceLevelingEditorProjectPanel = Ext.create('PO.view.resource_management.ResourceLevelingEditorProjectPanel', {
        title: false,
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
        overflowX: 'scroll',						// Allows for horizontal scrolling, but not vertical
        scrollFlags: {x: true},
        objectStore: projectResourceLoadStore,
        objectPanel: projectGrid,
        reportStartDate: new Date(report_start_date),
        reportEndDate: new Date(report_end_date),
        preferenceStore: senchaPreferenceStore,

        // Reference to the CostCenter store
        costCenterResourceLoadStore: costCenterResourceLoadStore
    });

    /**
     * Help Drop-down
     */
    // Define the model for a State
    Ext.regModel('State', {
        fields: [
            {type: 'string', name: 'abbr'},
            {type: 'string', name: 'name'},
            {type: 'string', name: 'slogan'}
    ]
    });

// The data store holding the states
    var store = Ext.create('Ext.data.Store', {
        model: 'State',
        data: [
            { 'abbr': 'cat', 'name': 'Catalonia', 'slogan': 'Hi' },
            { 'abbr': 'cat', 'name': 'Catalonia', 'slogan': 'Hi' }
        ]
    });

    var helpComponent = Ext.create('Ext.form.ComboBox', {
        emptyText: 'Help Topics',
        displayField: 'name',
        width: 300,
        labelWidth: 130,
        store: store,
        queryMode: 'local',
        typeAhead: true,
        listConfig : {
            getInnerTpl : function() {
                return '<div class="x-combo-list-item"><img src="' + Ext.BLANK_IMAGE_URL + '" class="chkCombo-default-icon chkCombo" /> {abbr} - {name} </div>';
            }
        }
    });


    var configurationMenuOnItemCheck = function(item, checked){
        console.log('configurationMenuOnItemCheck: item.id='+item.id);
        senchaPreferenceStore.setPreference('@page_url@', item.id, checked);
        resourceLevelingEditorProjectPanel.redraw();
        resourceLevelingEditorCostCenterPanel.redraw();
    }

    var configurationMenu = Ext.create('Ext.menu.Menu', {
        id: 'configMenu',
        style: {
            overflow: 'visible'     // For the Combo popup
        },
        items: [
            {
                text: 'Reset Configuration',
                handler: function() {
                    console.log('configurationMenuOnResetConfiguration');
                    senchaPreferenceStore.each(function(model) {
                        var url = model.get('preference_url');
                        if (url != '@page_url@') { return; }
                        model.destroy();
                    })
                }
            }, '-'
        ]
    });

    // Setup the configurationMenu items
    var confSetupStore = Ext.create('Ext.data.Store', {
        fields: ['key', 'text', 'def'],
        data : [
            {key: 'show_project_resource_load', text: 'Show Project Assigned Resources', def: true},
            {key: 'show_dept_assigned_resources', text: 'Show Department Assigned Resources', def: false},
            {key: 'show_dept_available_resources', text: 'Show Department Available Resources', def: false},
            {key: 'show_dept_percent_work_load', text: 'Show Department % Work Load', def: true},
            {key: 'show_dept_accumulated_overload', text: 'Show Department Accumulated Overload', def: false}
        ]
    });
    confSetupStore.each(function(model) {
        console.log('confSetupStore: '+model);
        var key = model.get('key');
        var def = model.get('def');
        var checked = senchaPreferenceStore.getPreferenceBoolean(key, def);
        if (!senchaPreferenceStore.existsPreference(key)) {
            senchaPreferenceStore.setPreference('@page_url@', key, checked ? 'true' : 'false');
        }
        var item = Ext.create('Ext.menu.CheckItem', {
            id: key,
            text: model.get('text'),
            checked: checked,
            checkHandler: configurationMenuOnItemCheck
        });
        configurationMenu.add(item);
    });

    /*
     * Main Panel that contains the three other panels
     * (projects, departments and gantt bars)
     */
    var buttonPanelHeight = 40;
    var borderPanelHeight = buttonPanelHeight + costCenterGridHeight + projectGridHeight;

    var sideBar = Ext.get('sidebar');					// ]po[ left side bar component
    var sideBarWidth = sideBar.getSize().width;
    var borderPanelWidth = Ext.getBody().getViewSize().width - sideBarWidth - 85;
    var borderPanel = Ext.create('Ext.panel.Panel', {
        width: borderPanelWidth,
        height: borderPanelHeight,
        title: false,
        layout: 'border',
        resizable: true,						// Allow the user to resize the outer diagram borders
        defaults: {
            collapsible: false,
            split: true,
            bodyPadding: 0
        },
        items: [{
            title: false,
            region: 'north',
            height: projectGridHeight,
            xtype: 'panel',
            layout: 'border',
            shrinkWrap: true,
            items: [
                projectGrid,
                resourceLevelingEditorProjectPanel
            ]
        }, {
            title: false,
            region: 'center',
            height: costCenterGridHeight,
            xtype: 'panel',
            layout: 'border',
            shrinkWrap: true,
            items: [
                costCenterGrid,
                resourceLevelingEditorCostCenterPanel
            ]
        }],
        tbar: [
            {
                text: 'OK',
                icon: '/intranet/images/navbar_default/disk.png',
                tooltip: 'Save the project to the ]po[ back-end',
                id: 'buttonSave'
            }, {
                icon: '/intranet/images/navbar_default/folder_go.png',
                tooltip: 'Load a project from he ]po[ back-end',
                id: 'buttonLoad'
            }, {
                xtype: 'tbseparator' 
            }, {
                icon: '/intranet/images/navbar_default/add.png',
                tooltip: 'Add a new task',
                id: 'buttonAdd'
            }, {
                icon: '/intranet/images/navbar_default/delete.png',
                tooltip: 'Delete a task',
                id: 'buttonDelete'
            }, {
                xtype: 'tbseparator' 
            }, {
                icon: '/intranet/images/navbar_default/arrow_left.png',
                tooltip: 'Reduce Indent',
                id: 'buttonReduceIndent'
            }, {
                icon: '/intranet/images/navbar_default/arrow_right.png',
                tooltip: 'Increase Indent',
                id: 'buttonIncreaseIndent'
            }, {
                xtype: 'tbseparator'
            }, {
                icon: '/intranet/images/navbar_default/link_add.png',
                tooltip: 'Add dependency',
                id: 'buttonAddDependency'
            }, {
                icon: '/intranet/images/navbar_default/link_break.png',
                tooltip: 'Break dependency',
                id: 'buttonBreakDependency'
            }, '->' , {
                icon: '/intranet/images/navbar_default/zoom_in.png',
                tooltip: { 
                    target: 'buttonZoomIn',
                    title: 'Title',
                    width: 300,
                    text: '<p>Zoom in time axis</p>'
                },
                id: 'buttonZoomIn'
            }, {
                icon: '/intranet/images/navbar_default/zoom_out.png',
                tooltip: 'Zoom out of time axis',
                id: 'buttonZoomOut'
            }, 
            helpComponent,
            {
                xtype: 'tbseparator' 
            }, {
                text: 'Configuration',
                icon: '/intranet/images/navbar_default/cog.png',
                menu: configurationMenu
            }
        ],
        renderTo: renderDiv
    });

    var onResize = function (sideBarWidth) {
        console.log('launchApplication.onSideBarResize:');

        var screenWidth = Ext.getBody().getViewSize().width;
        var width = screenWidth - sideBarWidth;

        borderPanel.setSize(width, borderPanelHeight);
        resourceLevelingEditorProjectPanel.redraw();
        resourceLevelingEditorCostCenterPanel.redraw();
    };

    var onWindowResize = function () {
        console.log('launchApplication.onWindowResize:');
        var sideBar = Ext.get('sidebar');				// ]po[ left side bar component
        var sideBarWidth = sideBar.getSize().width;

        if (sideBarWidth > 100) {
            sideBarWidth = 340;						// Determines size when Sidebar visible
        } else {
            sideBarWidth = 85;						// Determines size when Sidebar collapsed
        }

        onResize(sideBarWidth);
    };

    // Manually changed the size of the borderPanel
    var onBorderResize = function () {
        console.log('launchApplication.onBorderResize:');

        resourceLevelingEditorProjectPanel.redraw();
        resourceLevelingEditorCostCenterPanel.redraw();
    };

    var onSidebarResize = function () {
        console.log('launchApplication.onResize:');
        // ]po[ Sidebar
        var sideBar = Ext.get('sidebar');				// ]po[ left side bar component
        var sideBarWidth = sideBar.getSize().width;

        // We get the event _before_ the sideBar has changed it's size.
        // So we actually need to the the oposite of the sidebar size:
        if (sideBarWidth > 100) {
            sideBarWidth = 85;						// Determines size when Sidebar collapsed
        } else {
            sideBarWidth = 340;						// Determines size when Sidebar visible
        }
        onResize(sideBarWidth);

    };

    borderPanel.on('resize', onBorderResize);
    Ext.EventManager.onWindowResize(onWindowResize);
    var sideBarTab = Ext.get('sideBarTab');
    sideBarTab.on('click', onSidebarResize);

};


/**
 * Application Launcher
 * Only deals with loading the required
 * stores before calling launchApplication()
 */
Ext.onReady(function() {
    Ext.QuickTips.init();

    // Show splash screen while the stores are loading
    var renderDiv = Ext.get('resource_level_editor_div');
    var splashScreen = renderDiv.mask('Loading data');
    var task = new Ext.util.DelayedTask(function() {
        splashScreen.fadeOut({duration: 100, remove: true});		// fade out the body mask
        splashScreen.next().fadeOut({duration: 100, remove: true});	// fade out the message
    });

    var projectResourceLoadStore = Ext.create('PO.store.resource_management.ProjectResourceLoadStore');
    var costCenterResourceLoadStore = Ext.create('PO.store.resource_management.CostCenterResourceLoadStore');
    var senchaPreferenceStore = Ext.create('PO.store.user.SenchaPreferenceStore');

    // Wait for both the project and cost-center store
    // before launching the application. We need the
    // Stores in order to calculate the size of the panels
    var coo = Ext.create('PO.controller.StoreLoadCoordinator', {
        debug: 0,
        launched: false,
        stores: [
            'projectResourceLoadStore',
            'costCenterResourceLoadStore',
            'senchaPreferenceStore'
        ],
        listeners: {
            load: function() {

                if (this.launched) { return; }
                // Launch the actual application.
                console.log('PO.controller.StoreLoadCoordinator: launching Application');
                this.launched = true;
                task.delay(100);					// Fade out the splash screen
                launchApplication();					// launch the actual application
            }
        }
    });

    // Load the project store and THEN load the costCenter store.
    // The Gantt panels will redraw() if stores are reloaded.
    projectResourceLoadStore.load({
        callback: function() {
            console.log('PO.controller.StoreLoadCoordinator.projectResourceLoadStore: loaded');
            // Now load the cost center load for the current
            costCenterResourceLoadStore.loadWithProjectData(projectResourceLoadStore);
        }
    });

    senchaPreferenceStore.load();

});

</script>
