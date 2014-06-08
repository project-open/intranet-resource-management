# /packages/intranet-resource-management/lib/employee-assignment-pie-chart.tcl
#
# Copyright (C) 2012 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

# ----------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------

# The following variables are expected in the environment
# defined by the calling /tcl/*.tcl libary:
if {![info exists diagram_interval]} { set diagram_interval "next_quarter" }
if {![info exists diagram_width]} { set diagram_width 600 }
if {![info exists diagram_height]} { set diagram_height 400 }
if {![info exists diagram_title]} { set diagram_title [lang::message::lookup "" intranet-resource-management.Employee_Assignment "Employee Assignment"] }

# ----------------------------------------------------
# Diagram Setup
# ----------------------------------------------------

# Create a random ID for the diagram
set diagram_rand [expr round(rand() * 100000000.0)]
set diagram_id "employee_assignment_pie_chart_$diagram_rand"
