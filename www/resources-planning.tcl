# /packages/intranet-reporting/www/resources-planning.tcl
#
# Copyright (c) 2003-2006 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/ for licensing details.

set clicks_base [clock clicks]

ad_page_contract {
    Gantt Resource Planning.
    This page is similar to the resources-cube, but using a different
    approach and showing absences and translation tasks as well

    @param start_date Hard start of reporting period. Defaults to start of first project
    @param end_date Hard end of replorting period. Defaults to end of last project
    @param level_of_details Details of date axis: 1 (month), 2 (week) or 3 (day)
    @param project_id Id of project(s) to show. Defaults to all active projects
    @param customer_id Id of customer's projects to show
    @param user_name_link_opened List of users with details shown
} {
    { start_date "" }
    { end_date "" }
    { show_all_employees_p "" }
    { top_vars "year month_of_year day_of_month" }
    { project_id:multiple "" }
    { customer_id:integer 0 }
    { project_status_id:integer 0 }
    { project_type_id:integer 0 }
    { employee_cost_center_id 0 }
    { program_id 0 }
    { zoom "" }
    { max_col 20 }
    { max_row 100 }
}

#    { top_vars "year week_of_year day_of_week" }

# ---------------------------------------------------------------
# Defaults & Security
# ---------------------------------------------------------------

im_permission_flush

set current_user_id [auth::require_login]
if {![im_permission $current_user_id "view_projects_all"]} {
    ad_return_complaint 1 "You don't have permissions to see this page"
    ad_script_abort
}

# ------------------------------------------------------------
# Defaults

set page_title [lang::message::lookup "" intranet-reporting.Gantt_Resources "Gantt Resources"]
set page_url "/intranet-resource-management/resources-planning"
set sub_navbar ""
set main_navbar_label "resource_management"
set show_context_help_p 0
set return_url [im_url_with_query]

regsub -all {%20} $top_vars " " top_vars
regsub -all {\+} $top_vars " " top_vars

set restrict_to_user_department_by_default_p [parameter::get_from_package_key -package_key "intranet-resource-management" -parameter RestrictToUserDepartmentByDefaultP -default 0]


# ------------------------------------------------------------
# Start and End-Dat as min/max of selected projects.
# Note that the sub-projects might "stick out" before and after
# the main/parent project.


