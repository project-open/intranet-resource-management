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
    next_quarter { set employee_assignment_interval_sql "" }
    default {
	set json "{\"success\": false, \"message\": \"Invalid diagram_interval option: '$diagram_interval'.\" }"
	doc_return 200 "text/html" $json
	ad_script_abort
    }
}

set employee_assignments_sql "
	select	im_name_from_user_id(user_id) as name,
		1 as value
	from	users u
	where	u.user_id in (select member_id from group_distinct_member_map where group_id = [im_profile_employees])
	order by value DESC
"

set count 0
multirow create employee_assignments name value
db_foreach employee_assignments $employee_assignments_sql {
    set name_limited [string range $name 0 $diagram_max_length_employee_name]
    if {$name_limited != $name} { append name_limited "..." }
    multirow append employee_assignments $name_limited $value
    incr count
}

# Create dummy entry if there were no revenues
if {0 == $count} {
    set no_revenues_l10n [lang::message::lookup "" intranet-resource-management.No_Result_Data "No Result Data"]
    multirow append employee_assignments $no_revenues_l10n 1
}

# ----------------------------------------------------
# Create JSON for data source
# ----------------------------------------------------

set data_list [list]
multirow foreach employee_assignments {
    lappend data_list "{\"name\": \"$name\", \"value\": $value }"
}
set json "{\"success\": true, \"message\": \"Data loaded\", \"data\": \[\n[join $data_list ",\n"]\n\]}"
doc_return 200 "text/html" $json

