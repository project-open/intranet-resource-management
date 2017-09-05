# /packages/intranet-resource-management/tcl/intranet-resource-management-percentage.tcl
#
# Copyright (C) 2010-2013 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

ad_library {
    Resource management report by percentage.

    @author frank.bergmann@project-open.com
    @author klaus.hofeditz@project-open.com
}



# ---------------------------------------------------------------
# Resource Planning Report
# ---------------------------------------------------------------

#    {-top_vars "year week_of_year day"}

ad_proc -public im_resource_mgmt_resource_planning_percentage {
    {-top_vars "year month_of_year day_of_month" }
    {-left_vars "cell"}
    {-report_start_date ""}
    {-report_end_date ""}
    {-report_project_id ""}
    {-report_project_status_id ""}
    {-report_project_type_id ""}
    {-report_employee_cost_center_id "" }
    {-report_user_id ""}
    {-report_customer_id 0}
    {-export_var_list ""}
    {-excluded_group_ids "" }
    {-return_url ""}
    {-page_url:required}
    {-absences_included_in_project_planning_p "1"}
    {-debug_p 1}
} {
    Creates Resource Report 

    @param start_date Hard start of reporting period. Defaults to start of first project
    @param end_date Hard end of replorting period. Defaults to end of last project
    @param project_id Id of project(s) to show. Defaults to all active projects
    @param customer_id Id of customer's projects to show
} {
    # ---------------------------------------
    # Defaults
    # 

    # Write iregularities to protocoll
    set err_protocol ""

    # Department to use, when user is not assigned to one 
    set company_cost_center [im_cost_center_company]
    set default_department [parameter::get_from_package_key -package_key "intranet-resource-management" -parameter "DefaultCostCenterId" -default $company_cost_center]
    set freelancers_department 999999

    if {"" == $excluded_group_ids} { set excluded_group_ids 0 }

    set html ""
    set rowclass(0) "roweven"
    set rowclass(1) "rowodd"
    set sigma "&Sigma;"
    set current_user_id [ad_conn user_id]
    set return_url [im_url_with_query]
    set clicks([clock clicks -microseconds]) null

    # The list of users/projects opened already
    set user_name_link_opened {}

    set this_url [export_vars -base $page_url {start_date end_date customer_id} ]
    foreach pid $report_project_id { append this_url "&project_id=$pid" }


    # ------------------------------------------------------------
    # Determine what aggregates to calculate
    set calc_day_p 0
    set calc_week_p 0
    set calc_month_p 0
    set calc_quarter_p 0
    switch $top_vars {
        "year week_of_year day_of_week" { set calc_day_p 1 }
        "year month_of_year day_of_month" { set calc_day_p 1 }
        "year week_of_year" { set calc_week_p 1 }
        "year month_of_year" { set calc_month_p 1 }
        "year quarter_of_year" { set calc_quarter_p 1 }
    }

    if {0 != $report_customer_id && "" == $report_project_id} {
	set project_id [db_list pids "
	select	project_id
	from	im_projects
	where	parent_id is null
		and company_id = :report_customer_id
        "]
    }

    db_1row date_calc "
	select	to_char(:report_start_date::date, 'J') as report_start_julian,
		to_char(:report_end_date::date, 'J') as report_end_julian,
		to_char(now()::date, 'J') as now_julian
    "

    # ------------------------------------------------------------
    # URLs to different parts of the system

    set project_base_url "/intranet/projects/view"
    set user_base_url "/intranet/users/view"
    set trans_task_base_url "/intranet-translation/trans-tasks/new"

    set collapse_url "/intranet/biz-object-tree-open-close"
    set company_url "/intranet/companies/view?company_id="
    set project_url "/intranet/projects/view?project_id="
    set cost_center_url "/intranet-cost/cost-centers/new?cost_center_id="
    set user_url "/intranet/users/view?user_id="

    # Hash for URLs per object type
    set url_hash(user) $user_url
    set url_hash(im_project) $project_url
    set url_hash(im_cost_center) $cost_center_url

    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Conditional SQL where clause"
    #
    set assignment_criteria [list]
    set user_criteria ""
    if {"" != $report_customer_id && 0 != $report_customer_id} { lappend assignment_criteria "parent.company_id = :report_customer_id" }
    if {"" != $report_project_id && 0 != $report_project_id} { lappend assignment_criteria "parent.project_id in ([join $report_project_id ", "])" }
    if {"" != $report_project_status_id && 0 != $report_project_status_id} { 
	lappend assignment_criteria "parent.project_status_id in ([join [im_sub_categories $project_status_id] ", "])" 
    }
    if {"" != $report_project_type_id && 0 != $report_project_type_id} { 
	lappend assignment_criteria "parent.project_type_id in ([join [im_sub_categories $report_project_type_id] ", "])" 
    }
    if {"" != $report_user_id && 0 != $report_user_id} { lappend assignment_criteria "u.user_id in ([join $report_user_id ","])" }
    if {"" != $report_employee_cost_center_id && 0 != $report_employee_cost_center_id} {
	lappend assignment_criteria "u.user_id in (
		select	eee.employee_id
		from	im_employees eee
		where	eee.department_id in ([join [im_sub_cost_center_ids $report_employee_cost_center_id] ","])
	)"

	lappend user_criteria "
			u.user_id in (
				select  eee.employee_id
				from    im_employees eee
				where   eee.department_id in ([join [im_sub_cost_center_ids $report_employee_cost_center_id] ","])
			)
	"
    } 

    if {"" ne $excluded_group_ids && 0 ne $excluded_group_ids} {
        lappend assignment_criteria "u.user_id not in (
            select  object_id_two from acs_rels where object_id_one in ([join $excluded_group_ids ","]) and rel_type = 'membership_rel'
        )"
    }

    set assignment_where_clause [join $assignment_criteria " and\n\t\t\t"]
    if { $assignment_where_clause ne "" } { set assignment_where_clause " and $assignment_where_clause" }
    set user_where_clause [join $user_criteria " and\n\t\t\t"]
    if { $user_where_clause ne "" } { set user_where_clause " and $user_where_clause" }


    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Pre-calculate GIFs for performance reasons"
    #
    set object_type_gif_sql "select object_type, object_type_gif from acs_object_types
	where	object_type in ('user', 'person', 'im_cost_center', 'im_project', 'im_timesheet_task')
    "
    db_foreach gif $object_type_gif_sql {
	set gif_hash($object_type) [im_gif $object_type_gif]
    }
    foreach gif {minus_9 plus_9 magnifier_zoom_in magnifier_zoom_out} {
	set gif_hash($gif) [im_gif $gif]
    }
    set clicks([clock clicks -microseconds]) gifs


    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Store information about each day into hashes for speed"
    #
    for {set i $report_start_julian} {$i <= $report_end_julian} {incr i} {

	# Calculate the date components and store in a hash
	set date_components [util_memoize [list im_date_julian_to_components $i] 100000]
	set date_components_hash($i) $date_components

	array unset date_comps_hash
	array set date_comps_hash $date_components

	# Day of Week
	set dow $date_comps_hash(day_of_week)
	set day_of_week_hash($i) $dow

	# Weekend
	if {0 == $dow || 6 == $dow || 7 == $dow} { set weekend_hash($i) [im_user_absence_type_bank_holiday] }
	
	# Start of Week Julian
	set start_of_week_julian_hash($i) [expr $i - $dow]
    }
    set clicks([clock clicks -microseconds]) weekends


    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Absences - Determine when the user is away"
    # key: julian-uid, value: absence_type_id
    # 458004-624 5000 2458001-624 5000 2458005-624 5000 2458002-624 5000 2458003-624 5000
    #
    array set absences_julian_hash [im_resource_mgmt_resource_planning_percentage_absences \
				 -report_start_date $report_start_date \
				 -report_end_date $report_end_date \
				 -user_where_clause $user_where_clause \
    ]
    
    # Add absences_julian_hash entries for chosen top dimension
    foreach absence_key [array names absences_julian_hash] {
	# Split the $julian-$user_id key into it's components
	set tuple [split $absence_key "-"]
	set j [lindex $tuple 0]
	set user_id [lindex $tuple 1]

	# skip absences outside the report period
	if {![info exists date_components_hash($j)]} { continue }

	set key_list [util_memoize [list im_resource_management_top_scale_from_julian -julian $j -top_vars $top_vars]]
	set key "[join $key_list "-"]-$user_id"
	set absence_list [list]
	if {[info exists absences_hash($key)]} { set absence_list $absences_hash($key) }
	set absence_list [concat $absence_list $absences_julian_hash($absence_key)]

	# Don't show absences on weekends
	if {$calc_day_p && [info exists weekend_hash($j)]} { set absence_list "" }

	set absences_hash($key) $absence_list
    }

