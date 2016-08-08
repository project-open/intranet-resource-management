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

ad_proc -public im_resource_mgmt_resource_planning_percentage {
    {-top_vars "year week_of_year day"}
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
    {-show_all_employees_p 1}
    {-show_departments_only_p "0" }
    {-excluded_group_ids "" }
    {-return_url ""}
    {-page_url:required}
    {-debug:boolean}
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
    set debug_p 1

    # Department to use, when user is not assigned to one 
    set company_cost_center [im_cost_center_company]
    set default_department [parameter::get_from_package_key -package_key "intranet-resource-management" -parameter "DefaultCostCenterId" -default $company_cost_center]

    if {"" == $show_departments_only_p} { set show_departments_only_p 0 }
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
    set cost_center_url "/intranet-cost/cost-centers/view?cost_center_id="
    set user_url "/intranet/users/view?user_id="

    # Hash for URLs per object type
    set url_hash(user) $user_url
    set url_hash(im_project) $project_url
    set url_hash(im_cost_center) $cost_center_url

    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Conditional SQL where clause"
    #
    set criteria [list]
    if {"" != $report_customer_id && 0 != $report_customer_id} { lappend criteria "parent.company_id = :report_customer_id" }
    if {"" != $report_project_id && 0 != $report_project_id} { lappend criteria "parent.project_id in ([join $report_project_id ", "])" }
    if {"" != $report_project_status_id && 0 != $report_project_status_id} { 
	lappend criteria "parent.project_status_id in ([join [im_sub_categories $project_status_id] ", "])" 
    }
    if {"" != $report_project_type_id && 0 != $report_project_type_id} { 
	lappend criteria "parent.project_type_id in ([join [im_sub_categories $report_project_type_id] ", "])" 
    }
    if {"" != $report_user_id && 0 != $report_user_id} { lappend criteria "u.user_id in ([join $report_user_id ","])" }

    set union_criteria ""
    if {"" != $report_employee_cost_center_id && 0 != $report_employee_cost_center_id} {
	lappend criteria "u.user_id in (
		select	employee_id
		from	im_employees
		where	department_id in ([join [im_sub_cost_center_ids $report_employee_cost_center_id] ","])
	)"

	set union_criteria " 
                    and     e.employee_id in (
                                select  employee_id
                                from    im_employees
                                where   department_id in ([join [im_sub_cost_center_ids $report_employee_cost_center_id] ","])
			    )
	"
    } 

    if {"" ne $excluded_group_ids && 0 ne $excluded_group_ids} {
        lappend criteria "u.user_id not in (
            select  object_id_two from acs_rels where object_id_one in ([join $excluded_group_ids ","]) and rel_type = 'membership_rel'
        )"
    }

    set where_clause [join $criteria " and\n\t\t\t"]
    if { $where_clause ne "" } { set where_clause " and $where_clause" }


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
    ns_log Notice "percentage-report: Store information about each day into hashes for speed"
    #
    for {set i $report_start_julian} {$i <= $report_end_julian} {incr i} {
	array unset date_comps
	array set date_comps [im_date_julian_to_components $i]

	# Day of Week
	set dow $date_comps(day_of_week)
	set day_of_week_hash($i) $dow

	# Weekend
	if {0 == $dow || 6 == $dow || 7 == $dow} { set weekend_hash($i) 5 }
	
	# Start of Week Julian
	set start_of_week_julian_hash($i) [expr $i - $dow]
    }
    set clicks([clock clicks -microseconds]) weekends


    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Absences - Determine when the user is away"
    #
    array set absences_hash [im_resource_mgmt_resource_planning_percentage_absences \
				 -report_start_date $report_start_date \
				 -report_end_date $report_end_date \
				 -weekend_list [array get weekend_hash] \
    ]
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
			and parent.end_date >= :report_start_date::date
			and parent.start_date <= :report_end_date::date
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
			$where_clause
		order by
			child.tree_sortkey,
			u.user_id
    "
    db_foreach hierarchy $assignment_sql {
	# Store the actual assignment
	set key "$project_id-$user_id"
	set assignment_hash($key) $percentage

	# Calculate the list of children of each object
	set children []
	if {[info exists object_children_hash($parent_id)]} { set children $object_children_hash($parent_id) }
	lappend children $project_id
	set object_children_hash($parent_id) $children

	# Store properties into hashes for quick access later
	set object_name_hash($project_id) $project_name
	set object_type_hash($project_id) "im_project"
	set project_parent_hash($project_id) $parent_id
	set project_start_julian_hash($project_id) $child_start_julian
	set project_end_julian_hash($project_id) $child_end_julian
	set project_level_hash($project_id) $level
	set main_project_hash($main_project_id) $main_project_id
	set user_hash($user_id) $user_id
	set object_availability_hash($project_id) ""
    }
    set clicks([clock clicks -microseconds]) hierarchy

    # --------------------------------------------
    ns_log Notice "percentage-report: Cost center information"
    #
    set cc_sql "
	select	cc.*,
		round(length(cc.cost_center_code) / 2) as indent_level,
		coalesce((select sum(coalesce(e.availability, 0))
		from	im_employees e
		where	e.department_id = cc.cost_center_id and
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
		), 0) as resources_available_percent
	from	im_cost_centers cc
	where	1 = 1
	order by cc.cost_center_code
    "
    db_foreach ccs $cc_sql {
	set cc_parent_hash($cost_center_id) $parent_id
	set cc_indent_hash $indent_level
	set object_type_hash($cost_center_id) "im_cost_center"
	set object_name_hash($cost_center_id) $cost_center_name

	# Aggregate resources upward
	set object_availability_hash($cost_center_id) $resources_available_percent
	set parent_cc_id $parent_id
	set cnt 0
	while {"" ne $parent_cc_id} {
	    set val $object_availability_hash($parent_cc_id)
	    set val [expr $val + $resources_available_percent]
	    set object_availability_hash($parent_cc_id) $val
	    set parent_cc_id $cc_parent_hash($parent_cc_id)
	    incr cnt
	    if {$cnt > 20} { ad_return_complaint 1 "Percentage Report:<br>Infinite loop in dept aggregation" }
	}
    }
    set clicks([clock clicks -microseconds]) department_hierarchy


    # --------------------------------------------
    ns_log Notice "percentage-report: User department information"
    #
    set user_hash(0) 0
    set user_info_sql "
	select	u.user_id,
		coalesce(e.department_id, :default_department) as department_id,
		coalesce(e.availability, 100) as availability,
		im_name_from_user_id(u.user_id) as user_name
	from	users u
		LEFT OUTER JOIN im_employees e ON (u.user_id = e.employee_id)
	where	u.user_id not in (	     -- only natural active persons
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
    "
    if {1 eq $show_all_employees_p} {
	append user_info_sql "and (u.user_id in (select member_id from group_distinct_member_map where group_id = [im_profile_employees])
                OR u.user_id in ([join [array names user_hash] ","]))
        " 
    } else {
	append user_info_sql "and u.user_id in ([join [array names user_hash] ","])" 
    }
    db_foreach user_info $user_info_sql {
	set object_name_hash($user_id) $user_name
	set object_type_hash($user_id) "user"
	set user_department_hash($user_id) $department_id
	set object_availability_hash($user_id) $availability
    }
    set clicks([clock clicks -microseconds]) user_info

    
    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Check for data consistency"
    #
    foreach project_id [array names project_parent_hash] {
	set project_name $object_name_hash($project_id)

	# Check that the project has valid start-end dates
	set project_start_julian $project_start_julian_hash($project_id)
	set project_end_julian $project_end_julian_hash($project_id)
	if {"" eq $project_start_julian} {
	    append err_protocol "<li>Found a project with empty start_date:<br>Project #$project_id - $project_name"
	    set project_start_julian_hash($project_id) $now_julian
	}
	if {"" eq $project_end_julian} {
	    append err_protocol "<li>Found a project with empty end_date:<br>Project #$project_id - $project_name"
	    set project_end_julian_hash($project_id) $now_julian
	}

	# Check that the parent has valid start-end dates
	set parent_id $project_parent_hash($project_id)
	if {"" eq $parent_id} { continue }
	set parent_name $object_name_hash($parent_id)
	if {![info exists project_parent_hash($parent_id)]} {
	    append err_protocol "<li>Found a project inconsistency:<br>Project #$parent_id does not exist in the project hierarchy"
	}
	set parent_start_julian $project_start_julian_hash($parent_id)
	set parent_end_julian $project_end_julian_hash($parent_id)
	if {"" eq $parent_start_julian} {
	    append err_protocol "<li>Found a project with empty start_date:<br>Project #$parent_id"
	}
	if {"" eq $parent_end_julian} {
	    append err_protocol "<li>Found a project with empty end_date:<br>Project #$parent_id"
	}

	# Check that the parent start-end interval includes the child start-end interval
	if {$project_start_julian < $parent_start_julian} {
	    append err_protocol "<li>Found a sub-project that starts earlier than its parent:<br>Project #$project_id, parent #$parent_id"
	}
	if {$project_end_julian > $parent_end_julian} {
	    append err_protocol "<li>Found a sub-project that ends earlier than its parent:<br>Project #$project_id, parent #$parent_id"
	}
    }

    # Check consistency: every parent should also include the assignments of it's children
    foreach key [array names assignment_hash] {
	set tuple [split $key "-"]
	set project_id [lindex $tuple 0]
	set user_id [lindex $tuple 1]
	set parent_id $project_parent_hash($project_id)
	if {"" eq $parent_id} { continue }

	set parent_key "$parent_id-$user_id"
	if {![info exists assignment_hash($parent_key)]} {
	    append err_protocol "<li>Found a child project with more assignments that it's parent:<br>
            Project: #$project_id, parent: #$parent_id, user: $user_id"
	}
    }
    set clicks([clock clicks -microseconds]) consistency


    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Aggregate percentage assignments up the project hierarchy"
    #
    db_foreach aggregate_loop $assignment_sql {
	# We get the rows ordered by tree_sortkey with main projects before their children.
	# So we can directly aggregate along the hierarcy.
	set pid $parent_id
	while {"" ne $pid} {
	    set key "$pid-$user_id"
	    set assignment_hash($key) [expr $assignment_hash($key) + $percentage]
	    set pid $project_parent_hash($pid)
	}

	# Aggregate per user
	set key $user_id
	set perc 0
	if {[info exists assignment_hash($key)]} { set perc $assignment_hash($key) }
	set assignment_hash($key) [expr $perc + $percentage]

	# Aggregate per cost center
	set department_id $user_department_hash($user_id)
	set cnt 0
	while {"" ne $department_id} {
	    set perc 0
	    if {[info exists assignment_hash($department_id)]} { set perc $assignment_hash($department_id) }
	    set assignment_hash($department_id) [expr $perc + $percentage]
	    set department_id $cc_parent_hash($department_id)
	    incr cnt
	    if {$cnt > 20} { ad_return_complaint 1 "Percentage report:<br>Infinite loop in dept matrix aggregation" }
	}
    }
    set clicks([clock clicks -microseconds]) aggregate


    # ------------------------------------------------------------------
    ns_log Notice "percentage-report: Calculate the left dimension"
    #
    # The dimension is composed by:
    #
    # - The department
    # - The user
    # - The main project
    # - ... any level of sub-projects
    # - The leaf task
    #
    set left_dimension {}
    foreach key [array names assignment_hash] {

	set tuple [split $key "-"]
	set project_id [lindex $tuple 0]
	set user_id [lindex $tuple 1]
	if {"" ne $user_id} {

	    # Found a standard assignment: $project_id-$user_id: Calculate parent_list
	    set parent_list [list $project_id]
	    set pid $project_parent_hash($project_id)
	    while {"" ne $pid} {
		lappend parent_list $pid
		set pid $project_parent_hash($pid)
	    }
	    
	    lappend parent_list $user_id
	    set cc_id $user_department_hash($user_id)

	} else {

	    continue

	    # Found a special assignment: Either a user_id or a cc_id
	    set otype $object_type_hash($project_id)
	    switch $otype {
		"user" {
		    set user_id $project_id
		    set department_id $user_department_hash($user_id)
		    set parent_list [list $user_id]
		    set cc_id $department_id
		}
		"im_cost_center" {
		    set cc_id $project_id
		}
		default {
		    ad_return_complaint 1 "Found a single-object assignment that is neither user nor cc"
		}
	    }
	}

	# Append the CC parents before adding to the left dimension. $cc_id was set above.
	while {"" ne $cc_id} {
	    lappend parent_list $cc_id
	    set cc_id $cc_parent_hash($cc_id)
	}
	set parent_list [lreverse $parent_list]
	lappend left_dimension $parent_list

    }
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
    set left_scale_closed $left_dimension_smooth
    set clicks([clock clicks -microseconds]) closed_left_scale
    # ad_return_complaint 1 "<pre>[join $left_scale_closed "\n"]</pre>"
    set left_scale $left_scale_closed

    # --------------------------------------------------
    ns_log Notice "percentage-report: Top Scale"
    #

    # Top scale is a list of lists like {{2006 01} {2006 02} ...}
    set top_scale {}
    set last_top_dim {}
    for {set i [dt_ansi_to_julian_single_arg $report_start_date]} {$i <= [dt_ansi_to_julian_single_arg $report_end_date]} {incr i} {
	array unset date_hash
	array set date_hash [im_date_julian_to_components $i]

	# Each entry in the top_scale is a list of date parts defined by top_vars
	set top_dim [list $i]
	foreach top_var $top_vars {
	    set date_val ""
	    catch { set date_val $date_hash($top_var) }
	    lappend top_dim $date_val
	}

	# "distinct clause": Add the values of top_vars to the top scale, if it is different from the last one...
	# This is necessary for aggregated top scales like weeks and months.
	if {$top_dim != $last_top_dim} {
	    lappend top_scale $top_dim
	    set last_top_dim $top_dim
	}
    }

    # Determine how many date rows (year, month, day, ...) we've got
    set first_cell [lindex $top_scale 0]
    set top_scale_rows [llength $first_cell]
    set left_scale_size [llength [lindex $left_vars 0]]

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

	# Display +/- logic
	set closed_p "c"
	if {[info exists collapse_hash($object_id)]} { set closed_p $collapse_hash($object_id) }
	if {"o" == $closed_p} {
	    set url [export_vars -base $collapse_url {page_url return_url {open_p "c"} {object_id $object_id}}]
	    set collapse_html "<a href=$url>$gif_hash(minus_9)</a>"
	} else {
	    set url [export_vars -base $collapse_url {page_url return_url {open_p "o"} {object_id $object_id}}]
	    set collapse_html "<a href=$url>$gif_hash(plus_9)</a>"
	}

	set object_has_children_p 0
	if {[info exists object_children_hash($object_id)]} {
	    set object_has_children_p [llength $object_children_hash($object_id)]
	}
	set object_has_children_p 1; # !!!
	if {!$object_has_children_p} { set collapse_html [util_memoize [list im_gif cleardot "" 0 9 9]] }

	# Create cell
	set indent_level [llength $left_entry]
	set object_name $object_name_hash($object_id)
	set object_url $url_hash($object_type)
	set cell_html "$collapse_html $gif_hash($object_type) <a href='$object_url$object_id'>$object_name</a>"

	# Indent the object name
	set indent_html ""
	for {set i 0} {$i < $indent_level} {incr i} { append indent_html "&nbsp; &nbsp; &nbsp; " }

	set class $rowclass([expr $row_ctr % 2])
	append row_html "<tr class=$class valign=bottom>\n"
	append row_html "<td><nobr>$indent_html$cell_html</nobr></td>\n"

	set avail $object_availability_hash($object_id)
	if {"" ne $avail} { append avail "%" }
	append row_html "<td>$avail</td>\n"

	# ------------------------------------------------------------
	ns_log Notice "percentage-report: Start writing out the matrix elements"
	# ------------------------------------------------------------

	for {set j $report_start_julian} {$j < $report_end_julian} {incr j} {

	    # Check for Absences
	    set list_of_absences ""
	    if {[info exists weekend_hash($j)]} {
		append list_of_absences $weekend_hash($j)
	    }
	    set absence_key "$j-$user_id"
	    if {[info exists absences_hash($absence_key)]} {
		append list_of_absences $absences_hash($absence_key)
	    }

	    set col_attrib ""
	    if {"" != $list_of_absences} {
		set color [util_memoize [list im_absence_mix_colors $list_of_absences]]
		set col_attrib "bgcolor=#$color"
	    }
	    
	    # Check the percentage assignment
	    set cell_html "x"

	    append row_html "<td $col_attrib>$cell_html</td>\n"
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
    for {set row 1} {$row < $top_scale_rows} { incr row } {
	
	# Create the name of the date part in the very first (left) cell
	append header_html "<tr class=rowtitle>\n"
	set top_var [lindex $top_vars [expr $row-1]]
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

    if {0 == $row_ctr} {
	set no_rows_msg [lang::message::lookup "" intranet-resource-management.No_rows_selected "
		No rows found.<br>
		Maybe there are no assignments of users to projects in the selected period?
	"]
	append html "<br><b>$no_rows_msg</b>\n"
    }

    append html $err_protocol
    set clicks([clock clicks -microseconds]) close_table


    # ------------------------------------------------------------
    ns_log Notice "percentage-report: Profiling HTML"
    #
    set profiling_html ""
    if {$debug_p} {
	set profiling_html "<br>&nbsp;<br><table>\n"
	set last_click 0
	foreach click [lsort -integer [array names clicks]] {
	    if {0 == $last_click} { 
		set last_click $click 
		set first_click $click
	    }
	    append profiling_html "<tr><td>$click</td><td>$clicks($click)</td><td align=right>[expr ($click - $last_click) / 1000.0]</td></tr>\n"
	    set last_click $click
	}
	append profiling_html "<tr><td> </td><td><b>Total</b></td><td align=right>[expr ($last_click - $first_click) / 1000.0]</td></tr>\n"
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
    -weekend_list
} {

} {
    array set weekend_hash $weekend_list

    set absences_sql "
	-- Direct absences for a user within the period
	select	owner_id,
		to_char(start_date,'J') as absence_start_julian,
		to_char(end_date,'J') as absence_end_julian,
		absence_type_id
	from 	im_user_absences
	where	group_id is null and
		start_date <= :report_end_date::date and
		end_date   >= :report_start_date::date
    UNION
	-- Absences via groups - Check if the user is a member of group_id
	select	mm.member_id as owner_id,
		to_char(start_date,'J') as absence_start_julian,
		to_char(end_date,'J') as absence_end_julian,
		absence_type_id
	from	im_user_absences a,
		group_distinct_member_map mm
	where	a.group_id = mm.group_id and
		start_date <= :report_end_date::date and
		end_date   >= :report_start_date::date
    "
    db_foreach absences $absences_sql {
	for {set i $absence_start_julian} {$i <= $absence_end_julian} {incr i} {

	    # Aggregate per day
	    set key "$i-$owner_id"
	    set val ""
	    if {[info exists absences_hash($key)]} { set val $absences_hash($key) }
	    append val [expr $absence_type_id - 5000]
	    set absences_hash($key) $val


	    # Aggregate per week, skip weekends
	    set week_julian [util_memoize [list im_date_julian_to_week_julian $i]]
	    set key "$week_julian-$owner_id"
	    set val ""
	    if {[info exists absences_hash($key)]} { set val $absences_hash($key) }
	    append val [expr $absence_type_id - 5000]
	    set absences_hash($key) $val
	}
    }

    return [array get absences_hash]
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
