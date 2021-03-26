# /packages/intranet-resource-management/lib/employee-assignment-pie-chart.tcl
#
# Copyright (C) 2012 ]project-open[
#
# All rights reserved. Please check
# https://www.project-open.com/license/ for details.

# ----------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------

# The following variables are expected in the environment
# defined by the calling /tcl/*.tcl libary:
if {![info exists diagram_interval]} { set diagram_interval "next_quarter" }
if {![info exists diagram_width]} { set diagram_width 600 }
if {![info exists diagram_height]} { set diagram_height 400 }
if {![info exists diagram_title]} { set diagram_title [lang::message::lookup "" intranet-resource-management.Employee_Assignment "Employee Assignment"] }

set company_department_id [im_cost_center_company]

# ----------------------------------------------------
# Diagram Setup
# ----------------------------------------------------

# Create a random ID for the diagram
set diagram_rand [expr {round(rand() * 100000000.0)}]
set diagram_id "employee_assignment_pie_chart_$diagram_rand"

#ToDo: Eliminate deleted employees
set department_sql "
	select	cc.cost_center_id,
		cc.cost_center_name,
		length(cc.cost_center_code) - 2 as indent,
		e.employee_id,
		im_name_from_user_id(e.employee_id) as employee_name
	from	im_cost_centers cc
		LEFT OUTER JOIN im_employees e ON (cc.cost_center_id = e.department_id)
	where	1 = 1
	order by cc.cost_center_code, employee_name
"
multirow create departments value indent display
set last_cost_center_id ""
db_foreach departments $department_sql {
    if {$cost_center_id != $last_cost_center_id} {
	multirow append departments $cost_center_id $indent $cost_center_name
	set last_cost_center_id $cost_center_id
    }

    if {"" != $employee_id} {
	multirow append departments $employee_id [expr {1+$indent}] $employee_name
    }
}


