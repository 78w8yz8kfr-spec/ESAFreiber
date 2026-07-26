-- Abgerechnete Arbeitstage bleiben für neue Buchungen gesperrt.
-- Begründete Korrekturanträge und deren Büroentscheidung müssen dennoch
-- möglich bleiben, damit ein Fehler nie durch Überschreiben verborgen wird.

CREATE OR REPLACE FUNCTION time_entries_before_write()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    original_work_day_id UUID;
    original_entry_type VARCHAR(30);
    work_day_status VARCHAR(20);
    previous_approval_setting TEXT;
BEGIN
    NEW.correction_reason := NULLIF(BTRIM(NEW.correction_reason), '');

    IF TG_OP = 'INSERT' THEN
        NEW.invalidated_at := NULL;
    END IF;

    SELECT status
    INTO work_day_status
    FROM work_days
    WHERE company_id = NEW.company_id
      AND user_id = NEW.user_id
      AND id = NEW.work_day_id;

    IF work_day_status = 'locked' THEN
        IF TG_OP = 'INSERT' AND NEW.original_entry_id IS NULL THEN
            RAISE EXCEPTION 'Für einen gesperrten Arbeitstag sind keine neuen Zeitbuchungen möglich.';
        ELSIF TG_OP = 'UPDATE'
            AND OLD.original_entry_id IS NULL
            AND CURRENT_SETTING('app.approving_time_correction', TRUE) IS DISTINCT FROM 'on' THEN
            RAISE EXCEPTION 'Für einen gesperrten Arbeitstag sind keine neuen Zeitbuchungen möglich.';
        END IF;
    END IF;

    IF TG_OP = 'INSERT' AND NEW.original_entry_id IS NOT NULL THEN
        SELECT work_day_id, entry_type
        INTO original_work_day_id, original_entry_type
        FROM time_entries
        WHERE company_id = NEW.company_id
          AND user_id = NEW.user_id
          AND id = NEW.original_entry_id;

        IF original_work_day_id IS NULL THEN
            RAISE EXCEPTION 'Der zu korrigierende Zeiteintrag wurde nicht gefunden.';
        END IF;

        IF NEW.work_day_id <> original_work_day_id OR NEW.entry_type <> original_entry_type THEN
            RAISE EXCEPTION 'Eine Korrektur muss Arbeitstag und Buchungsart des Originals beibehalten.';
        END IF;

        NEW.correction_status := 'pending';
        NEW.reviewed_by_user_id := NULL;
        NEW.reviewed_at := NULL;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF NEW.company_id <> OLD.company_id
            OR NEW.user_id <> OLD.user_id
            OR NEW.work_day_id <> OLD.work_day_id
            OR NEW.construction_site_id IS DISTINCT FROM OLD.construction_site_id
            OR NEW.entry_type <> OLD.entry_type
            OR NEW.recorded_at <> OLD.recorded_at
            OR NEW.client_entry_id <> OLD.client_entry_id
            OR NEW.client_created_at <> OLD.client_created_at
            OR NEW.source <> OLD.source
            OR NEW.entered_by_user_id IS DISTINCT FROM OLD.entered_by_user_id
            OR NEW.original_entry_id IS DISTINCT FROM OLD.original_entry_id
            OR NEW.correction_reason IS DISTINCT FROM OLD.correction_reason
            OR NEW.created_at <> OLD.created_at THEN
            RAISE EXCEPTION 'Zeitbuchungen sind unveränderlich; bitte eine Korrektur anlegen.';
        END IF;

        IF OLD.original_entry_id IS NULL
            AND NEW.correction_status IS DISTINCT FROM OLD.correction_status THEN
            RAISE EXCEPTION 'Nur Korrektureinträge besitzen einen Prüfstatus.';
        END IF;

        IF NEW.invalidated_at IS DISTINCT FROM OLD.invalidated_at
            AND CURRENT_SETTING('app.approving_time_correction', TRUE) IS DISTINCT FROM 'on' THEN
            RAISE EXCEPTION 'Ein Original darf nur durch eine genehmigte Korrektur entwertet werden.';
        END IF;

        IF OLD.correction_status IN ('approved', 'rejected')
            AND NEW.correction_status IS DISTINCT FROM OLD.correction_status THEN
            RAISE EXCEPTION 'Eine entschiedene Korrektur kann nicht erneut bewertet werden.';
        END IF;

        IF OLD.correction_status = 'pending'
            AND NEW.correction_status IN ('approved', 'rejected') THEN
            IF NEW.reviewed_by_user_id IS NULL THEN
                RAISE EXCEPTION 'Eine Korrekturentscheidung benötigt einen Prüfer.';
            END IF;

            NEW.reviewed_at := COALESCE(NEW.reviewed_at, CURRENT_TIMESTAMP);

            IF NEW.correction_status = 'approved' THEN
                previous_approval_setting := CURRENT_SETTING('app.approving_time_correction', TRUE);
                PERFORM set_config('app.approving_time_correction', 'on', TRUE);

                UPDATE time_entries
                SET invalidated_at = CURRENT_TIMESTAMP
                WHERE company_id = NEW.company_id
                  AND user_id = NEW.user_id
                  AND id = NEW.original_entry_id
                  AND invalidated_at IS NULL;

                PERFORM set_config(
                    'app.approving_time_correction',
                    COALESCE(previous_approval_setting, ''),
                    TRUE
                );
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION time_entries_before_write() IS
    'Schützt unveränderliche Zeitbuchungen; erlaubt begründete Korrekturen auch nach der Abrechnung.';
