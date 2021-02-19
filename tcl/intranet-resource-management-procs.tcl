# /packages/intranet-resource-management/tcl/intranet-resource-management.tcl
#
# Copyright (C) 2010-2013 ]project-open[
#
# All rights reserved. Please check
# https://www.project-open.com/license/ for details.

ad_library {
    Report on and modify resource assignments to tasks of various types.
    @author frank.bergmann@project-open.com
    @author klaus.hofeditz@project-open.com
}


# ---------------------------------------------------------------
# Reusable Resource Management Components
# ---------------------------------------------------------------

ad_proc -public im_resource_management_cost_centers {
    {-start_date ""}
    {-end_date ""}
    {-limit_to_ccs_with_resources_p 1}
} {
    Returns a Hash with the list of all cost_centers in the system
    with name and the "perpetually" available users (member of the 
    cost_center).
} {
    # Variables of 
    set vars [im_rest_object_type_columns -include_acs_objects_p 0 -rest_otype "im_cost_center"]

    set limit_to_ccs_with_data ""
    if {$limit_to_ccs_with_resources_p} {
	set limit_to_ccs_with_data "and av.availability_percent is not null"
    }

    set cc_sql "
	select	cc.cost_center_id as object_id,
		cc.*,
		av.availability_percent
	from	im_cost_centers cc
		LEFT OUTER JOIN (
			select	e.department_id,
				sum(e.availability) as availability_percent
			from	im_employees e
			where	e.employee_id in (
				select	r.object_id_two
				from	acs_rels r,
					membership_rels mr
				where	r.rel_id = mr.rel_id and
					r.object_id_one = -2 and
					mr.member_state = 'approved'
				)
			group by e.department_id
		) av ON cc.cost_center_id = av.department_id
	where	1=1
		$limit_to_ccs_with_data
	order by cc.cost_center_code
    "
    db_foreach cost_centers $cc_sql {
	array unset value_hash
	foreach v $vars {
	    set value_hash($v) [set $v]
	}
	set value_hash(availability_percent) $availability_percent
	set cc_hash($object_id) [array get value_hash]
    }

    return [array get cc_hash]
}


ad_proc -public im_resource_management_user_absences {
    {-start_date ""}
    {-end_date ""}
} {
    Returns a Hash with the list of all absences in the interval.
} {
    # Variables of 
    set vars [im_rest_object_type_columns -include_acs_objects_p 0 -rest_otype "im_user_absence"]

    set date_where ""
    if {"" != $start_date} { append date_where "and end_date >= :start_date::date " }
    if {"" != $end_date} { append date_where "and start_date <= :end_date::date " }

    set absences_sql "
	select	t.absence_id as object_id,
		t.*,
		a.*,
		e.*,
		to_char(a.start_date,'J') as start_date_julian,
		to_char(a.end_date,'J') as end_date_julian
	from	(-- Direct absences for a user within the period
		select	owner_id,
			absence_id
		from	im_user_absences
		where	group_id is null
			$date_where
	    UNION
		-- Absences via groups - Check if the user is a member of group_id
		select	mm.member_id as owner_id,
			absence_id
		from	im_user_absences a,
			group_distinct_member_map mm
		where	a.group_id = mm.group_id
			$date_where
		) t,
		im_user_absences a,
		im_employees e
	where	t.absence_id = a.absence_id and
		a.owner_id = e.employee_id
    "
    db_foreach absences $absences_sql {

	# Set the values into a Hash array
	array unset value_hash
	foreach v $vars {
	    set value_hash($v) [set $v]
	}
	
	# Calculate the number of workdays in the absence
	set absence_workdays 0
	for {set i $start_date_julian} {$i <= $end_date_julian} {incr i} {
	    array unset date_comps
	    array set date_comps [util_memoize [list im_date_julian_to_components $i]]

	    set dow $date_comps(day_of_week)
	    if {0 != $dow && 6 != $dow && 7 != $dow} { 
		# Workday
		incr absence_workdays
	    }
	}
	set value_hash(absence_workdays) $absence_workdays
	set value_hash(department_id) $department_id
	set absence_hash($object_id) [array get value_hash]
    }

    return [array get absence_hash]
}


# ---------------------------------------------------------------
# Auxillary procedures for Resource Report
# ---------------------------------------------------------------



ad_proc -public im_date_julian_to_components { 
    julian_date 
} {
    Takes a Julian data and returns an array of its components:
    Year, MonthOfYear, DayOfMonth, WeekOfYear, Quarter
} {
    im_security_alert_check_integer -location "im_date_julian_to_components" -value $julian_date
    return [util_memoize [list im_date_julian_to_components_helper $julian_date] 3600]
}


