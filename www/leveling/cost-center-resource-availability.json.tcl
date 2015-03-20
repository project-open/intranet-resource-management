# /packages/sencha-task-editor/www/free-draw/dept-resource-availability.json.tcl
#
# Copyright (c) 2014 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/ for licensing details.

ad_page_contract {
    Returns information about 
} {
    { start_date:array,optional }
    { end_date:array,optional }
    { report_start_date "" }
    { report_end_date "" }
    { granularity "week" }
}

# ---------------------------------------------------------------
# Defaults & Security
# ---------------------------------------------------------------

set current_user_id [ad_maybe_redirect_for_registration]
if {![im_permission $current_user_id "view_projects_all"]} {
    ad_return_complaint 1 "You don't have permissions to see this page"
    ad_script_abort
}

if {"" == $report_start_date} { set start_date [db_string now "select (now()::date - '1 month'::interval)::date"] }
if {"" == $report_end_date} { set end_date [db_string now "select (now()::date + '1 year'::interval)::date"] }

set report_start_date [string range $report_start_date 0 9]
set report_end_date [string range $report_end_date 0 9]

set report_start_julian [im_date_ansi_to_julian $report_start_date]
set report_end_julian [im_date_ansi_to_julian $report_end_date]



#ad_return_complaint 1 $report_end_julian

# ---------------------------------------------------------------
# Calculate available resources per cost_center
# ---------------------------------------------------------------

# Cost_Centers hash cost_center_id -> hash(CC vars) + "availability_percent"
array set cc_hash [im_resource_management_cost_centers -start_date $report_start_date -end_date $report_end_date]
# ad_return_complaint 1 "<pre>[join [array get cc_hash] "\n"]</pre>"

# Initialize availalable resources per cost_center and day
foreach cc_id [array names cc_hash] {
    array unset cc_values
    array set cc_values $cc_hash($cc_id)
    set availability_percent $cc_values(availability_percent)
    if {"" == $availability_percent} { set availability_percent 0.0 }

    # Initialize the availability array for the interval 
    # and set the resource availability according to the cc base availability
    array unset cc_day_values
    for {set i $report_start_julian} {$i <= $report_end_julian} {incr i} {
	set available_days [expr $availability_percent / 100.0]

	# Reset weekends to zero availability
	array set date_comps [util_memoize [list im_date_julian_to_components $i]]
	set dow $date_comps(day_of_week)
	if {6 == $dow || 7 == $dow} { 
	    # Weekend
	    set available_days 0.0 
	}

	set key "$cc_id-$i"
	set available_day_hash($key) $available_days
    }
}

# ---------------------------------------------------------------
# Subtract vacations from available days
# ---------------------------------------------------------------

# Absences hash absence_id -> hash(absence vars)
array set absence_hash [im_resource_management_user_absences -start_date $report_start_date -end_date $report_end_date]
# ad_return_complaint 1 [array get absence_hash]

foreach aid [array names absence_hash] {
    array unset absence_values
    array set absence_values $absence_hash($aid)

    set absence_start_date [string range $absence_values(start_date) 0 9]
    set absence_end_date [string range $absence_values(end_date) 0 9]
    set duration_days $absence_values(duration_days)
    set absence_workdays $absence_values(absence_workdays)
    set department_id $absence_values(department_id)

    set end_julian [im_date_ansi_to_julian $absence_end_date]
    for {set i [im_date_ansi_to_julian $absence_start_date]} {$i <= $end_julian} {incr i} {
	set key "$department_id-$i"
	set available_days 0.0
	if {[info exists available_day_hash($key)]} { set available_days $available_day_hash($key) }

	array set date_comps [util_memoize [list im_date_julian_to_components $i]]
	set dow $date_comps(day_of_week)
	if {0 != $dow && 6 != $dow && 7 != $dow} { 
	    set available_days [expr $available_days - (1.0 * $duration_days / $absence_workdays)]
	}

	set available_day_hash($key) $available_days	
    }
}


# ---------------------------------------------------------------
# Calculate the required project resources during the interval
# with the modified project start- and end dates
# ---------------------------------------------------------------

