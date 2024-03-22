-- upgrade-5.1.0.0.0-5.1.0.0.1.sql
SELECT acs_log__debug('/packages/intranet-resource-management/sql/postgresql/upgrade/upgrade-5.1.0.0.0-5.1.0.0.1.sql','');


create or replace function im_resource_mgmt_user_absence (integer, date, date)
returns float[] as $body$
-- Returns a real[] for each day between start and end 
-- with 100 for each day the user has taken vacation.
-- Half days off will appear with 0.5 (50%).
DECLARE
	p_user_id			alias for $1;
	p_start_date			alias for $2;
	p_end_date			alias for $3;

	v_weekday			integer;
	v_date				date;
	v_work_days			float[];
        v_absence_work_days             float[];
	v_result			float[];
	v_absence_duration_work_days	integer;
	v_absence_percentage		float;
	row				record;
BEGIN
	v_work_days = im_resource_mgmt_work_days(p_user_id, p_start_date, p_end_date);

	-- Initiate the result array with weekends
	v_date := p_start_date;
	WHILE (v_date <= p_end_date) LOOP
		v_result[v_date - p_start_date] := 0;
		v_date := v_date + 1;
	END LOOP;

	-- Loop through all of the user absences between start_date and end_date
	-- And add them to the result
	FOR row IN
		select	*
		from	im_user_absences a
		where	a.owner_id = p_user_id and
			a.end_date >= p_start_date and
			a.start_date <= p_end_date and
			a.absence_status_id not in (16002, 16006) 		--- deleted or rejected
	LOOP
		-- Calculate the number of work days in the absence
		v_absence_duration_work_days = 0;

                -- Calculate the workable days during the absence.
                -- Use the v_work_days by default, unless the absence is (partially) outside the reporting interval
                IF (row.start_date::date >= p_start_date::date AND row.end_date::date <= p_end_date::date) THEN
                        -- The absence completely contained within the report interval. Just use work_days
		        v_date := row.start_date;
		        WHILE (v_date <= row.end_date) LOOP
			        IF v_work_days[v_date - p_start_date::date] > 0 THEN
				        v_absence_duration_work_days = 1 + v_absence_duration_work_days;
			        END IF;
			        v_date := v_date + 1;
		        END LOOP;
		        -- RAISE NOTICE 'im_resource_mgmt_user_absence(%,%,%): Absence % in report interval: dur=%, workdays=%, start=%, end=%', p_user_id, p_start_date, p_end_date, row.absence_name, row.duration_days, v_absence_duration_work_days, row.start_date::date, row.end_date::date;
                ELSE
                        -- The absence intersects the boundaries of the reporting interval. We need to calculate the work_days during the absence.
                        v_absence_work_days = im_resource_mgmt_work_days(p_user_id, row.start_date::date, row.end_date::date);
		        -- RAISE NOTICE 'im_resource_mgmt_user_absence(%,%,%): Absence % outside report interval: v_absence_work_days=%', p_user_id, p_start_date, p_end_date, row.absence_name, v_absence_work_days;
		        v_date := row.start_date;
		        WHILE (v_date <= row.end_date) LOOP
			        IF v_absence_work_days[v_date - row.start_date::date] > 0 THEN
				        v_absence_duration_work_days = 1 + v_absence_duration_work_days;
			        END IF;
			        v_date := v_date + 1;
		        END LOOP;
		        -- RAISE NOTICE 'im_resource_mgmt_user_absence(%,%,%): Absence % outside report interval: dur=%, workdays=%, start=%, end=%', p_user_id, p_start_date, p_end_date, row.absence_name, row.duration_days, v_absence_duration_work_days, row.start_date::date, row.end_date::date;

                END IF;

		WHILE (v_date <= row.end_date) LOOP
			IF v_absence_work_days[v_date - row.start_date::date] > 0 THEN
				v_absence_duration_work_days = 1 + v_absence_duration_work_days;
			END IF;
			v_date := v_date + 1;
		END LOOP;

		-- Calculate the percentage away
		IF 0 != v_absence_duration_work_days THEN
			v_absence_percentage := 100.0 * row.duration_days / v_absence_duration_work_days;
		ELSE
			-- Error: Division by zero:
			-- The vacation is completely within bank holidays.
			RAISE WARNING 'im_resource_mgmt_user_absence(%,%,%): Absence %: No workdays for vacation', p_user_id, p_start_date, p_end_date, row.absence_name;
			v_absence_percentage := 0;
		END IF;
		IF v_absence_duration_work_days > 100 THEN
			-- Error: Overlapping vacations or duration days > work days
			RAISE WARNING 'im_resource_mgmt_user_absence(%,%,%): Absence %: More duration_days=% than work_days=%', p_user_id, p_start_date, p_end_date, row.absence_name, row.duration_days, v_absence_duration_work_days;
			v_absence_percentage := 100;
		END IF;

		-- Add the absence percentage to the result set
		-- RAISE NOTICE 'im_resource_mgmt_user_absence(%,%,%): Absence %: dur=%, workdays=%, perc=%, start=%, end=%', p_user_id, p_start_date, p_end_date, row.absence_name, row.duration_days, v_absence_duration_work_days, v_absence_percentage, row.start_date, row.end_date;

		-- Add the vacation to the vacation days
		v_date := row.start_date;
		WHILE (v_date <= row.end_date) LOOP
			IF v_work_days[v_date - p_start_date] > 0 THEN
				v_result[v_date - p_start_date] := v_absence_percentage + v_result[v_date - p_start_date];
			END IF;
			v_date := v_date + 1;
		END LOOP;		
	END LOOP;

	return v_result;
END;$body$ language 'plpgsql';
-- select im_resource_mgmt_user_absence(11180, '2019-11-01', '2019-11-30');


