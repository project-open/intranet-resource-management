-- upgrade-5.0.3.0.0-5.0.3.0.1.sql
SELECT acs_log__debug('/packages/intranet-resource-management/sql/postgresql/upgrade/upgrade-5.0.3.0.0-5.0.3.0.1.sql','');



-- Returns a real[] for each day between start and end 
-- with 100 for working days and 0 for weekend + bank holidays
create or replace function im_resource_mgmt_work_days (integer, date, date)
returns float[] as $body$
DECLARE
	p_user_id			alias for $1;
	p_start_date			alias for $2;
	p_end_date			alias for $3;

	v_weekday			integer;
	v_date				date;
	v_work_days			float[];
	v_date_difference		integer;
	v_perc				float;
	v				float;
	row				record;
BEGIN
	v_work_days = im_resource_mgmt_weekend(p_user_id, p_start_date, p_end_date);

	-- Apply "Bank Holiday" absences
	FOR row IN
		select	a.*
		from	im_user_absences a
		where	(	a.owner_id = p_user_id OR
				a.group_id = p_user_id OR
				a.group_id in (select group_id from group_distinct_member_map where member_id = p_user_id)
			) and
			a.end_date::date >= p_start_date and
			a.start_date::date <= p_end_date and
			a.absence_type_id in (select * from im_sub_categories(5005)) and 		-- only bank holidays
			a.absence_status_id not in (select * from im_sub_categories(16002) union select * from im_sub_categories(16006)) -- exclude deleted and rejected
	LOOP
		-- Take into
		v_date_difference = 1 + row.end_date::date - row.start_date::date;
		v_perc = 100.0 * row.duration_days / v_date_difference;
		-- RAISE NOTICE 'im_resource_mgmt_work_days(%,%,%): Bank Holiday %', p_user_id, p_start_date, p_end_date, row.absence_name;
		v_date := row.start_date;
		WHILE (v_date <= row.end_date) LOOP
		        v := v_work_days[v_date - p_start_date];
			v := v - v_perc;
			if v < 0.0 THEN v := 0.0; END IF;
			v_work_days[v_date - p_start_date] := v;
			v_date := v_date + 1;
		END LOOP;
	END LOOP;

	return v_work_days;
END;$body$ language 'plpgsql';
-- select im_resource_mgmt_work_days(624, '2019-12-23', '2019-12-30');
-- select im_resource_mgmt_work_days(463, '2018-12-01'::date, '2019-01-01');

