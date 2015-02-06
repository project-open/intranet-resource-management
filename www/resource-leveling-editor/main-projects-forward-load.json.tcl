# /packages/sencha-task-editor/www/resource-leveling-editor/main-projects-forward-load.json.tcl
#
# Copyright (c) 2014 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/ for licensing details.

ad_page_contract {
    Editor for projects
} {
    { project_type_id:integer "" }
    { project_status_id:integer 76 }
    { granularity "week" }
    { program_id "" }
    { start_date ""}
    { end_date ""}
}

# ---------------------------------------------------------------
# Defaults & Security
# ---------------------------------------------------------------

set current_user_id [ad_maybe_redirect_for_registration]
if {![im_permission $current_user_id "view_projects_all"]} {
    ad_return_complaint 1 "You don't have permissions to see this page"
    ad_script_abort
}

# ---------------------------------------------------------------
# Calculate resource load per day and main project
# ---------------------------------------------------------------

# ToDo: Inconsistent states:
# - work vs. assignments: Check that there is no over/underallocation
# - day fractions: Check start/end of a task for fractions
# - natural users vs. skill profiles

set main_where ""
if {"" != $start_date} { append main_where "\t\tand main_p.end_date::date >= :start_date::date\n" }
if {"" != $end_date} { append main_where "\t\tand main_p.start_date::date <= :end_date::date\n" }
if {"" != $project_status_id} { append main_where "\t\tand main_p.project_status_id in (select im_sub_categories(:project_status_id))\n" }
if {"" != $project_type_id} { append main_where "\t\tand main_p.project_type_id in (select im_sub_categories(:project_type_id))\n" }
if {"" != $program_id} { append main_where "\t\tand main_p.program_id = :program_id\n" }

set main_sql "
	select	main_p.project_id as main_project_id,
		main_p.project_name as main_project_name,
		main_p.start_date::date as main_start_date,
		main_p.end_date::date as main_end_date,
		main_p.description as main_description,
		coalesce(main_p.percent_completed, 0.0) as main_percent_completed,
		coalesce(main_p.on_track_status_id, 0) as main_on_track_status_id,
		to_char(main_p.start_date::date, 'J') as main_start_date_julian,
		to_char(main_p.end_date::date, 'J') as main_end_date_julian,
		sub_p.*,
		to_char(sub_p.start_date::date, 'J') as start_date_julian,
		to_char(sub_p.end_date::date, 'J') as end_date_julian,
		p.person_id,
		coalesce(bom.percentage, 0.0) as percentage
	from	im_projects main_p,
		im_projects sub_p
		LEFT OUTER JOIN im_timesheet_tasks t ON (t.task_id = sub_p.project_id)
		LEFT OUTER JOIN acs_rels r ON (r.object_id_one = sub_p.project_id)
		LEFT OUTER JOIN im_biz_object_members bom ON (r.rel_id = bom.rel_id)
		LEFT OUTER JOIN persons p ON (r.object_id_two = p.person_id)
	where	main_p.parent_id is null and
		sub_p.tree_sortkey between main_p.tree_sortkey and tree_right(main_p.tree_sortkey)
		$main_where
		-- FOR TESTING ONLY - LIMIT TO ONE PROJECT TO IMPROVE PERFORMANCE
		-- and main_p.project_id in (171036) -- Fraber Test 2015
"
set sql "
	select	*
	from	($main_sql) main_sql
	where	percentage > 0.0
"

db_foreach main_p $sql {
    set main_project_name_hash($main_project_id) $main_project_name
    set main_project_start_j_hash($main_project_id) $main_start_date_julian
    set main_project_end_j_hash($main_project_id) $main_end_date_julian
    set main_project_start_date_hash($main_project_id) $main_start_date
    set main_project_end_date_hash($main_project_id) $main_end_date

    for {set j $start_date_julian} {$j <= $end_date_julian} {incr j} {
	array set date_comps [util_memoize [list im_date_julian_to_components $j]]
	set year $date_comps(year)
	set week_of_year $date_comps(week_of_year)
	set dow $date_comps(day_of_week)

	# Skip weekends
	if {0 == $dow || 6 == $dow || 7 == $dow} { continue }


	# Days
	set key "$main_project_id-$j"
	set val 0.0
	if {[info exists percentage_day_hash($key)]} { set val $percentage_day_hash($key) }
	set val [expr $val + ($percentage / 100.0)]
	set percentage_day_hash($key) $val

	# Weeks
	set key_week "$main_project_id-$year-$week_of_year"
	set val 0.0
	if {[info exists percentage_week_hash($key_week)]} { set val $percentage_week_hash($key_week) }
        set val [expr $val + ($percentage / 100.0)]
        set percentage_week_hash($key_week) $val
    }
}

# ad_return_complaint 1 [array get percentage_day_hash]
# ad_return_complaint 1 [lsort [array names percentage_day_hash]]

# ---------------------------------------------------------------
# Format result as JSON
# ---------------------------------------------------------------

set json_list [list]
set ctr 0
foreach pid [qsort [array names main_project_start_j_hash]] {
    set project_name $main_project_name_hash($pid)
    set start_j $main_project_start_j_hash($pid)
    set end_j $main_project_end_j_hash($pid)
    set start_date $main_project_start_date_hash($pid)
    set end_date $main_project_end_date_hash($pid)

    array unset week_hash
    set vals [list]
    set max_val 0
    for {set j $start_j} {$j <= $end_j} {incr j} {
	# day
	set key_day "$pid-$j"
	set perc 0
	if {[info exists percentage_day_hash($key_day)]} { set perc $percentage_day_hash($key_day) }
	set perc_rounded [expr round($perc * 100.0) / 100.0]
	lappend vals $perc_rounded
	if {$perc > $max_val} { set max_val $perc }


	# Aggregate values per week
	array set date_comps [util_memoize [list im_date_julian_to_components $j]]
	set year $date_comps(year)
	set week_of_year $date_comps(week_of_year)

	set key_week "$pid-$year-$week_of_year"
	set perc_week 0.0
	if {[info exists percentage_week_hash($key_week)]} { set perc_week $percentage_week_hash($key_week) }
	set perc_week [expr $perc_week + $perc]
	set percentage_week_hash($key_week) $perc_week

	# Remember this week as part of a hash
	set week_hash($key_week) 1
    }

    if {"week" == $granularity} {
	set vals [list]
	set max_val 0
	foreach key_week [qsort [array names week_hash]] {
	    set perc $percentage_week_hash($key_week)
	    set perc_rounded [expr round($perc * 100.0 / 5.0) / 100.0]
	    lappend vals $perc_rounded
	    if {$perc_rounded > $max_val} { set max_val $perc_rounded }
	}
    }

    set percs [join $vals ", "]
    set project_row_vals [list "\"id\":$pid,\
\"project_id\":$pid,\
\"project_name\":\"$project_name\",\
\"start_date\":\"$start_date\",\
\"end_date\":\"$end_date\",\
\"percent_completed\":$main_percent_completed,\
\"on_track_status_id\":$main_on_track_status_id,\
\"max_assigned_days\":$max_val,\
\"assigned_days\":\[
$percs
\]"]

    set project_row "{[join $project_row_vals ", "]}"
    lappend json_list $project_row
    incr ctr
}

set json [join $json_list ",\n"]
set result "{\"succes\": true, \"total\": $ctr, \"message\": \"Data Loaded\", data: \[\n$json\n\]}"
doc_return 200 "text/html" $result