#    ad_return_complaint 1 "<pre>absences_julian_hash<br>[array get absences_julian_hash]</pre>"
#    ad_return_complaint 1 "<pre>absences_hash<br>[array get absences_hash]</pre>"
#    ad_return_complaint 1 [array get absences_julian_hash]
    set clicks([clock clicks -microseconds]) absences



    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Assignments"
    # Assignments - Determine assignments per project/task and user.
    # This SQL is used as a sub-query in several other SQLs
    #
    set assignment_sql "
		select	child.project_id,
			child.project_name,
			child.parent_id,
			(length(child.tree_sortkey) / 8) - 3 as level,
			parent.project_id as main_project_id,
			u.user_id,
			coalesce(round(m.percentage), 0) as percentage,
			to_char(child.start_date, 'J') as child_start_julian,
			to_char(child.end_date, 'J') as child_end_julian
		from	im_projects parent,
			im_projects child,
			acs_rels r,
			im_biz_object_members m,
			users u
		where	parent.project_status_id not in ([join [im_sub_categories [im_project_status_closed]] ","])
			and parent.parent_id is null
			and parent.project_type_id not in ([im_project_type_task], [im_project_type_sla], [im_project_type_ticket])
			and child.end_date >= '$report_start_date'::date
			and child.start_date <= '$report_end_date'::date
			and child.tree_sortkey
				between parent.tree_sortkey
				and tree_right(parent.tree_sortkey)
			and child.project_type_id not in ([im_project_type_sla], [im_project_type_ticket])
			and r.rel_id = m.rel_id
			and r.object_id_one = child.project_id
			and r.object_id_two = u.user_id
			and u.user_id not in (		-- only active natural persons
				select member_id
				from   group_distinct_member_map
				where  group_id = [im_profile_skill_profile]
			   UNION
				select	u.user_id
				from	users u,
					acs_rels r,
					membership_rels mr
				where	r.rel_id = mr.rel_id and
					r.object_id_two = u.user_id and
					r.object_id_one = -2 and
					mr.member_state != 'approved'
			)
			$assignment_where_clause
		order by
			child.tree_sortkey,
			u.user_id
    "
    db_foreach assignments $assignment_sql {
	# Store properties into hashes for quick access later
	set main_project_hash($main_project_id) $main_project_id
	set user_hash($user_id) $user_id

	# Store the actual project-user assignment information
	if {$percentage > 0} {
	    set key "$project_id-$user_id"
	    set project_user_assignment_hash($key) $percentage
	}

    }

    # Check for existing assignments 
    if { 0 eq [array size user_hash] } { return "" }

    # ad_return_complaint 1 "<pre>[join [array get project_user_assignment_hash] "\n"]</pre>"
    set clicks([clock clicks -microseconds]) assignments


    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Hierarchy"
    # Hierarchy - Determine parent-child relationships etc. and store in hashes.
    # We need to get all sub-projects from the main projects references, because
    # projects in the hierarchy may not be included in the assignment query above.
    # 
    set main_project_list [array names main_project_hash]
    lappend main_project_list 0
    set hierarchy_sql "
		select	child.project_id,
			child.project_name,
			child.parent_id,
			(length(child.tree_sortkey) / 8) - 3 as level,
			greatest(to_char(child.start_date::date, 'J')::integer, :report_start_julian::integer) child_start_julian,
			least(to_char(child.end_date, 'J')::integer, :report_end_julian::integer) as child_end_julian
		from	im_projects parent,
			im_projects child
		where	parent.project_id in ([join $main_project_list ","])
			and child.tree_sortkey
				between parent.tree_sortkey
				and tree_right(parent.tree_sortkey)
    "
    db_foreach hierarchy $hierarchy_sql {
	# Store properties into hashes for quick access later
	set object_name_hash($project_id) $project_name
	set object_type_hash($project_id) "im_project"
	set object_parent_hash($project_id) $parent_id
	set project_start_julian_hash($project_id) $child_start_julian
	set project_end_julian_hash($project_id) $child_end_julian
	set project_level_hash($project_id) $level
	set object_availability_hash($project_id) ""
	set collapse_hash($project_id) "c"
    }
    # ad_return_complaint 1 "<pre>[join [array get project_user_assignment_hash] "\n"]</pre>"
    set clicks([clock clicks -microseconds]) hierarchy


    # --------------------------------------------
    ns_log Notice "percentage-report: Cost center information"
    #
    set cc_sql "
	select	cc.*,
		round(length(cc.cost_center_code) / 2) as indent_level,
		coalesce((select sum(coalesce(e.availability, 0))
		from	im_employees e,
			users u
		where	e.employee_id = u.user_id and
			e.department_id = cc.cost_center_id and
			e.employee_id not in (		-- only active natural persons
				select member_id
				from   group_distinct_member_map
				where  group_id = [im_profile_skill_profile]
			   UNION
				select	u.user_id
				from	users u,
					acs_rels r,
					membership_rels mr
				where	r.rel_id = mr.rel_id and
					r.object_id_two = u.user_id and
					r.object_id_one = -2 and
					mr.member_state != 'approved'
			)
			$user_where_clause
		), 0) as resources_available_percent
	from	im_cost_centers cc
	where	1 = 1
	order by cc.cost_center_code
    "
    db_foreach ccs $cc_sql {
	set object_parent_hash($cost_center_id) $parent_id
	set object_type_hash($cost_center_id) "im_cost_center"
	set object_name_hash($cost_center_id) $cost_center_name
	set collapse_hash($cost_center_id) "o"

	# Aggregate resources upward
	set object_availability_hash($cost_center_id) $resources_available_percent
	set parent_cc_id $parent_id
	set cnt 0
	while {"" ne $parent_cc_id} {
	    set val $object_availability_hash($parent_cc_id)
	    set val [expr $val + $resources_available_percent]
	    set object_availability_hash($parent_cc_id) $val
	    set parent_cc_id $object_parent_hash($parent_cc_id)
	    incr cnt
	    if {$cnt > 20} { ad_return_complaint 1 "Percentage Report:<br>Infinite loop in dept aggregation" }
	}
    }
    
    # Setup a fake "Freelancers" department below "The Company"
    set object_parent_hash($freelancers_department) $default_department
    set object_type_hash($freelancers_department) "im_cost_center"
    set object_name_hash($freelancers_department) [lang::message::lookup "" intranet-core.No_Department "No Department"]
    set collapse_hash($freelancers_department) "o"
    set object_availability_hash($freelancers_department) 0
    set clicks([clock clicks -microseconds]) department_hierarchy


    # --------------------------------------------
    ns_log Notice "percentage-report: User department information"
    #
    set user_info_sql "
	select	u.user_id,
		coalesce(e.department_id, :freelancers_department) as department_id,
		coalesce(e.availability, 0) as availability,
		im_name_from_user_id(u.user_id) as user_name
	from	users u
		LEFT OUTER JOIN im_employees e ON (u.user_id = e.employee_id)
	where	u.user_id not in (		-- only natural active persons
				select member_id
				from   group_distinct_member_map
				where  group_id = [im_profile_skill_profile]
			   UNION
				select	u.user_id
				from	users u,
					acs_rels r,
					membership_rels mr
				where	r.rel_id = mr.rel_id and
					r.object_id_two = u.user_id and
					r.object_id_one = -2 and
					mr.member_state != 'approved'
		) and
		u.user_id in (			-- all users who are part of a department
			select	ee.employee_id
			from	im_employees ee
			where	ee.department_id is not null
		    UNION			-- plus all employees
			select	member_id
			from	group_distinct_member_map
			where	group_id = [im_profile_employees]
		    UNION			-- plus all users with an assignment
			select	uu.user_id
			from	users uu
			where	u.user_id in ([join [array names user_hash] ","])
		)
		$user_where_clause
    "

    db_foreach user_info $user_info_sql {
        set user_hash($user_id) $user_id
	set object_name_hash($user_id) $user_name
	set object_type_hash($user_id) "user"
	set object_parent_hash($user_id) $department_id
	set object_availability_hash($user_id) $availability
	set collapse_hash($user_id) "c"
    }
    if {0 eq [llength [array names user_hash]]} { set user_hash(0) 0 }; # Avoid errors in an empty system
    set clicks([clock clicks -microseconds]) user_info


    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Collapse lines in the report"
    #
    set collapse_sql "
		select	object_id,
			open_p
		from	im_biz_object_tree_status
		where	user_id = :current_user_id and
			page_url = :page_url
    "
    db_foreach collapse $collapse_sql {
	set collapse_hash($object_id) $open_p
    }
    set clicks([clock clicks -microseconds]) init

    
    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Check for data consistency"
    #
    # Commented out - at the end of the file


    # ------------------------------------------------------------------
    ns_log Notice "percentage-report: Calculate the left dimension"
    # Take the project-user assignment hash and add the objects required
    # to create a chain from the top cost center through the user to the
    # sub-sub-task with the assighnent.
    #
    # The left dimension consists of:
    #
    # - The department
    # - The user
    # - The main project
    # - ... any level of sub-projects
    # - The leaf task with the assignment
    #
    set left_dimension {}

    # Add to the left dimension all project - user assignments