ad_proc -public im_date_julian_to_components_helper { 
    julian_date 
} {
    Takes a Julian data and returns an array of its components:
    Year, MonthOfYear, DayOfMonth, WeekOfYear, Quarter
} {
    im_security_alert_check_integer -location "im_date_julian_to_components" -value $julian_date

    set ansi [dt_julian_to_ansi $julian_date]
    regexp {(....)-(..)-(..)} $ansi match year month_of_year day_of_month

    set first_year_julian [dt_ansi_to_julian $year 1 1]
    set day_of_year [expr {$julian_date - $first_year_julian + 1}]
    set week_of_year [util_memoize [list db_string dow "select to_char(to_date('$julian_date', 'J'),'IW')"]]
    set day_of_week [util_memoize [list db_string dow "select extract(dow from to_date('$julian_date', 'J'))"]]
    if {0 == $day_of_week} { set day_of_week 7 }

    # Trim zeros
    if {"0" eq [string range $month_of_year 0 0]} { set month_of_year [string range $month_of_year 1 end] }
    if {"0" eq [string range $week_of_year 0 0]} { set week_of_year [string range $week_of_year 1 end] }
    if {"0" eq [string range $day_of_month 0 0]} { set day_of_month [string range $day_of_month 1 end] }

    set quarter_of_year [expr {1 + int(($month_of_year-1) / 3)}]

    # Julian weeks start on a Monday
    set jul_week [expr { int($julian_date) / 7}]

    return [list \
		year $year \
		month_of_year $month_of_year \
		day_of_month $day_of_month \
		week_of_year $week_of_year \
		quarter_of_year $quarter_of_year \
		day_of_year $day_of_year \
		day_of_week $day_of_week \
		julian_week $jul_week \
    ]
}


ad_proc -public im_date_julian_to_week_julian { julian_date } {
    Takes a Julian data and returns the julian date of the week's day "1" (=Monday)
} {
    array set week_info [util_memoize [list im_date_julian_to_components $julian_date]]
    set result [expr {$julian_date - $week_info(day_of_week)}]
}



ad_proc -public im_date_components_to_julian { top_vars top_entry} {
    Takes an entry from top_vars/top_entry and tries
    to figure out the julian date from this
} {

    set year 0
    set week_of_year 0
    set day_of_week 0 
    set month 0 
    
    set ctr 0
    foreach var $top_vars {
	set val [lindex $top_entry $ctr]
	# Remove trailing "0" in week_of_year
	set val [string trimleft $val "0"]
	if {"" == $val} { set val 0 }
	set $var $val
	incr ctr
    }

    set julian 0

    # -------------------------------------------------------------
    # Try to calculate the current data from top dimension
    # -------------------------------------------------------------
    
    # Security 
    if { ![string is integer $year] || ![string is integer $month] || ![string is integer $week_of_year] || ![string is integer $day_of_week] } {
	    ad_return_complaint 1 "<b>Unable to calculate data from date dimension</b>:<br/> Found non-integer"
    }

    switch $top_vars {
	"year week_of_year day_of_week" {
	    catch {
		set julian [dt_ansi_to_julian_single_arg [db_string get_iso_week_date "select (to_date('$year-$week_of_year', 'IYYY-IW')::date + interval '[expr {$day_of_week-1}]' day)::date;" -default 0]]
	    }
	}
	"year week_of_year" {
	    catch {
		set julian [dt_ansi_to_julian_single_arg [db_string get_iso_week_date "select (to_date('$year-$week_of_year', 'IYYY-IW')::date)::date;" -default 0]]
	    }
	}
	"year month_of_year day_of_month" {
	    catch {
		if {1 == [string length $month_of_year]} { set month_of_year "0$month_of_year" }
		if {1 == [string length $day_of_month]} { set day_of_month "0$day_of_month" }
		set julian [dt_ansi_to_julian_single_arg "$year-$month_of_year-$day_of_month"]

	    }
	}
	"year month_of_year" {
	    catch {
		if {1 == [string length $month_of_year]} { set month_of_year "0$month_of_year" }
                set julian [dt_ansi_to_julian_single_arg "$year-$month_of_year-01"]
	    }
	}
    }

    if {0 == $julian} { 
	ad_return_complaint 1 "<b>Unable to calculate data from date dimension</b>:<br><pre>$top_vars<br>$top_entry" 
	ad_script_abort
    }

    ns_log Notice "im_date_components_to_julian: $julian, top_vars=$top_vars, top_entry=$top_entry"
    return $julian
}



# ---------------------------------------------------------------
# Show the status of potential freelancers in the member-add page
# ---------------------------------------------------------------

