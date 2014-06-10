# /packages/intranet-resource-management/www/employee-assignment-pie-chart.json.tcl
#
# Copyright (C) 2014 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

ad_page_contract {
    Datasource for employee assignment Sencha pie chart.
} {
    { diagram_interval "all_time" }
    { diagram_department_user_id "" }
    { diagram_max_length_employee_name 15 }
}

# ----------------------------------------------------
# Defaults & Permissions
# ----------------------------------------------------

set current_user_id [ad_get_user_id]
if {![im_permission $current_user_id view_users]} { 
    set json "{\"success\": false, \"message\": \"Insufficient permissions - you need view_users.\" }"
    doc_return 200 "text/html" $json
    ad_script_abort
}

# ----------------------------------------------------
# Multirow as temporary store
# ----------------------------------------------------

switch $diagram_interval {
    next_quarter { db_1row date "select now()::date as start_date, now()::date + 90 as end_date" }
    last_quarter { db_1row date "select now()::date - 90 as start_date, now()::date as end_date" }
    over_next_quarter { db_1row date "select now()::date + 90 as start_date, now()::date + 180 as end_date" }
    over_last_quarter { db_1row date "select now()::date - 180 as start_date, now()::date -90 as end_date" }
    default {
	set json "{\"success\": false, \"message\": \"Invalid diagram_interval option: '$diagram_interval'.\" }"
	doc_return 200 "text/html" $json
	ad_script_abort
    }
}

set employee_assignments_sql "
	select	user_id,
		coalesce(e.availability, 100.0) as user_availability,
		im_resource_mgmt_work_days(u.user_id, '$start_date', '$end_date') as workday_array,
		im_resource_mgmt_user_absence(u.user_id, '$start_date', '$end_date') as absence_array,
		im_resource_mgmt_project_assignation(u.user_id, '$start_date', '$end_date', true) as billable_array,
		im_resource_mgmt_project_assignation(u.user_id, '$start_date', '$end_date', false) as nonbillable_array
	from	users u
		LEFT OUTER JOIN im_employees e ON (u.user_id = e.employee_id)
	where	u.user_id in (select member_id from group_distinct_member_map where group_id = [im_profile_employees]) and
		(  :diagram_department_user_id is null
		OR u.user_id = :diagram_department_user_id
		OR u.user_id in (
			-- Select users of sub-cost centers
			select	e.employee_id
			from	im_employees e,
				im_cost_centers cc,
				im_cost_centers cc_top
			where	cc_top.cost_center_id = :diagram_department_user_id and
				substring(cc.cost_center_code from 1 for length(cc_top.cost_center_code)) = cc_top.cost_center_code and
				e.department_id = cc.cost_center_id
			        )
		)
	order by user_id
"
set workday_sum 0.0
set absence_sum 0.0
set billable_sum 0.0
set nonbillable_sum 0.0
db_foreach employee_assignments $employee_assignments_sql {
    set workday_list [string map {"," " " "{" "" "}" ""} [lindex [split $workday_array "="] 1]]
    set absence_list [string map {"," " " "{" "" "}" ""} [lindex [split $absence_array "="] 1]]
    set billable_list [string map {"," " " "{" "" "}" ""} [lindex [split $billable_array "="] 1]]
    set nonbillable_list [string map {"," " " "{" "" "}" ""} [lindex [split $nonbillable_array "="] 1]]

#    ad_return_complaint 1 "$workday_list<br>$absence_list<br>$billable_list<br>$nonbillable_list"
    set len [llength $workday_list]
    for {set i 0} {$i < $len} {incr i} {
	set workday [lindex $workday_list $i]
	if {100 != $workday} { continue }
	set workday_sum [expr $workday_sum + $workday]
	set absence_sum [expr $absence_sum + [lindex $absence_list $i]]
	set billable_sum [expr $billable_sum + [lindex $billable_list $i]]
	set nonbillable_sum [expr $nonbillable_sum + [lindex $nonbillable_list $i]]
    }
}

set absences_l10n [lang::message::lookup "" intranet-resource-management.Absences "Absences"]
set billable_l10n [lang::message::lookup "" intranet-resource-management.Billable "Billable Projects"]
set nonbillable_l10n [lang::message::lookup "" intranet-resource-management.Not_Billable "Not Billable Projects"]
set not_assigned_l10n [lang::message::lookup "" intranet-resource-management.Not_Assigned "Not Assigned"]
set invalid_data_l10n [lang::message::lookup "" intranet-resource-management.Invalid_Data "Invalid Data"]
# set _l10n [lang::message::lookup "" intranet-resource-management.]

multirow create mr name value
if {0.0 == $workday_sum} {
    multirow append mr $invalid_data_l10n 1
} else {
    if {$billable_sum > 0} { multirow append mr $billable_l10n [expr 100.0 * $billable_sum / $workday_sum] }
    if {$nonbillable_sum > 0} { multirow append mr $nonbillable_l10n [expr 100.0 * $nonbillable_sum / $workday_sum] }
    if {$absence_sum > 0} { multirow append mr $absences_l10n [expr 100.0 * $absence_sum / $workday_sum] }

    set not_assigned_sum [expr 100.0 - 100.0 * $absence_sum / $workday_sum - 100.0 * $billable_sum / $workday_sum - 100.0 * $nonbillable_sum / $workday_sum]
    if {$not_assigned_sum > 0} { multirow append mr $not_assigned_l10n $not_assigned_sum }
}

# ----------------------------------------------------
# Create JSON for data source
# ----------------------------------------------------

set data_list [list]
multirow foreach mr {
    lappend data_list "{\"name\": \"$name\", \"value\": $value }"
}
set json "{\"success\": true, \"message\": \"Data loaded\", \"data\": \[\n[join $data_list ",\n"]\n\]}"
doc_return 200 "text/html" $json

