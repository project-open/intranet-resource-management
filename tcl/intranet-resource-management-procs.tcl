# /packages/intranet-resource-management/tcl/intranet-resource-management.tcl
#
# Copyright (C) 2010-2013 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

ad_library {
    Report on and modify resource assignments to tasks of various types.
    @author frank.bergmann@project-open.com
    @author klaus.hofeditz@project-open.com
}

# ---------------------------------------------------------------
# Reusable Resource Management Components
# ---------------------------------------------------------------

ad_proc -public im_resource_management_cost_centers {
    {-start_date ""}
    {-end_date ""}
    {-limit_to_ccs_with_resources_p 1}
} {
    Returns a Hash with the list of all cost_centers in the system
    with name and the "perpetually" available users (member of the 
    cost_center).
} {
    # Variables of 
    set vars [im_rest_object_type_columns -include_acs_objects_p 0 -rest_otype "im_cost_center"]

    set limit_to_ccs_with_data ""
    if {$limit_to_ccs_with_resources_p} {
	set limit_to_ccs_with_data "and av.availability_percent is not null"
    }

    set cc_sql "
	select	cc.cost_center_id as object_id,
		cc.*,
		av.availability_percent
	from	im_cost_centers cc
		LEFT OUTER JOIN (
			select	e.department_id,
				sum(e.availability) as availability_percent
			from	im_employees e
			where	e.employee_id in (
				select	r.object_id_two
				from	acs_rels r,
					membership_rels mr
				where	r.rel_id = mr.rel_id and
					r.object_id_one = -2 and
					mr.member_state = 'approved'
				)
			group by e.department_id
		) av ON cc.cost_center_id = av.department_id
	where	1=1
		$limit_to_ccs_with_data
	order by cc.cost_center_code
    "
    db_foreach cost_centers $cc_sql {
	array unset value_hash
	foreach v $vars {
	    set value_hash($v) [set $v]
	}
	set value_hash(availability_percent) $availability_percent
	set cc_hash($object_id) [array get value_hash]
    }

    return [array get cc_hash]
}


ad_proc -public im_resource_management_user_absences {
    {-start_date ""}
    {-end_date ""}
} {
    Returns a Hash with the list of all absences in the interval.
} {
    # Variables of 
    set vars [im_rest_object_type_columns -include_acs_objects_p 0 -rest_otype "im_user_absence"]

    set date_where ""
    if {"" != $start_date} { append date_where "and end_date >= :start_date::date " }
    if {"" != $end_date} { append date_where "and start_date <= :end_date::date " }

    set absences_sql "
	select	t.absence_id as object_id,
		t.*,
		a.*,
		e.*,
		to_char(a.start_date,'J') as start_date_julian,
		to_char(a.end_date,'J') as end_date_julian
	from	(-- Direct absences for a user within the period
		select	owner_id,
			absence_id
		from	im_user_absences
		where	group_id is null
			$date_where
	    UNION
		-- Absences via groups - Check if the user is a member of group_id
		select	mm.member_id as owner_id,
			absence_id
		from	im_user_absences a,
			group_distinct_member_map mm
		where	a.group_id = mm.group_id
			$date_where
		) t,
		im_user_absences a,
		im_employees e
	where	t.absence_id = a.absence_id and
		a.owner_id = e.employee_id
    "
    db_foreach absences $absences_sql {

	# Set the values into a Hash array
	array unset value_hash
	foreach v $vars {
	    set value_hash($v) [set $v]
	}
	
	# Calculate the number of workdays in the absence
	set absence_workdays 0
	for {set i $start_date_julian} {$i <= $end_date_julian} {incr i} {
	    array unset date_comps
	    array set date_comps [util_memoize [list im_date_julian_to_components $i]]

	    set dow $date_comps(day_of_week)
	    if {0 != $dow && 6 != $dow && 7 != $dow} { 
		# Workday
		incr absence_workdays
	    }
	}
	set value_hash(absence_workdays) $absence_workdays
	set value_hash(department_id) $department_id
	set absence_hash($object_id) [array get value_hash]
    }

    return [array get absence_hash]
}




# ---------------------------------------------------------------
# Display Procedure for Resource Planning
# ---------------------------------------------------------------

ad_proc -public im_resource_mgmt_resource_planning_cell {
    mode 
    percentage
    color_code
    title 
    appendix
    limit_height_p 
} {
    Takes a percentage value and returns a formatted HTML ready to be
    displayed as part of a cell. 
    - Mode "default" returns a gif   
    - Mode "custom" creates a bar using a pixel and bg color    
} {

    if {![string is double $percentage]} { return $percentage }
    if { (0.0 == $percentage || "" == $percentage) && !$limit_height_p } { return "" }

    # Calculate the percentage / 10, so that height=10 with 100%
    # Always draw a line, even if percentage is < 5% 
    # (which would result in 0 height of the GIF...)
    set p 0
    catch {
        set p [expr round((1.0 * $percentage) / 10.0)]
    }
    set p [expr round((1.0 * $percentage) / 10.0)]
    if {0 == $p && $percentage > 0.0} { set p 1 }

    # 
    if { $p > 10 && $limit_height_p } { set p 10 }

    if { "default" == $mode} {
	    # Color selection
	    set color ""
	    if {$percentage > 0} { set color "bluedot" }
	    if {$percentage > 100} { set color "FF0000" }
	    set color "bluedot"    
	    set result [im_gif -translate_p 0 $color "$percentage" 0 15 $p]
    } else {
	if { $limit_height_p } { 
	    set percentage 10 
	} else {
	    set percentage [expr $percentage / 5]
	}
	set result "<span class='img-cap' title='$title'>
			<img src='/intranet/images/cleardot.gif' title='$title' alt='$title $appendix' border='0' height='$percentage' width='15' style='background-color:$color_code'>
			<cite>$appendix</cite>
		</span>"
    }
    return $result
}


ad_proc -public im_resource_mgmt_get_bar_color {
    mode
    val
} {
    Returns a color code considering package parameter etc. 
} {
    if {![string is double $val]} { set val 0 }
    # green: 33ff00; yellow: #FFFF00; red: #ff0000

    switch $mode {
	"traffic_light" {
	    set bar_chart_color "\#33ff00"
	    if { $val > 70 } { set bar_chart_color "\#FFFF00" }
	    if { $val > 100 } { set bar_chart_color "\#ff0000" }
	}
	"gradient" {
	    # http://stackoverflow.com/questions/340209/generate-colors-between-red-and-green-for-a-power-meter
	    if { $val > 100 } { set val 100 }
	    set val [expr abs($val - 100)]
	    set val [expr $val / 100]
	    set h [expr $val * 0.38]
	    set s 0.9 			
	    set b 0.9 			
	    set bar_chart_color [hsv2hex $h $s $b]

	    # fool extreme red & extreme green 
	    if { $bar_chart_color == "#e61717" } {set bar_chart_color "#ff0000"}
	    if { $bar_chart_color == "#17e651" } {set bar_chart_color "#33ff00"}

	}
	default {
	    set bar_chart_color "\#666699"
	}
    }

    return $bar_chart_color
}


# ---------------------------------------------------------------
# Auxillary procedures for Resource Report
# ---------------------------------------------------------------


ad_proc -public im_date_julian_to_components { julian_date } {
    Takes a Julian data and returns an array of its components:
    Year, MonthOfYear, DayOfMonth, WeekOfYear, Quarter
} {
    im_security_alert_check_integer -location "im_date_julian_to_components" -value $julian_date

    set ansi [dt_julian_to_ansi $julian_date]
    regexp {(....)-(..)-(..)} $ansi match year month_of_year day_of_month

    set first_year_julian [dt_ansi_to_julian $year 1 1]
    set day_of_year [expr $julian_date - $first_year_julian + 1]
    set week_of_year [util_memoize [list db_string dow "select to_char(to_date('$julian_date', 'J'),'IW')"]]
    set day_of_week [util_memoize [list db_string dow "select extract(dow from to_date('$julian_date', 'J'))"]]
    if {0 == $day_of_week} { set day_of_week 7 }

    # Trim zeros
    if {"0" eq [string range $month_of_year 0 0]} { set month_of_year [string range $month_of_year 1 end] }
    if {"0" eq [string range $week_of_year 0 0]} { set week_of_year [string range $week_of_year 1 end] }
    if {"0" eq [string range $day_of_month 0 0]} { set day_of_month [string range $day_of_month 1 end] }

    set quarter_of_year [expr 1 + int(($month_of_year-1) / 3)]

    return [list year $year \
		month_of_year $month_of_year \
		day_of_month $day_of_month \
		week_of_year $week_of_year \
		quarter_of_year $quarter_of_year \
		day_of_year $day_of_year \
		day_of_week $day_of_week \
    ]
}


