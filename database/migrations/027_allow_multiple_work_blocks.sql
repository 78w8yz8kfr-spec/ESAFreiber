BEGIN;

DROP INDEX IF EXISTS time_entries_one_effective_clock_in_key;
DROP INDEX IF EXISTS time_entries_one_effective_clock_out_key;

CREATE INDEX time_entries_one_effective_clock_in_key
    ON time_entries (company_id, user_id, work_day_id, recorded_at)
    WHERE entry_type = 'clock_in'
      AND invalidated_at IS NULL
      AND (original_entry_id IS NULL OR correction_status = 'approved');

CREATE INDEX time_entries_one_effective_clock_out_key
    ON time_entries (company_id, user_id, work_day_id, recorded_at)
    WHERE entry_type = 'clock_out'
      AND invalidated_at IS NULL
      AND (original_entry_id IS NULL OR correction_status = 'approved');

CREATE OR REPLACE FUNCTION recalculate_work_day(
    target_company_id UUID,
    target_user_id UUID,
    target_work_day_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    calculated_clock_in TIMESTAMPTZ;
    calculated_clock_out TIMESTAMPTZ;
    calculated_gross INTEGER := 0;
    calculated_break INTEGER := 0;
    calculated_work INTEGER := 0;
    calculated_recorded_work INTEGER := 0;
    calculated_explicit_break INTEGER := 0;
    calculated_required_break INTEGER := 0;
    calculated_travel INTEGER := 0;
    target_minutes INTEGER := 0;
    previous_recalculation_setting TEXT;
BEGIN
    WITH effective_entries AS (
        SELECT entry_type, recorded_at
        FROM time_entries
        WHERE company_id = target_company_id
          AND user_id = target_user_id
          AND work_day_id = target_work_day_id
          AND invalidated_at IS NULL
          AND (
              (original_entry_id IS NULL AND correction_status IS NULL)
              OR correction_status = 'approved'
          )
    )
    SELECT
        MIN(recorded_at) FILTER (WHERE entry_type = 'clock_in'),
        MAX(recorded_at) FILTER (WHERE entry_type = 'clock_out')
    INTO calculated_clock_in, calculated_clock_out
    FROM effective_entries;

    IF calculated_clock_in IS NOT NULL
        AND calculated_clock_out IS NOT NULL
        AND calculated_clock_out >= calculated_clock_in THEN
        calculated_gross := FLOOR(
            EXTRACT(EPOCH FROM (calculated_clock_out - calculated_clock_in)) / 60
        )::INTEGER;
    END IF;

    WITH effective_entries AS (
        SELECT id, entry_type, recorded_at, created_at
        FROM time_entries
        WHERE company_id = target_company_id
          AND user_id = target_user_id
          AND work_day_id = target_work_day_id
          AND invalidated_at IS NULL
          AND (
              (original_entry_id IS NULL AND correction_status IS NULL)
              OR correction_status = 'approved'
          )
    ),
    work_segments AS (
        SELECT
            start_entry.recorded_at AS starts_at,
            (
                SELECT MIN(end_entry.recorded_at)
                FROM effective_entries AS end_entry
                WHERE end_entry.recorded_at > start_entry.recorded_at
                  AND end_entry.entry_type = 'clock_out'
                  AND NOT EXISTS (
                      SELECT 1
                      FROM effective_entries AS next_start
                      WHERE next_start.entry_type = 'clock_in'
                        AND next_start.recorded_at > start_entry.recorded_at
                        AND next_start.recorded_at < end_entry.recorded_at
                  )
            ) AS ends_at
        FROM effective_entries AS start_entry
        WHERE start_entry.entry_type = 'clock_in'
    )
    SELECT COALESCE(
        SUM(FLOOR(EXTRACT(EPOCH FROM (ends_at - starts_at)) / 60)),
        0
    )::INTEGER
    INTO calculated_recorded_work
    FROM work_segments
    WHERE ends_at IS NOT NULL
      AND ends_at >= starts_at;

    calculated_explicit_break := GREATEST(calculated_gross - calculated_recorded_work, 0);
    calculated_required_break := CASE
        WHEN calculated_gross >= 360 THEN 60
        WHEN calculated_gross >= 210 THEN 30
        ELSE 0
    END;
    calculated_break := GREATEST(calculated_explicit_break, calculated_required_break);
    calculated_work := GREATEST(calculated_gross - calculated_break, 0);

    WITH effective_entries AS (
        SELECT id, entry_type, recorded_at
        FROM time_entries
        WHERE company_id = target_company_id
          AND user_id = target_user_id
          AND work_day_id = target_work_day_id
          AND invalidated_at IS NULL
          AND (
              (original_entry_id IS NULL AND correction_status IS NULL)
              OR correction_status = 'approved'
          )
    ),
    travel_segments AS (
        SELECT
            start_entry.recorded_at AS starts_at,
            (
                SELECT MIN(end_entry.recorded_at)
                FROM effective_entries AS end_entry
                WHERE end_entry.recorded_at > start_entry.recorded_at
                  AND end_entry.entry_type IN ('site_arrival', 'clock_out')
            ) AS ends_at
        FROM effective_entries AS start_entry
        WHERE start_entry.entry_type IN ('clock_in', 'site_departure')
    )
    SELECT COALESCE(
        SUM(FLOOR(EXTRACT(EPOCH FROM (ends_at - starts_at)) / 60)),
        0
    )::INTEGER
    INTO calculated_travel
    FROM travel_segments
    WHERE ends_at IS NOT NULL
      AND ends_at >= starts_at;

    SELECT target_work_minutes
    INTO target_minutes
    FROM work_days
    WHERE company_id = target_company_id
      AND user_id = target_user_id
      AND id = target_work_day_id;

    previous_recalculation_setting := CURRENT_SETTING('app.recalculating_work_day', TRUE);
    PERFORM set_config('app.recalculating_work_day', 'on', TRUE);

    UPDATE work_days
    SET first_clock_in_at = calculated_clock_in,
        last_clock_out_at = calculated_clock_out,
        gross_minutes = calculated_gross,
        break_minutes = calculated_break,
        work_minutes = calculated_work,
        travel_minutes = LEAST(calculated_travel, calculated_work),
        overtime_minutes = GREATEST(calculated_work - COALESCE(target_minutes, 0), 0),
        calculation_version = 2
    WHERE company_id = target_company_id
      AND user_id = target_user_id
      AND id = target_work_day_id;

    PERFORM set_config(
        'app.recalculating_work_day',
        COALESCE(previous_recalculation_setting, ''),
        TRUE
    );
END;
$$;

COMMENT ON FUNCTION recalculate_work_day(UUID, UUID, UUID)
IS 'Berechnet mehrere Arbeitsblöcke pro Tag; Unterbrechungen zwischen Feierabend und erneutem Start zählen als Pause.';

COMMENT ON INDEX time_entries_one_effective_clock_in_key
IS 'Nicht eindeutiger Suchindex für mehrere wirksame Arbeitsbeginne je Arbeitstag.';

COMMENT ON INDEX time_entries_one_effective_clock_out_key
IS 'Nicht eindeutiger Suchindex für mehrere wirksame Feierabende je Arbeitstag.';

COMMIT;
