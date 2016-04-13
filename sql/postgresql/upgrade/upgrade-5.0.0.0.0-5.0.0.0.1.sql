-- upgrade-5.0.0.0.0-5.0.0.0.1.sql
SELECT acs_log__debug('/packages/intranet-resource-management/sql/postgresql/upgrade/upgrade-5.0.0.0.0-5.0.0.0.1.sql','');


create or replace function inline_1 ()
returns integer as $BODY$
declare
        v_menu                integer;
        v_parent_menu         integer;
        v_senior_managers     integer;
begin
	
        select menu_id into v_parent_menu from im_menus where label = 'resource_management';
	delete from im_menus where label = 'projects_resource_planning' and v_parent_menu = v_parent_menu; 
 
        v_menu := im_menu__new (
                null,                                   -- p_menu_id
                'im_menu',                            -- object_type
                now(),                                  -- creation_date
                null,                                   -- creation_user
                null,                                   -- creation_ip
                null,                                   -- context_id
                'intranet-resource-management',   -- package_name
                'projects_resources_assignation_percentage', -- label
                'Resource Assignation %',      -- name
                '/intranet-resource-management/resources-planning',   -- url
                100,                                    -- sort_order
                v_parent_menu,                          -- parent_menu_id
                null                                    -- p_visible_tcl
        );

        select group_id into v_senior_managers from groups where group_name = 'Senior Managers';
        PERFORM acs_permission__grant_permission(v_menu, v_senior_managers, 'read');
        return 0;

end;$BODY$ language 'plpgsql';
select inline_1 ();
drop function inline_1();