# Store the julian start- and end dates for the main projects
foreach pid [array names start_date] {
    set start_ansi $start_date($pid);
    set start_julian [im_date_ansi_to_julian $start_ansi]
    set end_ansi $end_date($pid);
    set end_julian [im_date_ansi_to_julian $end_ansi]

    set start_julian_hash($pid) $start_julian
    set end_julian_hash($pid) $end_julian
}

# Store employee department information in hash
set default_cost_center_id [im_cost_center_company]
set employee_sql "
	select	u.user_id,
		coalesce(e.department_id, :default_cost_center_id) as department_id
	from	users u
		LEFT OUTER JOIN im_employees e ON (u.user_id = e.employee_id)
"
db_foreach emp $employee_sql {
    set employe_department_hash($user_id) $department_id
}

set pids [array names start_date]
if {{} == $pids} { set pids [list 0] }
set percentage_sql "
		select
			parent.project_id as parent_project_id,
			to_char(parent.start_date, 'J') as parent_start_julian,
			to_char(parent.end_date, 'J') as parent_end_julian,
			u.user_id,
			child.project_id,
			to_char(child.start_date, 'J') as child_start_julian,
			to_char(child.end_date, 'J') as child_end_julian,
			coalesce(round(bom.percentage), 0) as percentage
		from
			im_projects parent,
			im_projects child,
			acs_rels r,				-- no left outer join - show only assigned users
			im_biz_object_members bom,
			users u
		where
			parent.project_id in ([join $pids ","]) and
			parent.parent_id is null and
			parent.end_date >= to_date(:report_start_date, 'YYYY-MM-DD') and
			parent.start_date <= to_date(:report_end_date, 'YYYY-MM-DD') and
			child.tree_sortkey between parent.tree_sortkey and tree_right(parent.tree_sortkey) and
			r.rel_id = bom.rel_id and
			bom.percentage is not null and		-- skip assignments without percentage
			r.object_id_one = child.project_id and
			r.object_id_two = u.user_id
			-- Testing
			-- and parent.project_id = 171036	-- Fraber Test 2015
"
db_foreach projects $percentage_sql {
    set pid_start_julian $start_julian_hash($parent_project_id)
    set pid_end_julian $end_julian_hash($parent_project_id)
    set parent_date_shift [expr $pid_start_julian - $parent_start_julian]

    # ns_log Notice "cost-center-resource-availability.json.tcl: parent_date_shift=$parent_date_shift"
    # ToDo: incorporate if the project has been dragged to be longer

    set child_start_julian [expr $child_start_julian + $parent_date_shift]
    set child_end_julian [expr $child_end_julian + $parent_date_shift]
    set department_id $employe_department_hash($user_id)

    for {set j $child_start_julian} {$j <= $child_end_julian} {incr j} {
	set key "$department_id-$j"
	set perc 0.0
	if {[info exists assigned_day_hash($key)]} { set perc $assigned_day_hash($key) }
	set perc [expr $perc + $percentage / 100.0]

	array set date_comps [util_memoize [list im_date_julian_to_components $j]]
	set dow $date_comps(day_of_week)

	if {6 == $dow || 7 == $dow} { set perc 0.0 }
	set assigned_day_hash($key) $perc
    }
}

#ad_return_complaint 1 [array get assigned_day_hash]

# ---------------------------------------------------------------
# Format result as JSON
# ---------------------------------------------------------------

set json_list [list]
set ctr 0