ad_proc -public im_date_julian_to_week_julian { julian_date } {
    Takes a Julian data and returns the julian date of the week's day "1" (=Monday)
} {
    array set week_info [im_date_julian_to_components $julian_date]
    set result [expr $julian_date - $week_info(day_of_week)]
}



ad_proc -public im_date_components_to_julian { top_vars top_entry} {
    Takes an entry from top_vars/top_entry and tries
    to figure out the julian date from this
} {

    set year 0
    set week_of_year 0
    set day_of_week 0 
    set month 0 
    
    set ctr 0
    foreach var $top_vars {
	set val [lindex $top_entry $ctr]
	# Remove trailing "0" in week_of_year
	set val [string trimleft $val "0"]
	if {"" == $val} { set val 0 }
	set $var $val
	incr ctr
    }

    set julian 0

    # -------------------------------------------------------------
    # Try to calculate the current data from top dimension
    # -------------------------------------------------------------
    
    # Security 
    if { ![string is integer $year] || ![string is integer $month] || ![string is integer $week_of_year] || ![string is integer $day_of_week] } {
	    ad_return_complaint 1 "<b>Unable to calculate data from date dimension</b>:<br/> Found non-integer"
    }

    switch $top_vars {
	"year week_of_year day_of_week" {
	    catch {
		set julian [dt_ansi_to_julian_single_arg [db_string get_iso_week_date "select (to_date('$year-$week_of_year', 'IYYY-IW')::date + interval '[expr $day_of_week - 1]' day)::date;" -default 0]]
	    }
	}
	"year week_of_year" {
	    catch {
		set julian [dt_ansi_to_julian_single_arg [db_string get_iso_week_date "select (to_date('$year-$week_of_year', 'IYYY-IW')::date)::date;" -default 0]]
	    }
	}
	"year month_of_year day_of_month" {
	    catch {
		if {1 == [string length $month_of_year]} { set month_of_year "0$month_of_year" }
		if {1 == [string length $day_of_month]} { set day_of_month "0$day_of_month" }
		set julian [dt_ansi_to_julian_single_arg "$year-$month_of_year-$day_of_month"]

	    }
	}
	"year month_of_year" {
	    catch {
		if {1 == [string length $month_of_year]} { set month_of_year "0$month_of_year" }
                set julian [dt_ansi_to_julian_single_arg "$year-$month_of_year-01"]
	    }
	}
    }

    if {0 == $julian} { 
	ad_return_complaint 1 "<b>Unable to calculate data from date dimension</b>:<br><pre>$top_vars<br>$top_entry" 
	ad_script_abort
    }

    ns_log Notice "im_date_components_to_julian: $julian, top_vars=$top_vars, top_entry=$top_entry"
    return $julian
}




# ---------------------------------------------------------------
# Resource Planning Report
# ---------------------------------------------------------------

