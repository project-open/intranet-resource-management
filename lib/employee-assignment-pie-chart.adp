<div id=@diagram_id@></div>

<style type="text/css" <if @::__csp_nonce@ not nil>nonce="@::__csp_nonce;literal@"</if>>
.extjs-indent-level-0 { font-size: 11px; padding-left: 5px }
.extjs-indent-level-1 { font-size: 11px; padding-left: 25px }
.extjs-indent-level-2 { font-size: 11px; padding-left: 45px }
.extjs-indent-level-3 { font-size: 11px; padding-left: 65px }
.extjs-indent-level-4 { font-size: 11px; padding-left: 85px }
.extjs-indent-level-5 { font-size: 11px; padding-left: 105px }
.extjs-indent-level-6 { font-size: 11px; padding-left: 125px }
.extjs-indent-level-7 { font-size: 11px; padding-left: 145px }
.extjs-indent-level-8 { font-size: 11px; padding-left: 165px }
</style>

<script type='text/javascript' <if @::__csp_nonce@ not nil>nonce="@::__csp_nonce;literal@"</if>>
Ext.require(['Ext.chart.*', 'Ext.Window', 'Ext.fx.target.Sprite', 'Ext.layout.container.Fit']);
Ext.onReady(function () {
    
    employeeAssignmentStore = Ext.create('Ext.data.Store', {
        fields: ['name', 'value'],
	autoLoad: true,
	proxy: {
            type: 'rest',
            url: '/intranet-resource-management/employee-assignment-pie-chart.json',
            extraParams: {				// Parameters to the data-source
		diagram_interval: 'next_quarter',	// Number of customers to show
		diagram_department_user_id: ""		// Department or user for which to show
            },
            reader: { type: 'json', root: 'data' }
	}
    });

    var employeeAssignmentIntervalStore = Ext.create('Ext.data.Store', {
	fields: ['display', 'value'],
	data : [
            {value: "next_quarter", display: "<%=[lang::message::lookup "" intranet-resource-management.Next_Quarter "Next Quarter"]%>"},
            {value: "over_next_quarter", display: "<%=[lang::message::lookup "" intranet-resource-management.Over_Next_Quarter "Over Next Quarter"]%>"},
            {value: "last_quarter", display: "<%=[lang::message::lookup "" intranet-resource-management.Last_Quarter "Last Quarter"]%>"},
            {value: "over_last_quarter", display: "<%=[lang::message::lookup "" intranet-resource-management.Over_Last_Quarter "Over Last Quarter"]%>"}
	]
    });

    var employeeAssignmentDepartmentStore = Ext.create('Ext.data.Store', {
	fields: ['display', 'value', 'indent'],
	data : [
	    <multiple name="departments">
		{value: '@departments.value@', indent: @departments.indent@, display: '@departments.display@'},
	    </multiple>
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
            }, {
		xtype: 'combo',
		editable: false,
		store: employeeAssignmentDepartmentStore,
		mode: 'local',
		displayField: 'display',
		valueField: 'value',
		triggerAction: 'all',
		width: 300,
		forceSelection: true,
		value: '@company_department_id@',
		listConfig: {
		    getInnerTpl : function() {
			return '<div class="extjs-indent-level-' + '{indent}' + '">' + '{display}&nbsp;' + '</div>';
			return '{name}';
		    }
		},
		listeners:{select:{fn:function(combo, comboValues) {
		    var value = comboValues[0].data.value;
		    var extraParams = employeeAssignmentStore.getProxy().extraParams;
		    extraParams.diagram_department_user_id = value;
		    employeeAssignmentStore.load();
		}}}
            }
	],
        items: employeeAssignmentChart
    });
});
</script>
