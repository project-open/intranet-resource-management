# /packages/sencha-task-editor/www/resource-leveling-editor/main-projects-forward-load-update.tcl
#
# Copyright (c) 2014 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/ for licensing details.

# NO page contract!
# ad_page_contract {}

# ---------------------------------------------------------------
# Defaults & Security
# ---------------------------------------------------------------

set current_user_id [ad_maybe_redirect_for_registration]
if {![im_permission $current_user_id "edit_projects_all"]} {
    ad_return_complaint 1 "You don't have permissions to edit_projects_all"
    ad_script_abort
}

# ---------------------------------------------------------------
# Extract Data
# Parameters may be send via the URL (project_id=...)
# ---------------------------------------------------------------

# Get the JSON content written as part of the POST data
set post_content [ns_conn content]
array set json_hash [util::json::parse $post_content]
ns_log Notice "main-projects-forward-load-update: json_content=[array get json_hash]"

set json_list [list]
if {[info exists json_hash(_array_)]} {
    # Multiple records to be updated
    set json_list $json_hash(_array_)
}

if {[info exists json_hash(_object_)]} {
    # Single record to be updated
    set json_list [list [list "_object_" $json_hash(_object_)]]
}

# json_list contains a list of projects to move or enable/disable
# {_object_ {id 171036 project_id 171036 ... start_date 2015-01-07 end_date 2015-04-06 end_date_date 2015-03-31T02:00:00}}
set debug_json ""
foreach project_json_object $json_list {
    ns_log Notice "main-projects-forward-load-update: project_json_object=$project_json_object"
    set project_json [lindex $project_json_object 1]
    array set project_hash $project_json

    set project_id $project_hash(project_id)
    # append debug ", project_id=$project_id"
    set new_start_date $project_hash(start_date)
    set new_end_date $project_hash(end_date)

    db_1row project_info "
	select	start_date::date as old_start_date,
		end_date::date as old_end_date,
		to_char(:new_start_date::date, 'J')::integer - to_char(start_date, 'J')::integer as start_diff,
		to_char(:new_end_date::date, 'J')::integer - to_char(end_date::date, 'J')::integer as end_diff
	from	im_projects
	where	project_id = :project_id	 
    "
    set debug ", project_id=$project_id, old_start_date=$old_start_date, old_end_date=$old_end_date, new_start_date=$new_start_date, new_end_date=$new_end_date, start_diff=$start_diff, end_diff=$end_diff"
    ns_log Notice "main-projects-forward-load-update.tcl: $debug"
    append debug_json $debug

    # Move the project by start_diff days
    db_dml shift_project "
	update im_projects set
		start_date = start_date + '$start_diff days'::interval,
		end_date = end_date + '$start_diff days'::interval
	where
		project_id in (
			select	child.project_id
			from	im_projects child,
				im_projects parent
			where	parent.project_id = :project_id and
				child.tree_sortkey between parent.tree_sortkey and tree_right(parent.tree_sortkey)
		)
    "
    # ToDo: Do we also need to shift:
    # - financial documents
    # - forum items
    # - ???

}

set message_quoted "Successfully updated projects$debug"
set result "{\"succes\": true, \"message\": \"$message_quoted\"}"
doc_return 200 "text/html" $result