switch $granularity {
    "day" {
	foreach cc_id [array names cc_hash] {
	    array unset cc_values
	    array set cc_values $cc_hash($cc_id)
	    set cost_center_name $cc_values(cost_center_name)
	    set assigned_resources_percent $cc_values(availability_percent)
	    set assigned_resources [expr round($assigned_resources_percent * 10.0) / 1000.0]
	    if {"" == $assigned_resources_percent} { set assigned_resources_percent 0.0 }

	    set available_days [list]
	    set assigned_days [list]
	    for {set i $report_start_julian} {$i <= $report_end_julian} {incr i} {
		set key "$cc_id-$i"

		# Format available days
		set days 0.0
		if {[info exists available_day_hash($key)]} { 
		    set days $available_day_hash($key) 
		}
		lappend available_days [expr round(1000.0 * $days) / 1000.0]

		# Format assigned days
		set days 0.0
		if {[info exists assigned_day_hash($key)]} { 
		    set days $assigned_day_hash($key) 
		}
		lappend assigned_days [expr round(1000.0 * $days) / 1000.0]
	    }
	    
	    set available_list [join $available_days ", "]
	    set assigned_list [join $assigned_days ", "]
	    set cc_row_days [list "\n\t\"id\":$cc_id,
\t\"cost_center_id\":$cc_id,
\t\"cost_center_name\":\"$cost_center_name<br>&nbsp;\",
\t\"assigned_resources\":\"$assigned_resources\",
\t\"available_days\":\[$available_list\],
\t\"assigned_days\":\[$assigned_list\]
"]

	    set cc_row "{[join $cc_row_days ", "]}"
	    lappend json_list $cc_row
	    incr ctr
	}
    }
    "week" {
	# Calculate the list of all weeks in reporting interval
	set week_list [list]
	array set week_hash {}
	for {set i $report_start_julian} {$i <= $report_end_julian} {incr i} {
	    set week_after_start [expr ($i-$report_start_julian) / 7]
	    set week_key "$week_after_start"
	    if {![info exists week_hash($week_key)]} { 
		set week_hash($week_key) 1
		lappend week_list $week_key
	    }
	}
	
	# Summarize the daily hash into a weekly hash
	foreach cc_id [array names cc_hash] {	    
	    for {set i $report_start_julian} {$i <= $report_end_julian} {incr i} {
		set day_key "$cc_id-$i"
		set week_after_start [expr ($i-$report_start_julian) / 7]
		set week_key "$cc_id-$week_after_start"

		# Aggregate available days per week
		set available_days 0
		if {[info exists available_day_hash($day_key)]} { set available_days $available_day_hash($day_key) }
		set available_week_days 0
		if {[info exists available_week_hash($week_key)]} { set available_week_days $available_week_hash($week_key) }
		set available_week_days [expr $available_week_days + $available_days]
		if {$available_week_days > 0.0} {
		    set available_week_hash($week_key) $available_week_days
		}

		# Aggregate assigned days per week
		set assigned_days 0
		if {[info exists assigned_day_hash($day_key)]} { set assigned_days $assigned_day_hash($day_key) }
		set assigned_week_days 0
		if {[info exists assigned_week_hash($week_key)]} { set assigned_week_days $assigned_week_hash($week_key) }
		set assigned_week_days [expr $assigned_week_days + $assigned_days]
		if {$assigned_week_days > 0.0} {
		    set assigned_week_hash($week_key) $assigned_week_days
		}

	    }
	}

	foreach cc_id [array names cc_hash] {
	    array unset cc_values
	    array set cc_values $cc_hash($cc_id)
	    set cost_center_name $cc_values(cost_center_name)
	    set assigned_resources_percent $cc_values(availability_percent)
	    if {"" == $assigned_resources_percent} { set assigned_resources_percent 0.0 }
	    set assigned_resources [expr round($assigned_resources_percent) / 100.0]
	    
	    set available_weeks [list]
	    set assigned_weeks [list]
	    foreach week_key $week_list {
		set key "$cc_id-$week_key"

		# Format available days
		set available_days 0.0
		if {[info exists available_week_hash($key)]} { set available_days $available_week_hash($key) }
		lappend available_weeks [expr round(1000.0 * $available_days / 5.0) / 1000.0]

		# Format assigned days
		set assigned_days 0.0
		if {[info exists assigned_week_hash($key)]} { set assigned_days $assigned_week_hash($key) }
		lappend assigned_weeks [expr round(1000.0 * $assigned_days / 5.0) / 1000.0]
	    }
	    
	    set available_list [join $available_weeks ", "]
	    set assigned_list [join $assigned_weeks ", "]
	    set cc_row_weeks [list "\"id\":$cc_id,\
\"cost_center_id\":$cc_id,\
\"cost_center_name\":\"$cost_center_name<br>&nbsp;\",\
\"assigned_resources\":\"$assigned_resources\",
\"available_days\":\[$available_list\],
\"assigned_days\":\[$assigned_list\]
"]

	    set cc_row "{[join $cc_row_weeks ", "]}"
	    lappend json_list $cc_row
	    incr ctr
	}
    }
}

set json [join $json_list ",\n"]
set result "{\"succes\": true, \"total\": $ctr, \"message\": \"Data Loaded\", data: \[\n$json\n\]}"
doc_return 200 "text/html" $result