ad_proc -public im_resource_mgmt_resource_planning_percentage {
    {-debug:boolean}
    {-start_date ""}
    {-end_date ""}
    {-show_all_employees_p "1"}
    {-top_vars "year week_of_year day"}
    {-left_vars "cell"}
    {-project_id ""}
    {-project_status_id ""}
    {-project_type_id ""}
    {-employee_cost_center_id "" }
    {-user_id ""}
    {-customer_id 0}
    {-return_url ""}
    {-export_var_list ""}
    {-zoom ""}
    {-auto_open 0}
    {-max_col 8}
    {-max_row 20}
    {-excluded_group_ids "" }
    {-show_departments_only_p "0" }
} {
    Creates Resource Report 

    @param start_date Hard start of reporting period. Defaults to start of first project
    @param end_date Hard end of replorting period. Defaults to end of last project
    @param project_id Id of project(s) to show. Defaults to all active projects
    @param customer_id Id of customer's projects to show

    ToDo: excluded_group_ids currently only accepts a single int
} {

    # ---------------------------------------
    # DEFAULTS
    # ---------------------------------------

    set start_date_request $start_date
    set end_date_request $end_date

    # Write iregularities to protocoll
    set err_protocol ""

    # Department to use, when user is not assigned to one 
    set company_cost_center [im_cost_center_company]
    set default_department [parameter::get -package_id [apm_package_id_from_key intranet-resource-management] -parameter "DefaultCostCenterId" -default $company_cost_center]

    if {"" == $show_departments_only_p} { set show_departments_only_p 0 }
    if {"" == $excluded_group_ids} { set excluded_group_ids 0 }

    set html ""
    set rowclass(0) "roweven"
    set rowclass(1) "rowodd"
    set sigma "&Sigma;"
    set page_url "/intranet-resource-management/resources-planning"

    set current_user_id [ad_conn user_id]
    set return_url [im_url_with_query]

    set clicks([clock clicks -milliseconds]) null

    # The list of users/projects opened already
    set user_name_link_opened {}

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

    if {0 != $customer_id && "" == $project_id} {
	set project_id [db_list pids "
	select	project_id
	from	im_projects
	where	parent_id is null
		and company_id = :customer_id
        "]
    }

    db_1row date_calc "
	select	to_char(:start_date::date, 'J') as start_date_julian,
		to_char(:end_date::date, 'J') as end_date_julian
    "


    # ------------------------------------------------------------
    # URLs to different parts of the system

    set project_base_url "/intranet/projects/view"
    set user_base_url "/intranet/users/view"
    set trans_task_base_url "/intranet-translation/trans-tasks/new"

    set collapse_url "/intranet/biz-object-tree-open-close"
    set company_url "/intranet/companies/view?company_id="
    set project_url "/intranet/projects/view?project_id="
    set user_url "/intranet/users/view?user_id="
    set this_url [export_vars -base $page_url {start_date end_date customer_id} ]
    foreach pid $project_id { append this_url "&project_id=$pid" }


    # ------------------------------------------------------------
    # Conditional SQL Where-Clause
    #
    set criteria [list]
    if {"" != $customer_id && 0 != $customer_id} { lappend criteria "parent.company_id = :customer_id" }
    if {"" != $project_id && 0 != $project_id} { lappend criteria "parent.project_id in ([join $project_id ", "])" }
    if {"" != $project_status_id && 0 != $project_status_id} { 
	lappend criteria "parent.project_status_id in ([join [im_sub_categories $project_status_id] ", "])" 
    }
    if {"" != $project_type_id && 0 != $project_type_id} { 
	lappend criteria "parent.project_type_id in ([join [im_sub_categories $project_type_id] ", "])" 
    }
    if {"" != $user_id && 0 != $user_id} { lappend criteria "u.user_id in ([join $user_id ","])" }

    set union_criteria ""
    if {"" != $employee_cost_center_id && 0 != $employee_cost_center_id} { 
	lappend criteria "u.user_id in (
		select	employee_id
		from	im_employees
		where	department_id = :employee_cost_center_id
	)"

	set union_criteria " 
                    and     e.employee_id in (
                                select  employee_id
                                from    im_employees
                                where   department_id = $employee_cost_center_id
			    )
	"
    } 

    if { "" != $excluded_group_ids } {
        lappend criteria "u.user_id not in (
                                select  object_id_two from acs_rels
                                where   object_id_one = $excluded_group_ids and
                                        rel_type = 'membership_rel'
                        )
	"
    }

    set where_clause [join $criteria " and\n\t\t\t"]
    if { $where_clause ne "" } { set where_clause " and $where_clause" }


    # ------------------------------------------------------------
    # Pre-calculate GIFs for performance reasons
    #
    set object_type_gif_sql "select object_type, object_type_gif from acs_object_types
	where	object_type in ('user', 'person', 'im_project', 'im_timesheet_task')
    "
    db_foreach gif $object_type_gif_sql {
	set gif_hash($object_type) [im_gif $object_type_gif]
    }
    foreach gif {minus_9 plus_9 magnifier_zoom_in magnifier_zoom_out} {
	set gif_hash($gif) [im_gif $gif]
    }

    # ------------------------------------------------------------
    # Collapse lines in the report - store results in a Hash
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


    set clicks([clock clicks -milliseconds]) init

    # ------------------------------------------------------------
    # Store information about each day into hashes for speed
    #
    for {set i $start_date_julian} {$i <= $end_date_julian} {incr i} {
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
    set clicks([clock clicks -milliseconds]) weekends


    # ------------------------------------------------------------
    # Absences - Determine when the user is away
    #
    set absences_sql "
	-- Direct absences for a user within the period
	select	owner_id,
		to_char(start_date,'J') as absence_start_date_julian,
		to_char(end_date,'J') as absence_end_date_julian,
		absence_type_id
	from 	im_user_absences
	where	group_id is null and
		start_date <= to_date(:end_date_request, 'YYYY-MM-DD') and
		end_date   >= to_date(:start_date_request, 'YYYY-MM-DD')
    UNION
	-- Absences via groups - Check if the user is a member of group_id
	select	mm.member_id as owner_id,
		to_char(start_date,'J') as absence_start_date_julian,
		to_char(end_date,'J') as absence_end_date_julian,
		absence_type_id
	from	im_user_absences a,
		group_distinct_member_map mm
	where	a.group_id = mm.group_id and
		start_date <= to_date(:end_date_request, 'YYYY-MM-DD') and
		end_date   >= to_date(:start_date_request, 'YYYY-MM-DD')
    "
    db_foreach absences $absences_sql {
	for {set i $absence_start_date_julian} {$i <= $absence_end_date_julian} {incr i} {

	    # Aggregate per day
	    if {$calc_day_p} {
		set key "$i-$owner_id"
		set val ""
		if {[info exists absences_hash($key)]} { set val $absences_hash($key) }
		append val [expr $absence_type_id - 5000]
		set absences_hash($key) $val
	    }

	    # Aggregate per week, skip weekends
	    if {$calc_week_p && ![info exists weekend_hash($i)]} {
		set week_julian [util_memoize [list im_date_julian_to_week_julian $i]]
		set key "$week_julian-$owner_id"
		set val ""
		if {[info exists absences_hash($key)]} { set val $absences_hash($key) }
		append val [expr $absence_type_id - 5000]
		set absences_hash($key) $val
	    }
	}
    }
    set clicks([clock clicks -milliseconds]) absences


    # ------------------------------------------------------------
    # Projects - determine project & task assignments at the lowest level.
    #
    set percentage_sql "
		select	child.project_id,
			parent.project_id as main_project_id,
			u.user_id,
			coalesce(round(m.percentage), 0) as percentage,
			to_char(child.start_date, 'J') as child_start_date_julian,
			to_char(child.end_date, 'J') as child_end_date_julian
		from	im_projects parent,
			im_projects child,
			acs_rels r,
			im_biz_object_members m,
			users u
		where	parent.project_status_id not in ([join [im_sub_categories [im_project_status_closed]] ","])
			and parent.parent_id is null
			and parent.end_date >= to_date(:start_date_request, 'YYYY-MM-DD')
			and parent.start_date <= to_date(:end_date_request, 'YYYY-MM-DD')
			and child.tree_sortkey
				between parent.tree_sortkey
				and tree_right(parent.tree_sortkey)
			and r.rel_id = m.rel_id
			and r.object_id_one = child.project_id
			and r.object_id_two = u.user_id
			$where_clause
    "


    # ------------------------------------------------------------
    # Main Projects x Users:
    # Return all main projects where a user is assigned in one of the sub-projects
    #
    set show_all_employees_p 1
    set show_all_employees_sql ""
    if {1 == $show_all_employees_p} {
	set show_all_employees_sql "
	UNION
		select
			0::integer as main_project_id,
			0::text as main_project_name,
			p.person_id as user_id,
			im_name_from_user_id(p.person_id) as user_name, 
			e.department_id as department_id
		from
			persons p,
			group_distinct_member_map gdmm, 
			im_employees e
		where
			gdmm.member_id = p.person_id and
			gdmm.group_id = [im_employee_group_id] and
			e.employee_id = p.person_id
		and 	e.employee_id not in (
                              select  object_id_two from acs_rels
                              where   object_id_one = $excluded_group_ids and
                                      rel_type = 'membership_rel'
                        )
		$union_criteria
	"
    }

    set show_users_sql ""
    if {"" != $user_id && 0 != $user_id} {
	set show_users_sql "
	UNION
		select
			0::integer as main_project_id,
			0::text as main_project_name,
			p.person_id as user_id,
			im_name_from_user_id(p.person_id) as user_name,
                        e.department_id as department_id
		from
			persons p, 
                        im_employees e
		where
			p.person_id in ([join $user_id ","]) and
                        e.employee_id = p.person_id
		$union_criteria
	"
    }

    set main_projects_sql "
	select distinct
		main_project_id,
		main_project_name,
		user_id,
		user_name,
		department_id
	from
		(select
			parent.project_id as main_project_id,
			parent.project_name as main_project_name,
			u.user_id,
			im_name_from_user_id(r.object_id_two) as user_name, 
			department_id
		from
			im_projects parent,
			im_projects child,
			acs_rels r,
			im_biz_object_members m,
			users u,
			im_employees e
		where
			parent.project_status_id not in ([join [im_sub_categories [im_project_status_closed]] ","])
			and parent.parent_id is null
			and parent.end_date >= to_date(:start_date, 'YYYY-MM-DD')
			and parent.start_date <= to_date(:end_date, 'YYYY-MM-DD')
			and child.tree_sortkey
				between parent.tree_sortkey
				and tree_right(parent.tree_sortkey)
			and r.rel_id = m.rel_id
			and r.object_id_one = child.project_id
			and r.object_id_two = u.user_id
			-- and m.percentage is not null
			and u.user_id = e.employee_id
			$where_clause
		$show_users_sql
		$show_all_employees_sql
		) t
	where
		t.user_id not in (
			select	u.user_id
			from	users u,
				acs_rels r,
				membership_rels mr
			where	r.rel_id = mr.rel_id and
				r.object_id_two = u.user_id and
				r.object_id_one = -2 and
				mr.member_state != 'approved'
		)
	order by
		department_id,
		user_name,
		main_project_id
    "
    db_foreach main_projects $main_projects_sql {
	set key "$user_id-$main_project_id"
	set member_of_main_project_hash($key) 1
	set object_name_hash($user_id) "$user_name"
	set object_name_hash($main_project_id) $main_project_name
	set has_children_hash($user_id) 1
	set indent_hash($main_project_id) 1
	set object_type_hash($main_project_id) "im_project"
	set object_type_hash($user_id) "person"
    }

    set clicks([clock clicks -milliseconds]) main_projects


    # ------------------------------------------------------------------
    # Calculate the hierarchy.
    # We have to go through all main-projects that have children with
    # assignments, and then we have to go through all of their children
    # in order to get a complete hierarchy.
    #
    set hierarchy_sql "
	select
		parent.project_id as parent_project_id,
		child.project_id,
		child.parent_id,
		child.tree_sortkey,
		child.project_name,
		child.project_nr,
		child.tree_sortkey,
		tree_level(child.tree_sortkey) - tree_level(parent.tree_sortkey) as tree_level,
		o.object_type
	from
		im_projects parent,
		im_projects child,
		acs_objects o
	where
		parent.project_status_id not in ([join [im_sub_categories [im_project_status_closed]] ","])
		and parent.parent_id is null
		and parent.project_id in (
			select	main_project_id
			from	($percentage_sql) t
		)
		and child.project_id = o.object_id
		and child.tree_sortkey
			between parent.tree_sortkey
			and tree_right(parent.tree_sortkey)
	order by
		parent.project_id,
		child.tree_sortkey
    "

    set empty ""
    set name_hash($empty) ""
    set parent_project_id 0
    set old_parent_project_id 0
    set hierarchy_lol {}
    db_foreach project_hierarchy $hierarchy_sql {

	ns_log Notice "gantt-resources-planning: parent=$parent_project_id, child=$project_id, tree_level=$tree_level"
	# Store the list of sub-projects into the hash once the main project changes
	if {$old_parent_project_id != $parent_project_id} {
	    set main_project_hierarchy_hash($old_parent_project_id) $hierarchy_lol
	    set hierarchy_lol {}
	    set old_parent_project_id $parent_project_id
	}

	# Store project hierarchy information into hashes
	set parent_hash($project_id) $parent_id
	set has_children_hash($parent_id) 1
	set name_hash($project_id) $project_name
	set indent_hash($project_id) [expr $tree_level + 1]
	set object_name_hash($project_id) $project_name
	set object_type_hash($project_id) $object_type

	# Determine the project path that leads to the current sub-project
	# and aggregate the current assignment information to all parents.
	set hierarchy_row {}
	set level $tree_level
	set pid $project_id

        while {$level >= 0} {
            lappend hierarchy_row $pid
            if { ![info exists parent_hash($pid)] } {
               # Fallback - can we get parent_id from tree_sortkey?
               set sql "
                        select  parent.project_id
                        from    im_projects parent,
                                im_projects child
                        where   child.project_id = :pid and
                                tree_ancestor_key(child.tree_sortkey, tree_level(child.tree_sortkey)-1) = parent.tree_sortkey
                "
	       set parent_id [db_string get_parent $sql -default 0]

	       if { "0" == $parent_id || "" == $parent_id }  {
                   set project_id_list "<br>"
                   set sql "select project_id as problem_project_id from im_projects where parent_id = $pid"
                   db_foreach problem_project_id $sql {
                        append project_id_list "<a href='/intranet/projects/view?project_id=$problem_project_id'>$problem_project_id</a><br>"
                   }
                   ad_return_complaint 1 "We have found an invalid/non existing parent project (id=$pid) for the following projects/tasks id(s):<br>$project_id_list <br>"
	       } else {
                  set pid $parent_id
	       }
	   } else {
              set pid $parent_hash($pid)
	   }
            incr level -1
        }

	# append the line to the list of sub-projects of the current main-project
	set project_path [f::reverse $hierarchy_row]
	lappend hierarchy_lol [list $project_id $project_name $tree_level $project_path]

    }

    # Save the list of sub-projects of the last main project (see above in the loop)
    set main_project_hierarchy_hash($parent_project_id) $hierarchy_lol
    set clicks([clock clicks -milliseconds]) hierarchy

    # ------------------------------------------------------------------
    # Calculate the left scale.
    #
    # The scale is composed by three different parts:
    #
    # - The user
    # - The outer "main_projects_sql" selects out users and their main_projects
    #   in which they are assigned with some percentage. All elements of this
    #   SQL are shown always.
    # - The inner "project_lol" look shows the _entire_ tree of sub-projects and
    #   tasks for each main_project. That's necessary, because no SQL could show
    #   us the 
    #
    # The scale starts with the "user" dimension, followed by the 
    # main_projects to which the user is a member. Then follows the
    # full hierarchy of the main_project.
    #
    set left_scale {}
    set old_user_id 0
    set total_user_ctr 0

    db_foreach left_scale_users $main_projects_sql {

	# ----------------------------------------------------------------------
	# Determine the user and write out the first line without projects

	# Add a line without project, only for the user
	if {$user_id != $old_user_id} {
	    ns_log Notice "intranet-resource-management-procs::main_projects_sql -- -------------------------------------------------------------------------------"
	    ns_log Notice "intranet-resource-management-procs::main_projects_sql - Building left_scale - Adding: $user_name ($user_id) - (old_user_id=$old_user_id)"
	    # remember the type of the object
	    set otype_hash($user_id) "person"
	    # append the user_id to the left_scale
	    lappend left_scale [list $user_id ""]
	    # Remember that we have already processed this user
	    set old_user_id $user_id
	    # Count users listed in this whole report  
	    incr total_user_ctr 
	}
	# ----------------------------------------------------------------------
	# Write out the project-tree for the main-projects.

	# Make sure that the user is assigned somewhere in the main project
	# or otherwise skip the entire main_project:
	set main_projects_key "$user_id-$main_project_id"
 	if {![info exists member_of_main_project_hash($key)]} { continue }

	# Get the hierarchy for the main project as a list-of-lists (lol)
	set hierarchy_lol $main_project_hierarchy_hash($main_project_id)
	set open_p "c"
	if {[info exists collapse_hash($user_id)]} { set open_p $collapse_hash($user_id) }
	if {"c" == $open_p} { set hierarchy_lol [list] }

	# Loop through the project hierarchy
	foreach row $hierarchy_lol {

	    # Extract the pieces of a hierarchy row
	    set project_id [lindex $row 0]
	    set project_name [lindex $row 1]
	    set project_path [lindex $row 3]

	    # Iterate through the project_path, looking for:
	    # - the name of the project to display and
	    # - if any of the parents has been closed
	    ns_log Notice "intranet-resource-management:main_projects_sql - Loop through PROJ hirarchy - pid=$project_id, name=$project_name, path=$project_path, row=$row"
	    set collapse_control_oid 0
	    set closed_p "c"
	    if {[info exists collapse_hash($user_id)]} { set closed_p $collapse_hash($user_id) }
	    for {set i 0} {$i < [llength $project_path]} {incr i} {
		set project_in_path_id [lindex $project_path $i]

		if {$i == [expr [llength $project_path] - 1]} {
		    # We are at the last element of the project "path" - This is the project to display.
		    set pid $project_in_path_id
		} else {
		    # We are at a parent (of any level) of the project
		    # Check if the parent is closed:
		    set collapse_p "c"
		    if {[info exists collapse_hash($project_in_path_id)]} { set collapse_p $collapse_hash($project_in_path_id) }
		    if {"c" == $collapse_p} { set closed_p "c" }
		}
	    }

	    # append the values to the left scale
	    if {"c" == $closed_p} { continue }
	    lappend left_scale [list $user_id $pid]
	}
    }

    set clicks([clock clicks -milliseconds]) left_scale

#    ad_return_complaint 1 "<pre>[join $left_scale "\n"]</pre>"


    # ------------------------------------------------------------------------------------------------------------------------------------
    # 
    # RESSOURCE ASSIGNMENT (%)
    #
    # Calculate the main resource assignment hash by looping
    # through the project hierarchy x looping through the date dimension  
    #
    # ------------------------------------------------------------------------------------------------------------------------------------

    db_foreach percentage_loop $percentage_sql {
	# sanity check for empty start/end date
	if {""==$start_date_julian || ""==$end_date_julian} {
	    ad_return_complaint 1 "Empty date found. Please verify start/end date of Project ID: <a href='/intranet/projects/view?project_id=$project_id'>$project_id</a>" 
	}

	# Skip if no data
	if {"" == $child_start_date_julian} { 
	    ns_log Notice "intranet-resource-management-procs::percentage_sql: Found empty child_end_start_julian, not setting perc_day_hash/perc_week_hash"
	    continue 
	}
	if {"" == $child_end_date_julian} { 
	    ns_log Notice "intranet-resource-management-procs::percentage_sql: Found empty child_end_date_julian, not setting perc_day_hash/perc_week_hash"
	    continue 
	}
	
	# Loop through the days between start_date and end_data
	for {set i $child_start_date_julian} {$i <= $child_end_date_julian} {incr i} {
	    ns_log Notice "intranet-resource-management-procs::percentage_sql: Loop through the days between start_date and end_data: Handling Jday: $i"
	    if {$i < $start_date_julian} { 
		ns_log Notice "intranet-resource-management-procs::percentage_sql: Loop through the days between start_date and end_data: day < start_date_julian ($start_date_julian), leaving loop,nothing set perc_day_hash/perc_week_hash"
		continue 
	    }
	    if {$i > $end_date_julian} { 
		ns_log Notice "intranet-resource-management-procs::percentage_sql: Loop through the days between start_date and end_data: day > end_date_julian ($end_date_julian), leaving loop, nothing set perc_day_hash/perc_week_hash"
		continue 
	    }

	    # Loop through the project hierarchy towards the top
	    set pid $project_id
	    set cont 1
	    while {$cont} {
		# Aggregate per day
		if {$calc_day_p} {
		    set key "$user_id-$pid-$i"
		    set perc 0
		    if {[info exists perc_day_hash($key)]} { set perc $perc_day_hash($key) }
		    set perc [expr $perc + $percentage]
		    set perc_day_hash($key) $perc
		    ns_log Notice "intranet-resource-management-procs::percentage_sql: AGGREGATE DAY \$perc_day_hash : ${perc}% (key:$key)"
		}

		# Aggregate per week
		if {$calc_week_p} {
		    set week_julian $start_of_week_julian_hash($i)
		    set key "$user_id-$pid-$week_julian"
		    set perc 0
		    if {[info exists perc_week_hash($key)]} { set perc $perc_week_hash($key) }
		    set perc [expr $perc + $percentage]
		    set perc_week_hash($key) $perc
		    ns_log Notice "intranet-resource-management-procs::percentage_sql: AGGREGATE WEEK \$perc_week_hash: ${perc}% (key:$key)"
		}

		# Check if there is a super-project and continue there.
		# Otherwise allow for one iteration with an empty $pid
		# to deal with the user's level
		if {"" == $pid} { 
		    set cont 0 
		} else {
		    if { [info exists parent_hash($pid)] } {
			set pid $parent_hash($pid)
		    } else {
			set err_mess "We have found an issue with project id: <a href='/intranet/projects/view?project_id=$pid'>$pid</a>.
			        <br />Possible causes include: 
			        <ul>
				<li>Start/end date of subordinate task or project does not ly within the period that is defined by start and end date of the superior project or task </li>
				</ul>
			"
			append err_protocol "<li>$err_mess</li>\n"
			set cont 0			
		    }
		}
	    }
	}
    }; # End creating perc_day_hash, perc_week_hash

    #DEBUG 
    # ad_return_complaint 1 [array get perc_day_hash]

    set clicks([clock clicks -milliseconds]) percentage_hash

    # -------------------
    # Define Top Scale 
    # -------------------

    # Top scale is a list of lists like {{2006 01} {2006 02} ...}
    set top_scale {}
    set last_top_dim {}
    for {set i [dt_ansi_to_julian_single_arg $start_date_request]} {$i <= [dt_ansi_to_julian_single_arg $end_date_request]} {incr i} {
	array unset date_hash
	array set date_hash [im_date_julian_to_components $i]
	
	set top_dim {}
	foreach top_var $top_vars {
	    set date_val ""
	    catch { set date_val $date_hash($top_var) }
	    lappend top_dim $date_val
	}

	# "distinct" clause: add the values of top_vars to the top scale, if it is different from the last one...
	# This is necessary for aggregated top scales like weeks and months.
	if {$top_dim != $last_top_dim} {
	    lappend top_scale $top_dim
	    set last_top_dim $top_dim
	}
    }
    ns_log Notice "intranet-resource-management-procs::DefineTopScale: Top Scale: $top_scale"
    set clicks([clock clicks -milliseconds]) top_scale

    # Determine how many date rows (year, month, day, ...) we've got
    set first_cell [lindex $top_scale 0]
    set top_scale_rows [llength $first_cell]
    set left_scale_size [llength [lindex $left_vars 0]]

    set clicks([clock clicks -milliseconds]) display_table_header


    set left_clicks(start) 0
    set left_clicks(gif) 0
    set left_clicks(left) 0
    set left_clicks(write) 0
    set left_clicks(top_scale) 0
    set last_click [clock clicks]

    set left_clicks(top_scale_start) 0
    set left_clicks(top_scale_write_vars) 0
    set left_clicks(top_scale_to_julian) 0
    set left_clicks(top_scale_calc) 0
    set left_clicks(top_scale_cell) 0
    set left_clicks(top_scale_color) 0
    set left_clicks(top_scale_append) 0

    # ------------------------------------------------------------------------------------------------------------------------
    # Create OUTPUT
    # Expects values in the following hash tables: perc_day_hash, perc_week_hash, ..... 
    # ------------------------------------------------------------------------------------------------------------------------

    # -----------------------------------------------------------
    # | For all elements left column (employees)
    # |  --------------------------------------------------------
    # |  |  ?? Change of Department ?? 
    # |  |-------------------------------------------------------
    # |  |  Y                               |           N  
    # |  |------------------------------------------------------
    # |  | Show row accumulation department |          - 
    # |  | Show rows employees              |
    # |  |------------------------------------------------------
    # |  |
    # |  |  tbc. ... 

    set row_ctr 0
    set show_row_task_p 0 

    foreach left_entry $left_scale {
	# example for left scale: {8892 {}} {624 {}} {30730 {}} {29622 {}} {29622 29946} ... 

	# This boolean is needed to calculate the total of hours available for the minimum UOM (day/week/month)
        set row_shows_employee_p 0

	set left_clicks(start) [expr $left_clicks(start) + [clock clicks] - $last_click]
	set last_click [clock clicks]

	ns_log Notice "intranet-resource-management-procs::output: -- --------------------------------------------------"
	ns_log Notice "intranet-resource-management-procs::output: -- --------------------------------------------------"
	ns_log Notice "intranet-resource-management-procs::output: Handling user: $left_entry"
	set row_html ""

	# Extract user and project. An empty project indicates 
	# an entry for a person only.
	set user_id [lindex $left_entry 0]

	set user_department_id [util_memoize [list db_string get_department "select department_id from im_employees where employee_id = $user_id" -default 0]]
	if { ""==$user_department_id } { set user_department_id $default_department }

	# -----------------------------------------------
        # Determine availability of user (hours/day)  
	# -----------------------------------------------
        set availability_user_perc [util_memoize [list db_string get_availabilty "select availability from im_employees where employee_id=$user_id" -default 0]]
        if { ![info exists availability_user_perc] } { set availability_user_perc 100 }
        # Make it 100% when no value found -> ToDo: Print hint on bottom of report 
	if { "" == $availability_user_perc } { set availability_user_perc 100 }

	set project_id [lindex $left_entry 1]

	# Determine what we want to show in this line
	set oid $user_id
	set otype "person"

	if {"" != $project_id} { 
	    ns_log Notice "intranet-resource-management-procs::output: Showing Project row" 
	    set oid $project_id 
	    set otype "im_project"
	} else {
	    ns_log Notice "intranet-resource-management-procs::output: Showing Employee row" 	    
	    # no project_id found, row shows employee
	    set row_shows_employee_p 1
	}

	# --------------------------------------------------------------------
	# Write department Row when user_department_id has changed ...   
	# -------------------------------------------------------------------
	if { $row_shows_employee_p } {
	    ns_log Notice "intranet-resource-management-procs::output: Check if department is completed and should be added to outpout" 
	    if { 0 == $row_ctr } {
		ns_log Notice "intranet-resource-management-procs::output: No rows found, setting user_department_id_predecessor to user_department_id"
		set user_department_id_predecessor $user_department_id
	    } else {
		if { $user_department_id_predecessor != $user_department_id } {
		    set first_department_p 0
		    ns_log Notice "intranet-resource-management-procs::output: Change of department -> show subtotals and print rows"
		    # Change of department -> show subtotals and print rows 
		    append html [write_department_row \
				     $department_row_html \
				     $user_department_id_predecessor \
				     [array get totals_department_absences_arr] \
				     [array get totals_department_planned_hours_arr] \
				     [array get totals_department_availability_arr] \
				     $top_scale $top_vars $show_departments_only_p \
		    ] 

		    set user_department_id_predecessor $user_department_id
		    
		    # Reset department arrays 
		    array unset totals_department_absences_arr
		    array unset totals_department_availability_arr
		    array unset totals_department_planned_hours_arr

		    set department_row_html ""
	        }
	    }
	}

	# ------------------------------------------------------------
	# Start the row and show the left_scale values at the left

	set class $rowclass([expr $row_ctr % 2])
	append department_row_html_tmp "<tr class=$class valign=bottom>\n"

	if {[info exists object_type_hash($oid)]} { set otype $object_type_hash($oid) }

	# Display +/- logic
	set closed_p "c"
	if {[info exists collapse_hash($oid)]} { set closed_p $collapse_hash($oid) }
	if {"o" == $closed_p} {
	    set url [export_vars -base $collapse_url {page_url return_url {open_p "c"} {object_id $oid}}]
	    set collapse_html "<a href=$url>$gif_hash(minus_9)</a>"
	} else {
	    set url [export_vars -base $collapse_url {page_url return_url {open_p "o"} {object_id $oid}}]
	    set collapse_html "<a href=$url>$gif_hash(plus_9)</a>"
	}

	set left_clicks(gif) [expr $left_clicks(gif) + [clock clicks] - $last_click]
	set last_click [clock clicks]


	set object_has_children_p 0
	if {[info exists has_children_hash($oid)]} { set object_has_children_p $has_children_hash($oid) }
	if {!$object_has_children_p} { set collapse_html [util_memoize [list im_gif cleardot "" 0 9 9]] }

	ns_log Notice "intranet-resource-management-procs::output: Handling object_type: $otype (user_id: $user_id)"

	switch $otype {
	    person {
		set indent_level 0
		set user_name "undef user $oid"
		if {[info exists object_name_hash($oid)]} { set user_name $object_name_hash($oid) }
		set cell_html "$collapse_html $gif_hash(user) <a href='[export_vars -base $user_base_url {{user_id $oid}}]'>$user_name</a>"
	    }
	    im_project {
		set indent_level 1
		set project_name "undef project $oid"
		if {[info exists object_name_hash($oid)]} { set project_name $object_name_hash($oid) }
		set cell_html "$collapse_html $gif_hash(im_project) <a href='[export_vars -base $project_base_url {{project_id $oid}}]'>$project_name</a>"
	    }
	    im_timesheet_task {
		set indent_level 1
		set project_name "undef project $oid"
		if {[info exists object_name_hash($oid)]} { set project_name $object_name_hash($oid) }
		set cell_html "$collapse_html $gif_hash(im_timesheet_task) <a href='[export_vars -base $project_base_url {{project_id $oid}}]'>$project_name</a>"
	    }

	    im_trans_task {
	     	set indent_level 1
	     	set task_id $oid
	     	set task_name "undef im_trans_task $oid"
	     	if {[info exists object_name_hash($oid)]} { set task_name $object_name_hash($oid) }
	     	set cell_html "$collapse_html $gif_hash(im_trans_task) <a href='[export_vars -base $trans_task_base_url {{task_id $oid}}]'>$task_name</a>"
	    }

	    default { 
		set cell_html "unknown object '$otype' type for object '$oid'" 
	    }
	}

	# Indent the object name
	if {[info exists indent_hash($oid)]} { set indent_level $indent_hash($oid) }
	set indent_html ""
	for {set i 0} {$i < $indent_level} {incr i} { append indent_html "&nbsp; &nbsp; &nbsp; " }

	append department_row_html_tmp "<td><nobr>$indent_html$cell_html</nobr></td>\n"

	set left_clicks(left) [expr $left_clicks(left) + [clock clicks] - $last_click]
	set last_click [clock clicks]

	# ------------------------------------------------------------
	# Write the left_scale values to their corresponding local 
	# variables so that we can access them easily when calculating
	# the "key".
	for {set i 0} {$i < [llength $left_vars]} {incr i} {
	    set var_name [lindex $left_vars $i]
	    set var_value [lindex $left_entry $i]
	    set $var_name $var_value
	}


	set left_clicks(write) [expr $left_clicks(write) + [clock clicks] - $last_click]
	set last_click [clock clicks]

	
	# ------------------------------------------------------------
	# Start writing out the matrix elements
	# ------------------------------------------------------------

	set last_julian 0
	set column_ctr 0 

	# topscale example: {2011 9 01} {2011 9 02}
	foreach top_entry $top_scale {
	    ns_log Notice "intranet-resource-management-procs::output:WriteMatrixElements::------------------------------------------------------ Loop through top_scale"

	    set left_clicks(top_scale_start) [expr $left_clicks(top_scale_start) + [clock clicks] - $last_click]
	    set last_click [clock clicks]

	    # Write the top_scale values to their corresponding local 
	    # variables so that we can access them easily for $key 
	    # Example: year month_of_year day_of_month
	    for {set i 0} {$i < [llength $top_vars]} {incr i} {
		set var_name [lindex $top_vars $i]
		set var_value [lindex $top_entry $i]
		set $var_name $var_value
	    }

	    set left_clicks(top_scale_write_vars) [expr $left_clicks(top_scale_write_vars) + [clock clicks] - $last_click]
	    set last_click [clock clicks]

	    # Calculate the julian date for today from top_vars
	    set julian_date [util_memoize [list im_date_components_to_julian $top_vars $top_entry]]
	    ns_log Notice "intranet-resource-management-procs::output:WriteMatrixElements:: Evaluating im_date_components_to_julian (top_vars: $top_vars // top_entry: $top_entry): $julian_date ([dt_julian_to_ansi $julian_date])"	    
	    if {$julian_date == $last_julian} {
		# We're with the second ... seventh entry of a week.
		continue
	    } else {
		set last_julian $julian_date
	    }

	    set left_clicks(top_scale_to_julian) [expr $left_clicks(top_scale_to_julian) + [clock clicks] - $last_click]
	    set last_click [clock clicks]

	    ns_log Notice "intranet-resource-management-procs::output:WriteMatrixElements:: Writing cell for julian_date: $julian_date ([dt_julian_to_ansi $julian_date] - user_id: $user_id"

	    # -----------------------------------
	    # Get the value for this cell 
	    # -----------------------------------

	    set val ""
	    set val_hours ""

	    if {$calc_day_p} {
		set key "$user_id-$project_id-$julian_date"
		if {[info exists perc_day_hash($key)]} { set val $perc_day_hash($key) }
	    }
	    if { $calc_week_p } {
		set week_julian [util_memoize [list im_date_julian_to_week_julian $julian_date]]
		set key "$user_id-$project_id-$week_julian"
		if {[info exists perc_week_hash($key)]} { set val $perc_week_hash($key) }
		if {"" == [string trim $val]} { set val 0 }
		set val [expr round($val / 7.0)]
	    }

	    if {"" == [string trim $val]} { set val 0 }
	    if {"" == [string trim $val_hours]} { set val_hours 0 }

	    # ----------------------------------------------------------------------
	    # Cell value evaluated, now format content based on object type .... 
	    # ----------------------------------------------------------------------

	    set left_clicks(top_scale_calc) [expr $left_clicks(top_scale_calc) + [clock clicks] - $last_click]
	    set last_click [clock clicks]

	    set occupation_user 0
	    set occupation_user_total 0

	    set day_of_week [util_memoize [list db_string dow "select extract(dow from to_date('$julian_date', 'J'))"]]
	    if {0 == $day_of_week} { set day_of_week 7 }

	    # Which type of line: person or project/task  
	    switch $otype {
            	person {
		    if { [info exists weekend_hash($julian_date)] } {
			# This is a weekend, do not print values for SAT and SUN
			set cell_html "&nbsp;"
		    } else {
			set cell_html "${val}%"
		    }
		}   

	        default {
		    # default line is showing project or task 
		    set cell_html "${val}%"
		}
	    }

	    set left_clicks(top_scale_cell) [expr $left_clicks(top_scale_cell) + [clock clicks] - $last_click]
	    set last_click [clock clicks]
	    
	    # Lookup the color of the absence for field background color
	    # Weekends
	    set list_of_absences ""
	    if {$calc_day_p && [info exists weekend_hash($julian_date)]} {
		set absence_key $julian_date
		append list_of_absences $weekend_hash($absence_key)
	    }
	
	    # Absences
	    set absence_key "$julian_date-$user_id"
	    if {[info exists absences_hash($absence_key)]} {
		# Color the entire column in case of an absence 
		append list_of_absences $absences_hash($absence_key)
	    }
	
	    set col_attrib ""
	    if {"" != $list_of_absences} {
#		ad_return_complaint 1 '$list_of_absences'
		if {$calc_week_p} {
		    while {[string length $list_of_absences] < 5} { append list_of_absences " " }
		}
		set color [util_memoize [list im_absence_mix_colors $list_of_absences]]
		set col_attrib "bgcolor=#$color"
	    }

	    set left_clicks(top_scale_color) [expr $left_clicks(top_scale_color) + [clock clicks] - $last_click]
	    set last_click [clock clicks]

	    append department_row_html_tmp "<td $col_attrib>$cell_html</td>\n"

	    set left_clicks(top_scale_append) [expr $left_clicks(top_scale_append) + [clock clicks] - $last_click]
	    set last_click [clock clicks]

	    incr column_ctr

	} ; # end loop columns 
	   
	set left_clicks(top_scale) [expr $left_clicks(top_scale) + [clock clicks] - $last_click]
	set last_click [clock clicks]
        append department_row_html_tmp "</tr>\n"

	# ---------------------------------------------------------------
	# Decide if we need  to show this row 
	# ----------------------------------------------------------------

        switch $otype {
            person {
		append department_row_html $department_row_html_tmp
            }
            im_project {
		append department_row_html $department_row_html_tmp
            }
            im_timesheet_task {
		if { $show_row_task_p } {
		    append department_row_html $department_row_html_tmp
		}
            }
            im_trans_task {
	     	append department_row_html $department_row_html_tmp
            }
            default {
		append department_row_html $department_row_html_tmp
            }
        }

	set department_row_html_tmp ""
	set show_row_task_p 0

	incr row_ctr

    }


    # ----------------------------------------------------------------------------------------------------------------------------
    # END 
    # ----------------------------------------------------------------------------------------------------------------------------
    # foreach left_entry $left_scale {} (loop user/project/task rows) 
    # ----------------------------------------------------------------------------------------------------------------------------
    # ----------------------------------------------------------------------------------------------------------------------------

 
    if { [info exists department_row_html] } {
	append html [write_department_row \
			 $department_row_html \
			 $user_department_id_predecessor \
			 [array get totals_department_absences_arr] \
			 [array get totals_department_planned_hours_arr] \
			 [array get totals_department_availability_arr] \
			 $top_scale $top_vars $show_departments_only_p \
			]
    }

    # end loop rows 

    set clicks([clock clicks -milliseconds]) display_table_body

    # ----------------------------------------------------------------------------------------------------------------------------
    # START
    # ----------------------------------------------------------------------------------------------------------------------------
    # Start header creation
    # ----------------------------------------------------------------------------------------------------------------------------
    # ----------------------------------------------------------------------------------------------------------------------------

    set header ""
    for {set row 0} {$row < $top_scale_rows} { incr row } {
	
	append header "<tr class=rowtitle>\n"
	set col_l10n [lang::message::lookup "" "intranet-resource-management.Dim_[lindex $top_vars $row]" [lindex $top_vars $row]]
	if {0 == $row} {
	    set zoom_in "<a href=[export_vars -base $this_url {top_vars {zoom "in"}}]>$gif_hash(magnifier_zoom_in)</a>\n" 
	    set zoom_out "<a href=[export_vars -base $this_url {top_vars {zoom "out"}}]>$gif_hash(magnifier_zoom_out)</a>\n" 
	    set col_l10n "<!-- $zoom_in $zoom_out --> $col_l10n \n" 
	}
	append header "<td class=rowtitle colspan=$left_scale_size align=right>$col_l10n</td>\n"
	
	# ------------------------------
	# Create Top Scale (Header)
	# ------------------------------

	for {set col 0} {$col <= [expr [llength $top_scale]-1]} { incr col } {
	    
	    set scale_entry [lindex $top_scale $col]
	    set scale_item [lindex $scale_entry $row]
	    
	    # Check if the previous item was of the same content
	    set prev_scale_entry [lindex $top_scale $col-1]
	    set prev_scale_item [lindex $prev_scale_entry $row]

	    # Check for the "sigma" sign. We want to display the sigma
	    # every time (disable the colspan logic)
	    if {$scale_item == $sigma} { 
		append header "\t<td class=rowtitle>$scale_item</td>\n"
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
	    append header "\t<td class=rowtitle colspan=$colspan>$scale_item</td>\n"
	}
	append header "</tr>\n"
    }

    # ------------------------------------------------------------
    # Profiling HTML
    #
    if {$debug_p} {
	set debug_html "<br>&nbsp;<br><table>\n"
	set last_click 0
	foreach click [lsort -integer [array names clicks]] {
	    if {0 == $last_click} { 
		set last_click $click 
		set first_click $click
	    }
	    append debug_html "<tr><td>$click</td><td>$clicks($click)</td><td>[expr ($click - $last_click) / 1000.0]</td></tr>\n"
	    set last_click $click
	}
	append debug_html "<tr><td> </td><td><b>Total</b></td><td>[expr ($last_click - $first_click) / 1000.0]</td></tr>\n"
	append debug_html "<tr><td colspan=3>&nbsp;</tr>\n"
	append debug_html "<tr><td> </td><td> start</td><td>$left_clicks(start)</td></tr>\n"
	append debug_html "<tr><td> </td><td> gif</td><td>$left_clicks(gif)</td></tr>\n"
	append debug_html "<tr><td> </td><td> left</td><td>$left_clicks(left)</td></tr>\n"
	append debug_html "<tr><td> </td><td> write</td><td>$left_clicks(write)</td></tr>\n"
	append debug_html "<tr><td> </td><td> top_scale</td><td>$left_clicks(top_scale)</td></tr>\n"
	append debug_html "<tr><td> </td><td> top_scale_start </td><td>$left_clicks(top_scale_start)</td></tr>\n"
	append debug_html "<tr><td> </td><td> top_scale_write_vars </td><td>$left_clicks(top_scale_write_vars)</td></tr>\n"
	append debug_html "<tr><td> </td><td> top_scale_to_julian </td><td>$left_clicks(top_scale_to_julian)</td></tr>\n"
	append debug_html "<tr><td> </td><td> top_scale_calc </td><td>$left_clicks(top_scale_calc)</td></tr>\n"
	append debug_html "<tr><td> </td><td> top_scale_cell </td><td>$left_clicks(top_scale_cell)</td></tr>\n"
	append debug_html "<tr><td> </td><td> top_scale_color </td><td>$left_clicks(top_scale_color)</td></tr>\n"
	append debug_html "<tr><td> </td><td> top_scale_append </td><td>$left_clicks(top_scale_append)</td></tr>\n"
	append debug_html "</table>\n"
	
	append html $debug_html
    }


    # ------------------------------------------------------------
    # Close the table
    #
    set html "<table cellspacing=3 cellpadding=3 valign=bottom>\n$header\n$html\n</table>\n"

    if {0 == $row_ctr} {
	set no_rows_msg [lang::message::lookup "" intranet-resource-management.No_rows_selected "
		No rows found.<br>
		Maybe there are no assignments of users to projects in the selected period?
	"]
	append html "<br><b>$no_rows_msg</b>\n"
    }

    set clicks([clock clicks -milliseconds]) close_table
    return "$html <br> $err_protocol"
}


# ---------------------------------------------------------------
# Show the status of potential freelancers in the member-add page
# ---------------------------------------------------------------

ad_proc im_resource_mgmt_resource_planning_add_member_component { } {
    Component that returns a formatted HTML table.
    The table contains the availability for all persons with
    matching freelance profiles.
} {
    # ------------------------------------------------
    # Security
    # Check that the user has the right to "read" the group Freelancers
  
    set user_id [ad_conn user_id]
    set perm_p [db_string freelance_read "select im_object_permission_p([im_profile_freelancers], :user_id, 'read')"]
    if {"t" != $perm_p} {
        return ""
    }

    # Only show if the freelance package is installed.
    if {![db_table_exists im_freelance_skills]} { return "" }



    # ------------------------------------------------
    # Parameter Logic
    # 
    # Get the freel_trans_order_by variable from the http header
    # because we can't trust that the embedding page will pass
    # this param into this component.

    set current_url [ad_conn url]
    set header_vars [ns_conn form]
    set var_list [ad_ns_set_keys $header_vars]

    # set local TCL vars from header vars
    ad_ns_set_to_tcl_vars $header_vars

    # Remove the "freel_trans_order_by" from the var_list
    set order_by_pos [lsearch $var_list "freel_trans_order_by"]
    if {$order_by_pos > -1} {
	set var_list [lreplace $var_list $order_by_pos $order_by_pos]
    }

    

    # ------------------------------------------------
    # Constants

    set source_lang_skill_type 2000
    set target_lang_skill_type 2002

    set order_freelancer_sql "user_name"

    # Project's Source & Target Languages
    set project_source_lang ""
    set project_target_langs ""
    catch {
    set project_source_lang [db_string source_lang "
                select  substr(im_category_from_id(source_language_id), 1, 2)
                from    im_projects
                where   project_id = :object_id" \
    -default 0]

    set project_target_langs [db_list target_langs "
		select '''' || substr(im_category_from_id(language_id), 1, 2) || '''' 
		from	im_target_languages 
		where	project_id = :object_id
    "]
    }
    if {0 == [llength $project_target_langs]} { set project_target_langs [list "'none'"]}


    # ------------------------------------------------
    # Get the list of users that meet source- and target language requirements

    set freelance_sql "
	select distinct
		u.user_id,
		im_name_from_user_id(u.user_id) as user_name
	from
		users u,
		group_member_map m, 
		membership_rels mr,
		(	select	user_id
			from	im_freelance_skills
			where	skill_type_id = :source_lang_skill_type
				and substr(im_category_from_id(skill_id), 1, 2) = :project_source_lang
		) sls,
		(	select	user_id
			from	im_freelance_skills
			where	skill_type_id = :target_lang_skill_type
				and substr(im_category_from_id(skill_id), 1, 2) in ([join $project_target_langs ","])
		) tls
	where
		m.group_id = acs__magic_object_id('registered_users'::character varying) AND 
		m.rel_id = mr.rel_id AND 
		m.container_id = m.group_id AND 
		m.rel_type::text = 'membership_rel'::text AND 
		mr.member_state::text = 'approved'::text AND 
		u.user_id = m.member_id AND
		sls.user_id = u.user_id AND
		tls.user_id = u.user_id
	order by
		$order_freelancer_sql
    "
    
    set user_list {}
    db_foreach freelancers $freelance_sql {
	lappend user_list $user_id
    }

    # ------------------------------------------------
    # Call the resource planning compoment
    #

    db_1row date "
	select	now()::date as start_date,
		now()::date + 30 as end_date
    "

    set result [im_resource_mgmt_resource_planning \
		-start_date $start_date \
		-end_date $end_date \
		-top_vars "year month_of_year day_of_month" \
		-user_id $user_list
    ]

    return $result
}


ad_proc -private write_department_row {
    	{ department_row_html }
        { department_id }
        { totals_department_absences_arr }
        { totals_department_planned_hours_arr }
        { totals_department_availability_arr }
        { top_scale }
        { top_vars }
        { show_departments_only_p }
} {
    - writes department row
} {
    array set totals_department_absences_arr_loc $totals_department_absences_arr
    array set totals_department_planned_hours_arr_loc $totals_department_planned_hours_arr
    array set totals_department_availability_arr_loc $totals_department_availability_arr
    set row_html ""
    set department_name [db_string get_department_name "select cost_center_name from im_cost_centers where cost_center_id = $department_id" -default ""]
    append row_html "<tr><td><b>[lang::message::lookup "" intranet-reporting.SubTotalDepartment "Department"]: $department_name</b></td>"
    set ctr 0
    
    # Sanity check: Make sure we have a value vor each column
    foreach top_entry $top_scale {
	if {![info exists totals_department_absences_arr_loc($ctr)]} { set totals_department_absences_arr_loc($ctr) 0 }
	if {![info exists totals_department_planned_hours_arr_loc($ctr)]} { set totals_department_planned_hours_arr_loc($ctr) 0 }
	if {![info exists totals_department_availability_arr_loc($ctr)]} { set totals_department_availability_arr_loc($ctr) 0 }
	
	set julian_date [util_memoize [list im_date_components_to_julian $top_vars $top_entry]]
	set day_of_week [util_memoize [list db_string dow "select extract(dow from to_date('$julian_date', 'J'))"]]
	if {0 == $day_of_week} { set day_of_week 7 }
	
	append row_html "<td></td>"
	incr ctr	
    }
    append row_html "</tr>"
    # Write all rows for department (depeartment acc values & user)
    
    if { $show_departments_only_p } {
	return $row_html
    } else {
	return "$row_html$department_row_html"
    }
}

ad_proc -private hsv2hex {h s v} {
	# http://code.activestate.com/recipes/133527/ (
	# Arguments: h hue, s saturation, v value
	# Results: Returns an rgb triple from hsv
	if {$s <= 0.0} {
        	# achromatic
	        set v [expr int($v)]
        	return "$v $v $v"
    	} else {
        	set v [expr double($v)]
	        if {$h >= 1.0} { set h 0.0 }
        	set h [expr 6.0 * $h]
	        set f [expr double($h) - int($h)]
        	set p [expr int(256 * $v * (1.0 - $s))]
	        set q [expr int(256 * $v * (1.0 - ($s * $f)))]
        	set t [expr int(256 * $v * (1.0 - ($s * (1.0 - $f))))]
	        set v [expr int(256 * $v)}]
        	switch [expr int($h)}] {
	            0 { set rgb "$v $t $p" }
        	    1 { set rgb "$q $v $p" }
	            2 { set rgb "$p $v $t" }
        	    3 { set rgb "$p $q $v" }
	            4 { set rgb "$t $p $v" }
        	    5 { set rgb" $v $p $q" }
        	}
    	}

	set rgb_list [split $rgb " "]
	return "\#[format %x [lindex $rgb_list 0]][format %x [lindex $rgb_list 1]][format %x [lindex $rgb_list 2]]"
}

ad_proc -public im_absence_working_days_weekend_only {
    -start_date
    -end_date
} {
} {
    return [db_list get_work_days "select * from im_absences_working_days_period_weekend_only(:start_date::date, :end_date::date) as series_days (days date)"]
}

# ---------------------------------------------------------------
# Component showing related objects
# ---------------------------------------------------------------

ad_proc -public im_resource_mgmt_employee_assignment_pie_chart {
    {-diagram_interval "next_quarter"}
    {-diagram_width 600}
    {-diagram_height 350}
} {
    Returns a HTML component with a pie chart of user assignments
} {
    if {![im_sencha_extjs_installed_p]} { return "" }
    im_sencha_extjs_load_libraries

    set diagram_title [lang::message::lookup "" intranet-resource-management.Employee_Assignment "Employee Assignment"]
    set params [list \
                    [list diagram_interval $diagram_interval] \
                    [list diagram_width $diagram_width] \
                    [list diagram_height $diagram_height] \
                    [list diagram_title $diagram_title] \
    ]

    set result [ad_parse_template -params $params "/packages/intranet-resource-management/lib/employee-assignment-pie-chart"]
    return [string trim $result]
}

