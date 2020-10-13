-- upgrade-5.0.4.0.0-5.0.4.0.1.sql
SELECT acs_log__debug('/packages/intranet-resource-management/sql/postgresql/upgrade/upgrade-5.0.4.0.0-5.0.4.0.1.sql','');



-- Returns a real[] for each day between start and end 
-- with 100 for a full absence (vacation, bank holiday, ...any)

drop function if exists im_resource_mgmt_absence_days(integer, date, date);
create or replace function im_resource_mgmt_absence_days (integer, date, date)
returns float[] as $body$
DECLARE
	p_user_id			alias for $1;
	p_start_date			alias for $2;
	p_end_date			alias for $3;

	v_offset			integer;
	v_max_offset			integer;
	v_weekday			integer;
	v_date				date;
	v_work_days			float[];
	v_date_difference		integer;
	v_perc				float;
	v				float;
	row				record;
BEGIN
	-- Initiate the result array with zeros
	-- The array starts (index 0) with p_start_date and ends with p_end_date
	v_date := p_start_date;
	WHILE (v_date <= p_end_date) LOOP
		v_offset = (v_date - p_start_date);
		v_work_days[v_offset] := 0;
		v_date := v_date + 1;
	END LOOP;

	-- Apply absences
	v_max_offset = (p_end_date - p_start_date);
	FOR row IN
		select	a.*
		from	im_user_absences a
		where	(a.owner_id = p_user_id OR a.group_id = p_user_id OR a.group_id in (select group_id from group_distinct_member_map where member_id = p_user_id)) and
			a.end_date::date >= p_start_date and a.start_date::date <= p_end_date and
			-- a.absence_type_id in (select * from im_sub_categories(5005)) and 		-- only bank holidays
			a.absence_status_id not in (select * from im_sub_categories(16002) union select * from im_sub_categories(16006)) -- exclude deleted and rejected
	LOOP
		v_date_difference = 1 + row.end_date::date - row.start_date::date;
		v_perc = 100.0 * row.duration_days / v_date_difference;
		RAISE NOTICE 'im_resource_mgmt_work_days(%,%,%): Absence %: %perc', p_user_id, row.start_date::date, row.end_date::date, row.absence_name, v_perc;
		v_date := row.start_date;
		WHILE (v_date <= row.end_date) LOOP

			v_offset = (v_date - p_start_date);
			v_date := v_date + 1;

			if v_offset < 0 THEN continue; END IF;
			if v_offset > v_max_offset THEN continue; END IF;

		        v := v_work_days[v_offset];
			IF v is null THEN RAISE EXCEPTION 'im_resource_mgmt_absence_days: found null in array at offset %', v_offset; continue; END IF;
			v := v + v_perc;
			if v > 100.0 THEN v := 100.0; END IF;
			v_work_days[v_offset] := v;
		END LOOP;
	END LOOP;

	-- Set weekends to zero
	v_date := p_start_date;
	WHILE (v_date <= p_end_date) LOOP
		v_weekday := to_char(v_date, 'D');
		IF v_weekday = 1 OR v_weekday = 7 THEN
			v_work_days[v_date - p_start_date] := 0;
		END IF;
		v_date := v_date + 1;
	END LOOP;


	return v_work_days;
END;$body$ language 'plpgsql';

-- select im_resource_mgmt_work_days(55807, '2020-10-01', '2020-10-31');
-- select im_resource_mgmt_work_days_cosine(55807, '2020-10-01', '2020-10-31');

-- select im_resource_mgmt_absence_days(55807, '2020-10-01', '2020-10-31');
select im_resource_mgmt_absence_days(55807, '2019-03-19', '2021-01-29');