#    ad_return_complaint 1 [array names project_user_assignment_hash]
    foreach key [array names project_user_assignment_hash] {

	set tuple [split $key "-"]
	set project_id [lindex $tuple 0]
	set user_id [lindex $tuple 1]
	if {"" eq $project_id || "" eq $user_id} { ad_return_complaint 1 "left_scale:<br>Found bad key: $tuple" }

	# Found a standard assignment: $project_id-$user_id: Calculate parent_list
	set parent_list [list $project_id]
	set pid $object_parent_hash($project_id)
	while {"" ne $pid} {
	    lappend parent_list $pid
	    set pid $object_parent_hash($pid)
	}

	# Append the user assigned
	lappend parent_list $user_id

	# Append the user's cost center and it's parents
	set cc_id $object_parent_hash($user_id)
	while {"" ne $cc_id} {
	    lappend parent_list $cc_id
	    set cc_id $object_parent_hash($cc_id)
	}
	set parent_list [lreverse $parent_list]
	lappend left_dimension $parent_list
	set left_dimension_hash($key) $parent_list;      # remember the parents for aggregation
    }

    # Add to the left dimension all users from the users hash
    foreach user_id [array names user_hash] {

	set parent_list [list $user_id]

	# Append the user's cost center and it's parents
	set cc_id $object_parent_hash($user_id)
	while {"" ne $cc_id} {
	    lappend parent_list $cc_id
	    set cc_id $object_parent_hash($cc_id)
	}
	set parent_list [lreverse $parent_list]
	lappend left_dimension $parent_list
	set left_dimension_hash($user_id) $parent_list;      # remember the parents for aggregation
    }

