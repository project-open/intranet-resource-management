<div id=@diagram_id@></div>
<script type='text/javascript'>

Ext.require(['Ext.chart.*', 'Ext.Window', 'Ext.fx.target.Sprite', 'Ext.layout.container.Fit']);
Ext.onReady(function () {
    
    employeeAssignmentStore = Ext.create('Ext.data.Store', {
        fields: ['name', 'value'],
	autoLoad: true,
	proxy: {
            type: 'rest',
            url: '/intranet-resource-management/employee-assignment-pie-chart.json',
            extraParams: {				// Parameters to the data-source
		diagram_interval: 'next_quarter'	// Number of customers to show
            },
            reader: { type: 'json', root: 'data' }
	}
    });

    var employeeAssignmentIntervalStore = Ext.create('Ext.data.Store', {
	fields: ['display', 'value'],
	data : [
            {"display":"<%=[lang::message::lookup "" intranet-resource-management.Next_Quarter "Next Quarter"]%>", "value": "next_quarter"}
	]
    });

    employeeAssignmentChart = new Ext.chart.Chart({
	xtype: 'chart',
	animate: true,
	store: employeeAssignmentStore,
	legend: { position: 'right' },
	insetPadding: 20,
	theme: 'Base:gradients',
	series: [{
	    type: 'pie',
	    field: 'value',
	    showInLegend: true,
	    label: {
		field: 'name',
		display: 'rotate',
                font: '11px Arial'
	    },
	    tips: {
                width: 140,
                height: 50,
                renderer: function(storeItem, item) {
                    var total = 0;                    //calculate percentage.
                    employeeAssignmentStore.each(function(rec) { total += rec.get('value'); });
                    this.setTitle(storeItem.get('name') + ':<br>' + Math.round(storeItem.get('value') / total * 100) + '%');
                }
	    },
	    highlight: { segment: { margin: 20 } }
	}]
    });

    var employeeAssignmentPanel = Ext.create('widget.panel', {
        width: @diagram_width@,
        height: @diagram_height@,
        title: '@diagram_title@',
	renderTo: '@diagram_id@',
        layout: 'fit',
	header: false,
        tbar: [
	    {
		xtype: 'combo',
		editable: false,
		store: employeeAssignmentIntervalStore,
		mode: 'local',
		displayField: 'display',
		valueField: 'value',
		triggerAction: 'all',
		width: 150,
		forceSelection: true,
		value: 'next_quarter',
		listeners:{select:{fn:function(combo, comboValues) {
		    var value = comboValues[0].data.value;
		    var extraParams = employeeAssignmentStore.getProxy().extraParams;
		    extraParams.diagram_interval = value;
		    employeeAssignmentStore.load();
		}}}
            }
	],
        items: employeeAssignmentChart
    });
});
</script>
