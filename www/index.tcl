# /packages/intranet-resource-management/www/index.tcl
#
# Copyright (C) 2003 - 2011 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/license/ for details.

ad_page_contract {
    Offers all around resource management
    @author frank.bergmann@project-open.com
} {

}
set user_id [ad_maybe_redirect_for_registration]
set page_title [lang::message::lookup "" intranet-resource-management.Resource_Management_Home "Resource Management Home"]
set context_bar [im_context_bar $page_title]
set return_url [im_url_with_query]

# ---------------------------------------------------------------
# Sub-Navbar
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
		    $bind_vars "" "pagedesriptionbar" "resource_management_home" \
		    ]


# ---------------------------------------------------------------
# Format the admin menu
# ---------------------------------------------------------------

set admin_html ""
set admin_html "<ul>$admin_html</ul>"

append left_navbar_html "
	    <div class=\"filter-block\">
		<div class=\"filter-title\">
		    [lang::message::lookup "" intranet-cost.Admin "Administration"]
		</div>
		$admin_html
	    </div>
	    <hr/>
"