#    ad_return_complaint 1 "<pre>[join [array get left_dimension_hash] "\n"]</pre>"



    set clicks([clock clicks -microseconds]) left_dimension
    # ad_return_complaint 1 "<pre>[join $left_dimension "\n"]</pre>"

    # Sort the left dimension
    set left_dimension_sorted [im_resource_management_sort_left_dimension \
				   -lol $left_dimension \
				   -object_type_list [array get object_type_hash]]
    set clicks([clock clicks -microseconds]) sorted_left_dimension
    # ad_return_complaint 1 "<pre>[join $left_dimension_sorted "\n"]</pre>"

    # "Smoothen" the left dimension, in order to create "stairs" to each objects
    # composed by it's super-objects
    set left_dimension_smooth [im_resource_management_smoothen_left_dimension \
				   -lol $left_dimension_sorted]
    set clicks([clock clicks -microseconds]) smooth_left_scale
    # ad_return_complaint 1 "<pre>[join $left_dimension_smooth "\n"]</pre>"

    
    # "Close" the left_dimension, according to user open/close actions
    set left_scale [im_resource_management_collapse_left_dimension \
				   -lol $left_dimension_smooth \
				   -collapse_list [array get collapse_hash]]
    set clicks([clock clicks -microseconds]) closed_left_scale
    # ad_return_complaint 1 "<pre>[join $left_scale_closed "\n"]</pre>"


    # Should we show every container line twice on the left side?
    set add_subtotals_p [parameter::get_from_package_key -package_key "intranet-resource-management" -parameter "AddSubtotalsP" -default 0]
    if {$add_subtotals_p} {
	set left_scale [im_resource_management_subtotals_left_dimension -lol $left_scale]
	set clicks([clock clicks -microseconds]) subtotals_left_scale
    }

    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Determine which object has children"
    #
    foreach l $left_dimension_smooth {
	# All objects have children, except for the last one
	foreach oid [lrange $l 0 end-1] {
	    set object_has_children_hash($oid) 1
	}
    }
    set clicks([clock clicks -microseconds]) children_hash


    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Aggregate percentage assignments up the project hierarchy"
    #
    # ad_return_complaint 1 "<pre>[join [array get project_user_assignment_hash] "\n"]</pre>"
    foreach key [array names project_user_assignment_hash] {
	set tuple [split $key "-"]
	set project_id [lindex $tuple 0]
	set user_id [lindex $tuple 1]
	set percentage $project_user_assignment_hash($key)
	set availability $object_availability_hash($user_id)
	set assigavail [expr $percentage * $availability / 100.0]

	# Get the list of parents for the project/user assignment combination
	set start_julian $project_start_julian_hash($project_id)
	set end_julian $project_end_julian_hash($project_id)
	set parent_list $left_dimension_hash($key)

	foreach oid $parent_list {
	    for {set j $start_julian} {$j <= $end_julian} {incr j} {

		# Skip weekends
		if {[info exists weekend_hash($j)]} { continue }

		# Calculate the date component of the key, depending on top_vars
		set key_list [util_memoize [list im_resource_management_top_scale_from_julian -julian $j -top_vars $top_vars]]
		lappend key_list $oid

		# Append the object part of the cell to the key
		set otype $object_type_hash($oid)
		switch $otype {
		    im_project { 
			lappend key_list $user_id
		    }
		}

		set key [join $key_list "-"]
		set v 0
		if {[info exists assignment_hash($key)]} { set v $assignment_hash($key) }
		set assignment_hash($key) [expr $v + $assigavail]
	    }
	}
    }
    # ad_return_complaint 1 "<pre>[join [array get assignment_hash] "\n"]</pre>"

    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Add absences to the aggregate"
    # ad_return_complaint 1 "<pre>absences_julian_hash=[array get absences_julian_hash]</pre>"
    #
    if {"1" eq $absences_included_in_project_planning_p} {
	foreach absence_key [array names absences_julian_hash] {
	    set tuple [split $absence_key "-"]
	    set j [lindex $tuple 0]
	    set user_id [lindex $tuple 1]

	    # Skip weekends
	    if {[info exists weekend_hash($j)]} { continue }

	    # Logic depending on absence types
	    set absence_type_id $absences_julian_hash($absence_key)
	    switch $absence_type_id {
		5005 { 
		    continue ; # Exclude bank holidays 
		}
	    }
	    
	    # Calculate how many percent are assigned
	    set percentage 100
	    set availability $object_availability_hash($user_id)
	    set assigavail [expr $percentage * $availability / 100.0]

	    # Get the list of objects from the left-hand side for the user
	    set parent_list $left_dimension_hash($user_id)
	    set key_list [util_memoize [list im_resource_management_top_scale_from_julian -julian $j -top_vars $top_vars]]
	    foreach oid $parent_list {
		set v 0
		set key "[join $key_list "-"]-$oid"
		if {[info exists assignment_hash($key)]} { set v $assignment_hash($key) }
		set assignment_hash($key) [expr $v + $assigavail]; # aggregate up the hierarchy
	    }
	}
    }