ad_proc im_resource_mgmt_resource_planning_add_member_component { } {
    Component that returns a formatted HTML table.
    The table contains the availability for all persons with
    matching freelance profiles.
} {
    # ------------------------------------------------
    # Security
    # Check that the user has the right to "read" the group Freelancers
  
    set user_id [ad_conn user_id]
    set perm_p [db_string freelance_read "select im_object_permission_p([im_profile_freelancers], :user_id, 'read')"]
    if {"t" != $perm_p} {
        return ""
    }

    # Only show if the freelance package is installed.
    if {![db_table_exists im_freelance_skills]} { return "" }
    

    # ------------------------------------------------
    # Constants

    set source_lang_skill_type 2000
    set target_lang_skill_type 2002

    set order_freelancer_sql "user_name"

    # Project's Source & Target Languages
    set project_source_lang ""
    set project_target_langs ""
    catch {
    set project_source_lang [db_string source_lang "
                select  substr(im_category_from_id(source_language_id), 1, 2)
                from    im_projects
                where   project_id = :object_id" \
    -default 0]

    set project_target_langs [db_list target_langs "
		select '''' || substr(im_category_from_id(language_id), 1, 2) || '''' 
		from	im_target_languages 
		where	project_id = :object_id
    "]
    }
    if {0 == [llength $project_target_langs]} { set project_target_langs [list "'none'"]}


    # ------------------------------------------------
    # Get the list of users that meet source- and target language requirements

    set freelance_sql "
	select distinct
		u.user_id,
		im_name_from_user_id(u.user_id) as user_name
	from
		users u,
		group_member_map m, 
		membership_rels mr,
		(	select	user_id
			from	im_freelance_skills
			where	skill_type_id = :source_lang_skill_type
				and substr(im_category_from_id(skill_id), 1, 2) = :project_source_lang
		) sls,
		(	select	user_id
			from	im_freelance_skills
			where	skill_type_id = :target_lang_skill_type
				and substr(im_category_from_id(skill_id), 1, 2) in ([join $project_target_langs ","])
		) tls
	where
		m.group_id = acs__magic_object_id('registered_users'::character varying) AND 
		m.rel_id = mr.rel_id AND 
		m.container_id = m.group_id AND 
		m.rel_type::text = 'membership_rel'::text AND 
		mr.member_state::text = 'approved'::text AND 
		u.user_id = m.member_id AND
		sls.user_id = u.user_id AND
		tls.user_id = u.user_id
	order by
		$order_freelancer_sql
    "
    
    set user_list {}
    db_foreach freelancers $freelance_sql {
	lappend user_list $user_id
    }

    # ------------------------------------------------
    # Call the resource planning compoment
    #

    db_1row date "
	select	now()::date as start_date,
		now()::date + 30 as end_date
    "

    set page_url "/intranet-resource-management/resources-planning"
    set result [im_resource_mgmt_resource_planning_percentage \
		    -report_start_date $start_date \
		    -report_end_date $end_date \
		    -top_vars "year month_of_year week_of_year" \
		    -report_user_id $user_list \
		    -page_url $page_url \
    ]
    
    return $result
}


ad_proc -private hsv2hex {h s v} {
	# https://code.activestate.com/recipes/133527/ (
	# Arguments: h hue, s saturation, v value
	# Results: Returns an rgb triple from hsv
	if {$s <= 0.0} {
        	# achromatic
	        set v [expr {int($v)}]
        	return "$v $v $v"
    	} else {
        	set v [expr {double($v)}]
	        if {$h >= 1.0} { set h 0.0 }
        	set h [expr {6.0 * $h}]
	        set f [expr {double($h) - int($h)}]
        	set p [expr {int(256 * $v * (1.0 - $s))}]
	        set q [expr {int(256 * $v * (1.0 - ($s * $f)))}]
        	set t [expr {int(256 * $v * (1.0 - ($s * (1.0 - $f))))}]
	        set v [expr {int(256 * $v)}]
        	switch [expr {int($h)}] {
	            0 { set rgb "$v $t $p" }
        	    1 { set rgb "$q $v $p" }
	            2 { set rgb "$p $v $t" }
        	    3 { set rgb "$p $q $v" }
	            4 { set rgb "$t $p $v" }
        	    5 { set rgb" $v $p $q" }
        	}
    	}

	set rgb_list [split $rgb " "]
	return "\#[format %x [lindex $rgb_list 0]][format %x [lindex $rgb_list 1]][format %x [lindex $rgb_list 2]]"
}

ad_proc -public im_absence_working_days_weekend_only {
    -start_date
    -end_date
} {
} {
    return [db_list get_work_days "select * from im_absences_working_days_period_weekend_only(:start_date::date, :end_date::date) as series_days (days date)"]
}

# ---------------------------------------------------------------
# Component showing related objects
# ---------------------------------------------------------------

ad_proc -public im_resource_mgmt_employee_assignment_pie_chart {
    {-diagram_interval "next_quarter"}
    {-diagram_width 600}
    {-diagram_height 350}
} {
    Returns a HTML component with a pie chart of user assignments
} {
    if {![im_sencha_extjs_installed_p]} { return "" }
    im_sencha_extjs_load_libraries

    set diagram_title [lang::message::lookup "" intranet-resource-management.Employee_Assignment "Employee Assignment"]
    set params [list \
                    [list diagram_interval $diagram_interval] \
                    [list diagram_width $diagram_width] \
                    [list diagram_height $diagram_height] \
                    [list diagram_title $diagram_title] \
    ]

    set result [ad_parse_template -params $params "/packages/intranet-resource-management/lib/employee-assignment-pie-chart"]
    return [string trim $result]
}

