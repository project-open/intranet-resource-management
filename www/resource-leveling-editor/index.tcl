# /packages/sencha-task-editor/www/resource-leveling-editor/index
#
# Copyright (c) 2014 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/ for licensing details.

ad_page_contract {
    Editor for projects
} {
    { report_start_date "" }
    { report_end_date "" }
    { report_granularity "week" }
    { project_id:multiple "" }
    { report_customer_id:integer 0 }
    { report_project_type_id:integer 0 }
    { report_program_id 0 }
}

# ---------------------------------------------------------------
# Defaults & Security
# ---------------------------------------------------------------

set current_user_id [ad_maybe_redirect_for_registration]
if {![im_permission $current_user_id "view_projects_all"]} {
    ad_return_complaint 1 "You don't have permissions to see this page"
    ad_script_abort
}

# ------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------

set page_title [lang::message::lookup "" intranet-reporting.Resource_Leveling_Editor "Resource Leveling Editor"]
set page_url "/intranet-resource-management/resource-leveling-editor/index"
set main_navbar_label "resource_management"
set context_bar [im_context_bar $page_title]
set return_url [im_url_with_query]

if {"" == $report_start_date} { set report_start_date [db_string report_start_date "select to_char(now(), 'YYYY-MM-01') from dual"] }
if {"" == $report_end_date} { set report_end_date [db_string report_end_date "select :report_start_date::date + '3 months'::interval"] }
if {0 == $report_project_type_id} { set report_project_type_id [im_project_type_consulting] }



# ---------------------------------------------------------------
# Sencha Processing
# ---------------------------------------------------------------

# Load Sencha 
im_sencha_extjs_load_libraries


set project_main_store_where ""
if {"" != $report_project_type_id} {
    append project_main_store_where "and project_type_id in (select * from im_sub_categories($report_project_type_id)) "
}
if {"" != $report_customer_id} {
    append project_main_store_where "and company_id = $report_customer_id "
}
if {"" != $report_program_id} {
    append project_main_store_where "and program_id = $report_program_id "
}



# ---------------------------------------------------------------
# Format the Filter
# ---------------------------------------------------------------

set filter_html "
<form method=get name=projects_filter action='$page_url'>
<table border=0 cellpadding=0 cellspacing=1>
"

if { [empty_string_p $report_customer_id] } {
    set report_customer_id 0
}

append filter_html "
  <tr>
	<td class=form-label>[_ intranet-core.Start_Date]</td>
            <td class=form-widget>
              <input type=textfield name=report_start_date value=$report_start_date>
	</td>
  </tr>
  <tr>
	<td class=form-label>[lang::message::lookup "" intranet-core.End_Date "End Date"]</td>
            <td class=form-widget>
              <input type=textfield name=report_end_date value=$report_end_date>
	</td>
  </tr>
"


if {1} {
    set granularity_options [list "day" [_ intranet-core.Day] "week" [_ intranet-core.Week]]

    append filter_html "
  <tr>
<td class=form-label valign=top>[lang::message::lookup "" intranet-resource-management.Planning_Granularity "Granularity"]:</td>
<td class=form-widget valign=top>[im_select -ad_form_option_list_style_p 0 report_granularity $granularity_options $report_granularity]</td>
  </tr>
    "
}


if {1} {
    append filter_html "
  <tr>
<td class=form-label valign=top>[lang::message::lookup "" intranet-core.Customer "Customer"]:</td>
<td class=form-widget valign=top>[im_company_select -include_empty_p 1 -include_empty_name "All" report_customer_id $report_customer_id "" "CustOrIntl"]</td>
  </tr>
    "
}

if {1} {
append filter_html "
  <tr>
    <td class=form-label>[_ intranet-core.Project_Type]:
    <a target='_' href='http://www.project-open.org/en/category_intranet_project_type'>[im_gif help]</a>
    </td>
    <td class=form-widget>
      [im_category_select -include_empty_p 1 "Intranet Project Type" report_project_type_id $report_project_type_id]
    </td>
  </tr>
"
}

if {1} {
    append filter_html "
  <tr>
    <td class=form-label>[lang::message::lookup "" intranet-core.Program "Program"]:</td>
    <td class=form-widget>[im_project_select -include_empty_p 1 -project_type_id [im_project_type_program] report_program_id $report_program_id]</td>
  </tr>
    "
}

append filter_html "
  <tr>
    <td class=form-label></td>
    <td class=form-widget>
	  <input type=submit value='[lang::message::lookup "" intranet-core.Filter "Filter"]' name=submit>
    </td>
  </tr>
"

append filter_html "</table>\n</form>\n"


# ---------------------------------------------------------------
# Left Navbar
# ---------------------------------------------------------------

# Project Navbar goes to the top
#
set letter ""
set next_page_url ""
set previous_page_url ""
set menu_select_label ""

# Left Navbar is the filter/select part of the left bar
set left_navbar_html "
	<div class='filter-block'>
        	<div class='filter-title'>
	           #intranet-core.Filter_Projects#
        	</div>
            	$filter_html
      	</div>
      <hr/>
"


# ---------------------------------------------------------------
# Sub-Navbar
# ---------------------------------------------------------------

set main_navbar_label "resource_management"
set bind_vars [ns_set create]
set parent_menu_id [im_menu_id_from_label $main_navbar_label]
set sub_navbar [im_sub_navbar \
		    -components \
                    -base_url "/intranet-resource-management/index" \
                    -plugin_url "/intranet-resource-management/index" \
                    -menu_gif_type "none" \
                    $parent_menu_id \
		    $bind_vars "" "pagedesriptionbar" "resource_leveling_editor" \
]