#    ad_return_complaint 1 "<pre>[join [array get assignment_hash] "\n"]</pre>"
    set clicks([clock clicks -microseconds]) aggregate


    # --------------------------------------------------
    ns_log Notice "percentage-report: Top Scale"
    #

    # Top scale is a list of lists like {{2006 01} {2006 02} ...}
    set top_scale {}
    set last_top_entry {}
    for {set i [dt_ansi_to_julian_single_arg $report_start_date]} {$i < [dt_ansi_to_julian_single_arg $report_end_date]} {incr i} {
	set top_entry [util_memoize [list im_resource_management_top_scale_from_julian -julian $i -top_vars $top_vars]]

	# "distinct clause": Add the values of top_vars to the top scale, if it is different from the last one...
	# This is necessary for aggregated top scales like weeks and months.
	set key [join $top_entry "-"]
	if {$top_entry ne $last_top_entry} {
	    lappend top_scale $top_entry
	    set last_top_entry $top_entry
	    set days_per_cell_hash($key) 0
	} 

	# Remember how many julian days are included in one cell
	set days_per_cell $days_per_cell_hash($key)
	if {![info exists weekend_hash($i)]} { incr days_per_cell }
	set days_per_cell_hash($key) $days_per_cell
	
    }

    # Determine how many date rows (year, month, day, ...) we've got
    set first_cell [lindex $top_scale 0]
    set top_scale_rows [llength $first_cell]
    # set left_scale_size [llength [lindex $left_vars 0]]
    set left_scale_size 2; # just one col for object + one col for percentage

    ns_log Notice "percentage-report: top_scale=$top_scale"
    set clicks([clock clicks -microseconds]) top_scale





    # -------------------------------------------------------------------------------------------
    ns_log Notice "percentage-report: Write out matrix"
    # 
    set matrix_html ""
    set row_ctr 0
    set show_row_task_p 0 
    foreach left_entry $left_scale {
	ns_log Notice "percentage-report: Write out table: left_entry=$left_entry"
	# example for left scale: {dept_id user_id main_pid ... pid}
	# {{12356} {12356 8858} {12356 8858 37450} {12356 8858 37450 37453} ...}

	set row_html ""
	set object_id [lindex $left_entry end]
	set object_type $object_type_hash($object_id)

	# Extract project_id and user_id (if part of the left_entry...)
	set project_id ""
	set user_id ""
	for {set i [expr [llength $left_entry]-1]} {$i > 0} {incr i -1} {
	    set oid [lindex $left_entry $i]
	    set otype $object_type_hash($oid)
	    if {"im_project" eq $otype && "" eq $project_id} { set project_id $oid }
	    if {"user" eq $otype && "" eq $user_id} { set user_id $oid }
	}

	# Display +/- GIF
	set closed_p "o"
	if {[info exists collapse_hash($object_id)]} { set closed_p $collapse_hash($object_id) }
	if {"o" == $closed_p} {
	    set url [export_vars -base $collapse_url {page_url return_url {open_p "c"} {object_id $object_id}}]
	    set collapse_html "<a href=$url>$gif_hash(minus_9)</a>"
	} else {
	    set url [export_vars -base $collapse_url {page_url return_url {open_p "o"} {object_id $object_id}}]
	    set collapse_html "<a href=$url>$gif_hash(plus_9)</a>"
	}

	set object_has_children_p [info exists object_has_children_hash($object_id)]
	if {!$object_has_children_p} { set collapse_html [util_memoize [list im_gif cleardot "" 0 9 9]] }
	if {$object_id eq $freelancers_department} { set collapse_html [util_memoize [list im_gif cleardot "" 0 9 9]] }; # fake dept - no collapse

	# Create cell
	set indent_level [expr [llength $left_entry] - 1]
	set object_name $object_name_hash($object_id)
	set object_url $url_hash($object_type)
	set oname_html "$collapse_html $gif_hash($object_type) <a href='$object_url$object_id'>$object_name</a>"

	# Indent the object name
	set indent_html ""
	for {set i 0} {$i < $indent_level} {incr i} { append indent_html "&nbsp; &nbsp; &nbsp; " }

	# Determine availabilityability per object
	set availability $object_availability_hash($object_id)
	set availability_html $availability
	if {"" ne $availability} { append availability_html "%" } else { set availability 0 }

	set class $rowclass([expr $row_ctr % 2])
	switch $object_type {
	    im_cost_center {
		append row_html "<tr class=plain valign=bottom>\n"
		set oname_html "<td><nobr>$indent_html<b>$oname_html</b></nobr></td>\n"
		set availability_html "<b>$availability_html</b>"
		set availability_title [lang::message::lookup "" intranet-resource-management.Availability_title_cost_center "
                    Sum of the availabililities of all active natual persons in this department"]
	    }
	    user {
		append row_html "<tr class=$class valign=bottom>\n"
		set oname_html "<td><nobr>$indent_html$oname_html</nobr></td>\n"
		set availability_title [lang::message::lookup "" intranet-resource-management.Availability_title_default "
                    Availability of the user for project work"]

		# Check for users with an empty department - create an error message
		if {$company_cost_center eq $object_parent_hash($object_id)} {
		    set availability_html "<font color=red><b>$availability_html</b></font>"
		    set availability_title [lang::message::lookup "" intranet-resource-management.User_without_department "Please check the department of this user."]
		}
	    }
	    default {
		append row_html "<tr class=$class valign=bottom>\n"
		set oname_html "<td><nobr>$indent_html$oname_html</nobr></td>\n"
		set availability_title ""
	    }
	}

	append row_html "<td><span title='$availability_title'>$availability_html</span></td>\n"
	append row_html $oname_html

	# ------------------------------------------------------------
	ns_log Notice "percentage-report: Start writing out the matrix elements"
	#
	foreach top_entry $top_scale {

	    set key_list $top_entry
	    set days_per_cell 1
	    set key [join $top_entry "-"]
	    if {[info exists days_per_cell_hash($key)]} { set days_per_cell $days_per_cell_hash($key) }
	    if {0 eq $days_per_cell} { set days_per_cell 0.000001 }

	    # Check for Absences. Weekends are already included in the absences_julian_hash(..)
	    set list_of_absences ""
	    set absence_key "[join $key_list "-"]-$user_id"
	    if {[info exists absences_hash($absence_key)]} {
		set list_of_absences $absences_hash($absence_key)
	    }

	    set col_attrib ""
	    if {"" != $list_of_absences} {
		set color [util_memoize [list im_absence_mix_colors $list_of_absences]]
		ns_log Notice "write_out_matrix: im_absence_mix_colors $list_of_absences -> $color"
		set col_attrib "bgcolor=#$color"
	    }
	    if {[im_resource_management_top_entry_is_weekend_p -top_vars $top_vars -top_entry $top_entry]} { 
		set col [im_absence_type_color -absence_type_id [im_user_absence_type_bank_holiday]]
		set col_attrib "bgcolor=#$col" 
	    }

	    
	    # Format user or department cells - choose a font color according to overallocation
	    set cell_html "&nbsp;&nbsp;&nbsp;&nbsp;"
	    set key "[join $key_list "-"]-$object_id"
	    # ad_return_complaint 1 "<pre>$key<br>[array names assignment_hash]</pre>"
	    if {[info exists assignment_hash($key)]} { 
		set assig [expr round($assignment_hash($key)) / $days_per_cell]
		set color "black"
		if {$availability > 0} {
		    set overassignment_ratio [expr (1.0 * $assig / $availability) - 1.0]
		    # <= 1.0 -> black=#00000, >1.5 -> red=#FF0000
		    set ratio [expr round(min(max($overassignment_ratio,0) * 700.0, 255))]
		    set color "#[format %x $ratio]0000"
		    if {"" ne $assig} { set assig "$assig%" }
		    set cell_html "<font color=$color>$assig</font>"
		}
	    }

	    # Normal project assignment - don't compare and don't change color
	    set key "[join $key_list "-"]-$project_id-$user_id"
	    if {[info exists assignment_hash($key)]} { 
		set assig [expr round($assignment_hash($key)) / $days_per_cell] 
		if {"" ne $assig} { set assig "$assig%" }
		set cell_html $assig
	    }

	    switch $object_type {
		im_cost_center {
		    set title "Sum of availability of department members multiplied with % project assignments"
		    append row_html "<td $col_attrib><b><span>$cell_html</span></b></td>\n" 
		}
		user { 
		    set title "Sum of availability multiplied with % project assignments"
		    append row_html "<td $col_attrib><span>$cell_html</span></td>\n" 
		}
		im_project { 
		    set title "Sum of all % project assignments to project or tasks"
		    append row_html "<td $col_attrib><span>$cell_html</span></td>\n" 
		}
		default { ad_return_complaint 1 "format-cells:<br>Found invalid object_type=$object_type" }
	    }
	}
        append row_html "</tr>\n"

	append matrix_html $row_html
	incr row_ctr
    }
    set clicks([clock clicks -microseconds]) write_matrix


    # ---------------------------------------------------------------------
    ns_log Notice "percentage-report: Write out the header of the table"
    # Each date entry starts with the julian of the date, so we have to skip row=0
    #
    set header_html ""
    for {set row 0} {$row < $top_scale_rows} { incr row } {
	
	# Create the name of the date part in the very first (left) cell
	append header_html "<tr class=rowtitle>\n"
	set top_var [lindex $top_vars $row]
	set col_l10n [lang::message::lookup "" "intranet-resource-management.Dim_$top_var" $top_var]
	if {0 == $row} {
	    set zoom_in "<a href=[export_vars -base $this_url {top_vars {zoom "in"}}]>$gif_hash(magnifier_zoom_in)</a>\n" 
	    set zoom_out "<a href=[export_vars -base $this_url {top_vars {zoom "out"}}]>$gif_hash(magnifier_zoom_out)</a>\n" 
	    set col_l10n "<!-- $zoom_in $zoom_out --> $col_l10n \n" 
	}
	append header_html "<td class=rowtitle colspan=$left_scale_size align=right>$col_l10n</td>\n"
	
	# Loop through the date dimension
	for {set col 0} {$col <= [expr [llength $top_scale]-1]} { incr col } {
	    set scale_entry [lindex $top_scale $col]
	    set scale_item [lindex $scale_entry $row]
	    
	    # Check if the previous item was of the same content
	    set prev_scale_entry [lindex $top_scale $col-1]
	    set prev_scale_item [lindex $prev_scale_entry $row]

	    # Check for the "sigma" sign. We want to display the sigma
	    # every time (disable the colspan logic)
	    if {$scale_item == $sigma} { 
		append header_html "\t<td class=rowtitle>$scale_item</td>\n"
		continue
	    }

	    # Prev and current are same => just skip.
	    # The cell was already covered by the previous entry via "colspan"
	    if {$prev_scale_item == $scale_item} { continue }
	    
	    # This is the first entry of a new content.
	    # Look forward to check if we can issue a "colspan" command
	    set colspan 1
	    set next_col [expr $col+1]
	    while {$scale_item == [lindex $top_scale $next_col $row]} {
		incr next_col
		incr colspan
	    }
	    append header_html "\t<td class=rowtitle colspan=$colspan>$scale_item</td>\n"
	}
	append header_html "</tr>\n"
    }
    set clicks([clock clicks -microseconds]) write_header

    # ------------------------------------------------------------
    # Close the table
    #
    set html "<table cellspacing=3 cellpadding=3 valign=bottom>\n"
    append html $header_html
    append html $matrix_html
    append html "\n</table>\n"
    append html $err_protocol
    set clicks([clock clicks -microseconds]) close_table


    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Profiling HTML"
    #
    set profiling_html ""
    set first_click 0
    if {$debug_p} {
	set profiling_html "<br>&nbsp;<br><table>\n"
	set last_click 0
	foreach click [lsort -integer [array names clicks]] {
	    if {0 == $last_click} { 
		set last_click $click 
		set first_click $click
	    }
	    append profiling_html "
<tr>
    <td>$click</td>
    <td>$clicks($click)</td>
    <td align=right>[expr round(10.0 * ($click - $first_click) / 1000.0) / 10.0]</td>
    <td align=right>[expr round(10.0 * ($click - $last_click) / 1000.0) / 10.0]</td>
</tr>
            "
	    set last_click $click
	}
	append profiling_html "<tr><td> </td><td><b>Total</b></td><td align=right>[expr round(10.0 * ($last_click - $first_click) / 1000.0) / 10.0]</td></tr>\n"
	append profiling_html "<tr><td colspan=3>&nbsp;</tr>\n"
	append profiling_html "</table>\n"
    }

    append html $profiling_html
    return $html
}



# ---------------------------------------------------------------
# Auxillary functions for percentage report
# ---------------------------------------------------------------

ad_proc -public im_resource_mgmt_resource_planning_percentage_absences {
    -report_start_date
    -report_end_date
    -user_where_clause
} {
    Extract absences into a hash
} {

    set absences_sql "
	-- Direct absences for a user within the period
	select	u.user_id,
		to_char(a.start_date,'J') as absence_start_julian,
		to_char(a.end_date,'J') as absence_end_julian,
		a.absence_type_id
	from 	im_user_absences a,
		users u
	where	a.group_id is null and
		a.owner_id = u.user_id and
		a.start_date <= :report_end_date::date and
		a.end_date   >= :report_start_date::date
		$user_where_clause
    UNION
	-- Absences via groups - Check if the user is a member of group_id
	select	u.user_id,
		to_char(a.start_date,'J') as absence_start_julian,
		to_char(a.end_date,'J') as absence_end_julian,
		a.absence_type_id
	from	im_user_absences a,
		users u,
		group_distinct_member_map mm
	where	a.group_id = mm.group_id and
		u.user_id = mm.member_id and
		a.start_date <= :report_end_date::date and
		a.end_date   >= :report_start_date::date
		$user_where_clause
    "
    db_foreach absences $absences_sql {
	for {set i $absence_start_julian} {$i <= $absence_end_julian} {incr i} {
	    set val {}
	    set key "$i-$user_id"
	    if {[info exists absences_julian_hash($key)]} { set val $absences_julian_hash($key) }
	    lappend val $absence_type_id
	    set absences_julian_hash($key) $val
	}
    }

    return [array get absences_julian_hash]
}



ad_proc -public im_resource_management_sort_left_dimension {
    -lol
    -object_type_list
} {
    Expects a list-of-lists composed of integer values representing 
    cost centers, users, projects and tasks.
    Returns the lol sorted according to the type of the objects in 
    order: ccs, users, projects, tasks.
} {
    ns_log Notice "sort_left_dimension: lol=$lol"
    array set object_type_hash $object_type_list
    # ad_return_complaint 1 "<pre>[join $lol "\n"]</pre>"

    # Go through the list-of-lists and add a prefix according to the object type.
    # This way object type will take precedence over the object_id.
    set otype_lol [list]

    # Add a prefix to each object_id according to the object type
    foreach l $lol {
	set otype_l [list]
	foreach oid $l {
	    set otype $object_type_hash($oid)
	    switch $otype {
		user              { set i [expr 10000000 + $oid] }
		im_cost_center    { set i [expr 20000000 + $oid] }
		im_project        { set i [expr 30000000 + $oid] }
		defalt            { ad_return_complaint 1 "im_resource_management_sort_left_dimension: unknown object type: '$otype'" }
	    }
	    lappend otype_l $i
	}
	lappend otype_lol $otype_l
    }
    # ad_return_complaint 1 "<pre>[join $otype_lol "\n"]</pre>"

    # Use a plain string sort on the object_ids that have all the 
    # same length and a prefix according to their object type
    set otype_lol_sorted [qsort $otype_lol]
    # ad_return_complaint 1 $otype_lol

    # Remove the prefixes in order to restore the normal list
    set lol [list]
    foreach otype_l $otype_lol_sorted {
	set l [list]
	foreach otype_oid $otype_l {
	    set oid [expr $otype_oid % 10000000]
	    lappend l $oid
	}
	lappend lol $l
    }

#    ad_return_complaint 1 "<pre>[join $lol "\n"]</pre>"

    return $lol
}





ad_proc -public im_resource_management_smoothen_left_dimension {
    -lol
} {
    Expects a list-of-lists composed of integer values representing 
    cost centers, users, projects and tasks. However, this list just
    contains the final fine-grain assignments.
    This procedure adds missing intermediate objects so that every
    assignment is preceded by the hierarchy object CCs and other
    objects leading to it.
} {
    ns_log Notice "sort_left_dimension: lol=$lol"
    set result [list]
    set last_l [list]
    foreach l $lol {
	ns_log Notice "smoothen_left_dimension: "
	ns_log Notice "smoothen_left_dimension: l=$l: last_l=$last_l"

	# Calculate the common part of l and last_l
	set last_idx [llength $l]
	set a [lrange $l 0 $last_idx]
	set b [lrange $last_l 0 $last_idx]
	while {$a ne $b && $last_idx > 0} {
	    incr last_idx -1
	    set a [lrange $l 0 $last_idx]
	    set b [lrange $last_l 0 $last_idx]
	}
	set last_l $b
	ns_log Notice "smoothen_left_dimension: l=$l: last_l=$last_l, idx=$last_idx, last_l=$last_l"

	# Now add lines in order to get from last_l to l in "steps" of one object each.
	# last_l has already been part of result, so we don't need to include it again.
	while {[llength $last_l] < [llength $l]} {
	    lappend last_l [lindex $l [llength $last_l]]
	    lappend result $last_l
	    ns_log Notice "smoothen_left_dimension: l=$l, last_l=$last_l: adding"
	}
	# Now last_l should be identical to l
    }

    return $result
}




ad_proc -public im_resource_management_subtotals_left_dimension {
    -lol
} {
    Adds a subtotal line at the end of every department or user
} {
    ns_log Notice "subtotals_left_dimension: lol=$lol"
    set result [list]
    set last_l [list]
    foreach l $lol {
	ns_log Notice "subtotals_left_dimension: "
	ns_log Notice "subtotals_left_dimension: l=$l: last_l=$last_l"
	set org_l $l

	# We need to add a subtotal line
	while {[llength $l] < [llength $last_l]} {
	    set last_l [lrange $last_l 0 end-1]
	    lappend result $last_l
	}

	lappend result $org_l
	set last_l $org_l
    }

    return $result
}









ad_proc -public im_resource_management_collapse_left_dimension {
    -lol
    -collapse_list
} {
    Expects a list-of-lists composed of integer values representing 
    cost centers, users, projects and tasks.
    This procedure eliminates those entries that include at least
    one "closed" item.
} {
    ns_log Notice "collapse_left_dimension: lol=$lol"
    array set collapse_hash $collapse_list
    set result [list]

    foreach l $lol {
	set status "o"
	foreach oid [lrange $l 0 end-1] {
	    if {[info exists collapse_hash($oid)]} {
		if {"c" eq $collapse_hash($oid)} {
		    set status "c"
		}
	    }
	}
	if {"o" eq $status} { lappend result $l }
    }

#    ad_return_complaint 1 $result

    return $result
}



ad_proc -public im_resource_management_top_scale_from_julian {
    -julian:required
    -top_vars:required
} {
    Calculate the date component for the julian date, depending on top_vars
} {
    array set date_hash [util_memoize [list im_date_julian_to_components $julian] 100000]
    set key_list [list]
    foreach top_var $top_vars {
	set date_val $date_hash($top_var)
	lappend key_list $date_val
    }
    return $key_list
}


ad_proc -public im_resource_management_top_entry_is_weekend_p {
    -top_vars:required
    -top_entry:required
} {
    Returns true if the top entry refers to a weekend.
    We only handle the cases "year month_of_year day_of month"
    and "year week_of_year day_of_week" here
} {
    # ad_return_complaint 1 $top_vars
    switch $top_vars {
	"year month_of_year day_of_month" {
	    set j [dt_ansi_to_julian [lindex $top_entry 0] [lindex $top_entry 1] [lindex $top_entry 2]]
	    array set date_comps_hash [im_date_julian_to_components $j]
	    set dow $date_comps_hash(day_of_week)
	    switch $dow {
		6 - 7 { return 1 }
	    }
	}
	"year week_of_year day_of_week" {
	    set dow [lindex $top_entry 2]
	    switch $dow {
		6 - 7 { return 1 }
	    }
	}
    }
    return 0
}
