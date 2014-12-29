# /packages/sencha-task-editor/www/free-draw/dept-resource-availability.json.tcl
#
# Copyright (c) 2014 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/ for licensing details.

ad_page_contract {
    Editor for projects
} {
    { start_date:array }
    { end_date:array }
    { report_start_date "" }
    { report_end_date "" }
    { granularity "week" }
}

# ad_return_complaint 1 "<pre>[array get start_date]<br>[array get end_date]</pre>"

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

# ---------------------------------------------------------------
# Calculate available resources per cost_center
# ---------------------------------------------------------------

# Cost_Centers hash cost_center_id -> hash(CC vars) + "availability_percent"
array set cc_hash [im_resource_management_cost_centers -start_date $report_start_date -end_date $report_end_date]
# ad_return_complaint 1 [array get cc_hash]

# Initialize availalable resources per cost_center and day
foreach cc_id [array names cc_hash] {
    array unset cc_values
    array set cc_values $cc_hash($cc_id)
    set availability_percent $cc_values(availability_percent)

    # Initialize the availability array for the interval 
    # and set the resource availability according to the cc base availability
    array unset cc_day_values
    for {set i [dt_ansi_to_julian_single_arg $report_start_date]} {$i <= [dt_ansi_to_julian_single_arg $report_end_date]} {incr i} {
	set available_days [expr $availability_percent / 100.0]

	# Reset weekends to zero availability
	array set date_comps [util_memoize [list im_date_julian_to_components $i]]
	set dow $date_comps(day_of_week)
	if {0 == $dow || 6 == $dow || 7 == $dow} { 
	    # Weekend
	    set available_days 0.0 
	}

	set key "$cc_id-$i"
	set cc_day_hash($key) $available_days
    }
}

# Subtract vacations from available days
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
	if {[info exists cc_day_hash($key)]} { set available_days $cc_day_hash($key) }

	array set date_comps [util_memoize [list im_date_julian_to_components $i]]
	set dow $date_comps(day_of_week)
	if {0 != $dow && 6 != $dow && 7 != $dow} { 
	    set available_days [expr $available_days - (1.0 * $duration_days / $absence_workdays)]
	}

	set cc_day_hash($key) $available_days	
    }
}


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
	    
	    set days [list]
	    for {set i [im_date_ansi_to_julian $report_start_date]} {$i <= [im_date_ansi_to_julian $report_end_date]} {incr i} {
		set key "$cc_id-$i"
		set available_days 0.0
		if {[info exists cc_day_hash($key)]} { set available_days $cc_day_hash($key) }
		lappend days $available_days
	    }
	    
	    set days_list [join $days ", "]
	    set cc_row_days [list "\"id\":$cc_id,\
\"cost_center_id\":$cc_id,\
\"cost_center_name\":\"$cost_center_name\",\
\"available_days\":\[
$days_list
\]"]

	    set cc_row "{[join $cc_row_days ", "]}"
	    lappend json_list $cc_row
	    incr ctr
	}
    }


    "week" {

	# Calculate the list of all weeks in reporting interval
	set week_list [list]
	array set week_hash {}
	for {set i [im_date_ansi_to_julian $report_start_date]} {$i <= [im_date_ansi_to_julian $report_end_date]} {incr i} {
	    array set date_comps [util_memoize [list im_date_julian_to_components $i]]
	    set year $date_comps(year)
	    set week_of_year $date_comps(week_of_year)
	    
	    set week_key "$year-$week_of_year"
	    if {![info exists week_hash($week_key)]} { 
		set week_hash($week_key) 1
		lappend week_list $week_key
	    }
	}

	
	# Summarize the daily hash into a weekly hash
	foreach cc_id [array names cc_hash] {	    
	    for {set i [im_date_ansi_to_julian $report_start_date]} {$i <= [im_date_ansi_to_julian $report_end_date]} {incr i} {
		array set date_comps [util_memoize [list im_date_julian_to_components $i]]
		set year $date_comps(year)
		set week_of_year $date_comps(week_of_year)

		set day_key "$cc_id-$i"
		set available_days 0
		if {[info exists cc_day_hash($day_key)]} { set available_days $cc_day_hash($day_key) }

		set week_key "$cc_id-$year-$week_of_year"
		set available_week_days 0
		if {[info exists cc_week_hash($week_key)]} { set available_week_days $cc_week_hash($week_key) }
		set available_week_days [expr $available_week_days + $available_days]
		if {$available_week_days > 0.0} {
		    set cc_week_hash($week_key) $available_week_days
		}
	    }
	}
	# ad_return_complaint 1 [array get cc_week_hash]

	foreach cc_id [array names cc_hash] {
	    array unset cc_values
	    array set cc_values $cc_hash($cc_id)
	    set cost_center_name $cc_values(cost_center_name)
	    
	    set weeks [list]
	    foreach week_key $week_list {
		set key "$cc_id-$week_key"
		set available_days 0.0
		if {[info exists cc_week_hash($key)]} { set available_days $cc_week_hash($key) }
		lappend weeks [expr round(1000.0 * $available_days) / 1000.0]
	    }
	    
	    set list [join $weeks ", "]
	    set cc_row_weeks [list "\"id\":$cc_id,\
\"cost_center_id\":$cc_id,\
\"cost_center_name\":\"$cost_center_name\",\
\"available_days\":\[
$list
\]"]

	    set cc_row "{[join $cc_row_weeks ", "]}"
	    lappend json_list $cc_row
	    incr ctr
	}
    }
}

set json [join $json_list ",\n"]
set result "{\"succes\": true, \"total\": $ctr, \"message\": \"Data Loaded\", data: \[\n$json\n\]}"
doc_return 200 "text/html" $result