if {$restrict_to_user_department_by_default_p} {
    if {0 == $employee_cost_center_id && "" == $start_date && "" == $end_date} {
        set employee_cost_center_id [db_string current_user_cc "
		select	department_id
		from	im_employees
		where	employee_id = :current_user_id
        " -default ""]
    }
}

if {0 == $start_date || "" == $start_date} {
    set start_date [db_string start_date "select to_char(now()::date, 'YYYY-MM-01')"]
}

if {0 == $end_date || "" == $end_date} {
    set end_date [db_string end_date "select to_char(now()::date + 4*7, 'YYYY-MM-01')"]
}


# ------------------------------------------------------------
# Contents

set html [im_resource_mgmt_resource_planning_percentage \
	-report_start_date $start_date \
	-report_end_date $end_date \
	-top_vars $top_vars \
	-report_project_id $project_id \
	-report_project_status_id $project_status_id \
	-report_project_type_id $project_type_id \
	-report_customer_id $customer_id \
	-report_employee_cost_center_id $employee_cost_center_id \
	-show_all_employees_p $show_all_employees_p \
	-excluded_group_ids "" \
	-page_url $page_url \
]

if {"" == $html} { 
    set html [lang::message::lookup "" intrant-ganttproject.No_resource_assignments_found "No resource assignments found"]
    set html "<p>&nbsp;<p><blockquote><i>$html</i></blockquote><p>&nbsp;<p>\n"
}




# ---------------------------------------------------------------
# 6. Format the Filter
# ---------------------------------------------------------------

set filter_html "
<form method=get name=projects_filter action='$page_url'>
[export_vars -form {start_idx order_by how_many view_name include_subprojects_p letter}]
<table border=0 cellpadding=0 cellspacing=1>
"

if {0} {
    append filter_html "
  <tr>
    <td class=form-label>[lang::message::lookup "" intranet-core.Program "Program"]:</td>
    <td class=form-widget>[im_project_select -include_empty_p 1 -project_type_id [im_project_type_program] program_id $program_id]</td>
  </tr>
    "
}

if { $customer_id eq "" } {
    set customer_id 0
}

if {0} {
    append filter_html "
  <tr>
<td class=form-label valign=top>[lang::message::lookup "" intranet-core.Customer "Customer"]:</td>
<td class=form-widget valign=top>[im_company_select -include_empty_p 1 -include_empty_name "All" customer_id $customer_id "" "CustOrIntl"]</td>
  </tr>
    "
}


if {0} {
    # Not yet supported: "year quarter_of_year", "Quarter"
    set top_var_options {
	"year week_of_year day_of_week"		"Week and Day"
	"year month_of_year day_of_month"	"Month and Day"
	"year week_of_year"			"Week"
    }
#	"year month_of_year"			"Month"

    append filter_html "
  <tr>
    <td class=form-label>[lang::message::lookup "" intranet-ganttproject.Top_Scale "Top Scale"]:</td>
    <td class=form-widget>[im_select top_vars $top_var_options $top_vars]</td>
  </tr>
    "
}

append filter_html "
  <tr>
	<td class=form-label>[_ intranet-core.Start_Date]</td>
            <td class=form-widget>
              <input type=textfield name=start_date value=$start_date>
	</td>
  </tr>
  <tr>
	<td class=form-label>[lang::message::lookup "" intranet-core.End_Date "End Date"]</td>
            <td class=form-widget>
              <input type=textfield name=end_date value=$end_date>
	</td>
  </tr>
"


if {1} {
    append filter_html "
  <tr>
    <td class=form-label>[_ intranet-core.Department]:</td>
    <td class=form-widget>[im_cost_center_select -include_empty 1 -include_empty_name "All" -department_only_p 1 employee_cost_center_id $employee_cost_center_id]</td>
  </tr>
    "
}

if {1} {
    append filter_html "
  <tr>
    <td class=form-label>[_ intranet-core.Project_Status]:</td>
    <td class=form-widget>[im_category_select -include_empty_p 1 "Intranet Project Status" project_status_id $project_status_id]</td>
  </tr>
    "
}

if {1} {
append filter_html "
  <tr>
    <td class=form-label>[_ intranet-core.Project_Type]:</td>
    <td class=form-widget>
      [im_category_select -include_empty_p 1 "Intranet Project Type" project_type_id $project_type_id]
    </td>
  </tr>
"
}



set show_all_employees_checked ""
if {1 == $show_all_employees_p} { set show_all_employees_checked "checked" }
append filter_html "
  <tr>
	<td class=form-label valign=top>[lang::message::lookup "" intranet-ganttproject.All_Employees "Show all:"]</td>
	<td class=form-widget valign=top>
	        <input name=show_all_employees_p type=checkbox value='1' $show_all_employees_checked> 
		[lang::message::lookup "" intranet-core.Employees "Employees?"]
	</td>
  </tr>
"

append filter_html "
  <tr>
    <td class=form-label></td>
    <td class=form-widget>
	  <input type=submit value='[lang::message::lookup "" intranet-core.Action_Go "Go"]' name=submit>
    </td>
  </tr>
"

append filter_html "</table>\n</form>\n"


# ---------------------------------------------------------------
# Help message
#
set help_html [im_help_collapsible [lang::message::lookup "" intranet-resource-management.Percentage_Report_Help "
<h2>Resource Management Report - By Percentage</h2>
<p>This resource management report shows summarized assignments of natural persons by task,
project, user and department, aggregated from the actual to a task up the project hierarchy 
towards the user and department level.</p>
<p>Important comments:</p>
<ul>
<li><b>Effective Working Time</b>:<br>
    The values shown in this report refer to percentages of the effective working time
    of resources.
    This time can be set in the 'Employee Information' portlet on the user's page. <br>
    Example: Assigning a user working a 50% part-time job to a task with 80% will 
    result in a 40% assignment.
<li><b>Assignment Duration and Precision</b>:<br>
    The duration of an assignment includes both the start and end date of the task.
    Assignments are currently only per days. Future versions of this report
    will allow for assignments per hour and minute based on a calendar with
    working hours.
<li><b>Vacation and other absences</b>:<br>
    This report counts vacation as additional assignments. They are added to the
    project assignments. <br>
    Example: A user assigned with 100% to a task will be shown as overassigned, 
    if he is going for vacation during the time of the task.<br>
    Other absences may or may not count as vacation time. 
</ul>
"]]
set help_html "<table width='50%' align=left border=0><tr><td>$help_html</td></tr></table>\n"


# ---------------------------------------------------------------
# Navbars
# ---------------------------------------------------------------

set main_navbar_label "resource_management"
set bind_vars [ns_set create]
set parent_menu_id [db_string parent_menu "select menu_id from im_menus where label = :main_navbar_label"]
set sub_navbar [im_sub_navbar \
                    -components \
                    -base_url "/intranet-resource-management/index" \
                    -plugin_url "/intranet-resource-management/index" \
                    -menu_gif_type "none" \
                    $parent_menu_id \
                    $bind_vars \
		    "" \
		    "pagedesriptionbar" \
		    "projects_resource_planning" \
]

# Left Navbar is the filter/select part of the left bar
set left_navbar_html "
	<div class='filter-block'>
        	<div class='filter-title'>
	           [_ intranet-core.Filter_Projects]
        	</div>
            	$filter_html
      	</div>
      <hr/>
"


# ---------------------------------------------------------------
# Color Codes
#
set color_list [im_absence_cube_color_list]
set col_sql "
        select  category_id, category
        from    im_categories
        where   category_type = 'Intranet Absence Type'
        order by category_id
"
append absence_color_codes "<div class=filter-title>&nbsp;[lang::message::lookup "" intranet-timesheet2.Absences_Color_Codes "Absences Color Codes"]</div>\n"
append absence_color_codes "<table cellpadding='5' cellspacing='5'>\n"
db_foreach cols $col_sql {
    set index [expr $category_id - 5000]
    set col [lindex $color_list $index]
    regsub -all " " $category "_" category_key
    set category_l10n [lang::message::lookup "" intranet-core.$category_key $category]
    append absence_color_codes "<tr><td>&nbsp;&nbsp;&nbsp;</td><td bgcolor='\#$col' style='padding:3px'>$category_l10n</td></tr>\n"
}
append absence_color_codes "</table>\n"

append left_navbar_html "<br>$absence_color_codes"


