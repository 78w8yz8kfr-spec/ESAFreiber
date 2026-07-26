BEGIN;

ALTER TABLE site_assignments
    ADD COLUMN IF NOT EXISTS report_responsibility_source VARCHAR(20);

UPDATE site_assignments
SET report_responsibility_source = 'manual'
WHERE report_responsible
  AND report_responsibility_source IS NULL;

ALTER TABLE site_assignments
    DROP CONSTRAINT IF EXISTS site_assignments_report_responsibility_source_check;
ALTER TABLE site_assignments
    ADD CONSTRAINT site_assignments_report_responsibility_source_check CHECK (
        (NOT report_responsible AND report_responsibility_source IS NULL)
        OR (
            report_responsible
            AND report_responsibility_source IN ('manual', 'automatic')
        )
    );

CREATE OR REPLACE FUNCTION site_assignments_validate_report_responsibility()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.report_responsible AND NEW.report_responsibility_source IS NULL THEN
        NEW.report_responsibility_source := 'manual';
    ELSIF NOT NEW.report_responsible THEN
        NEW.report_responsibility_source := NULL;
    END IF;

    IF TG_OP = 'UPDATE'
        AND (
            NEW.report_responsible IS DISTINCT FROM OLD.report_responsible
            OR NEW.report_responsibility_source IS DISTINCT FROM OLD.report_responsibility_source
        )
        AND NULLIF(BTRIM(NEW.last_change_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Änderungen an der Berichtsverantwortung benötigen eine Begründung.';
    END IF;

    IF TG_OP = 'UPDATE' AND EXISTS (
        SELECT 1 FROM site_reports
        WHERE company_id = OLD.company_id AND site_assignment_id = OLD.id
    ) AND (
        NEW.work_date IS DISTINCT FROM OLD.work_date
        OR NEW.status IS DISTINCT FROM OLD.status
        OR NEW.report_responsible IS DISTINCT FROM OLD.report_responsible
        OR NEW.report_responsibility_source IS DISTINCT FROM OLD.report_responsibility_source
    ) THEN
        RAISE EXCEPTION 'Ein Einsatz mit bereits erfasstem Baustellenbericht ist gesperrt.';
    END IF;

    IF NEW.report_responsible
        AND NEW.status <> 'cancelled'
        AND NEW.report_responsibility_source = 'manual'
        AND NOT EXISTS (
            SELECT 1
            FROM users
            WHERE company_id = NEW.company_id
              AND id = NEW.user_id
              AND status = 'active'
              AND is_foreman
        ) THEN
        RAISE EXCEPTION 'Nur aktive Vorarbeiter dürfen manuell für den Tagesbericht verantwortlich sein.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS site_assignments_validate_report_responsibility_trigger ON site_assignments;
CREATE TRIGGER site_assignments_validate_report_responsibility_trigger
    BEFORE INSERT OR UPDATE OF user_id, work_date, status, report_responsible,
        report_responsibility_source ON site_assignments
    FOR EACH ROW
    EXECUTE FUNCTION site_assignments_validate_report_responsibility();

COMMENT ON COLUMN site_assignments.report_responsibility_source IS
    'manual für eingeplante Vorarbeiter; automatic wenn ein Mitarbeiter allein auf der Baustelle eingesetzt ist.';

COMMIT;
