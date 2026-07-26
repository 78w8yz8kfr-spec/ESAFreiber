BEGIN;

ALTER TABLE site_reports
    ADD COLUMN IF NOT EXISTS structured_data JSONB NOT NULL DEFAULT '{}'::JSONB;

-- Der technische Backfill muss auch freigegebene Altberichte ergänzen können.
-- Der bisherige Trigger sperrt bei diesen Datensätzen absichtlich jedes UPDATE;
-- deshalb wird er nur innerhalb dieser Transaktion entfernt und unten mit der
-- bisherigen Fachlogik plus Strukturstandard wieder angelegt.
DROP TRIGGER IF EXISTS site_reports_before_write_trigger ON site_reports;

UPDATE site_reports
SET structured_data = jsonb_build_object(
    'workPerformed', COALESCE(NULLIF(BTRIM(details), ''), summary),
    'obstructions', NULL,
    'openItems', NULL,
    'personnel', '[]'::JSONB
)
WHERE structured_data = '{}'::JSONB
   OR NOT structured_data ? 'workPerformed'
   OR NOT structured_data ? 'personnel';

CREATE OR REPLACE FUNCTION site_report_structure_valid(value JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    item JSONB;
    item_user_id UUID;
    seen_user_ids UUID[] := ARRAY[]::UUID[];
    item_minutes INTEGER;
BEGIN
    IF value IS NULL OR jsonb_typeof(value) <> 'object' THEN
        RETURN FALSE;
    END IF;
    IF jsonb_typeof(value -> 'workPerformed') <> 'string'
        OR CHAR_LENGTH(BTRIM(value ->> 'workPerformed')) NOT BETWEEN 1 AND 5000 THEN
        RETURN FALSE;
    END IF;
    IF value ? 'obstructions'
        AND value -> 'obstructions' <> 'null'::JSONB
        AND (
            jsonb_typeof(value -> 'obstructions') <> 'string'
            OR CHAR_LENGTH(BTRIM(value ->> 'obstructions')) NOT BETWEEN 1 AND 3000
        ) THEN
        RETURN FALSE;
    END IF;
    IF value ? 'openItems'
        AND value -> 'openItems' <> 'null'::JSONB
        AND (
            jsonb_typeof(value -> 'openItems') <> 'string'
            OR CHAR_LENGTH(BTRIM(value ->> 'openItems')) NOT BETWEEN 1 AND 3000
        ) THEN
        RETURN FALSE;
    END IF;
    IF jsonb_typeof(value -> 'personnel') <> 'array'
        OR jsonb_array_length(value -> 'personnel') > 100 THEN
        RETURN FALSE;
    END IF;

    FOR item IN
        SELECT personnel_item
        FROM jsonb_array_elements(value -> 'personnel') AS personnel(personnel_item)
    LOOP
        IF jsonb_typeof(item) <> 'object'
            OR jsonb_typeof(item -> 'userId') <> 'string'
            OR jsonb_typeof(item -> 'name') <> 'string'
            OR jsonb_typeof(item -> 'minutes') <> 'number'
            OR CHAR_LENGTH(BTRIM(item ->> 'name')) NOT BETWEEN 1 AND 200
            OR (item ->> 'minutes') !~ '^[0-9]+$' THEN
            RETURN FALSE;
        END IF;
        item_user_id := (item ->> 'userId')::UUID;
        item_minutes := (item ->> 'minutes')::INTEGER;
        IF item_minutes NOT BETWEEN 1 AND 1440 OR item_user_id = ANY(seen_user_ids) THEN
            RETURN FALSE;
        END IF;
        seen_user_ids := array_append(seen_user_ids, item_user_id);
    END LOOP;

    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    RETURN FALSE;
END;
$$;

ALTER TABLE site_reports
    DROP CONSTRAINT IF EXISTS site_reports_structured_data_check;
ALTER TABLE site_reports
    ADD CONSTRAINT site_reports_structured_data_check
    CHECK (site_report_structure_valid(structured_data));

CREATE OR REPLACE FUNCTION site_reports_before_write()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NULLIF(BTRIM(NEW.report_number), '') IS NULL THEN
        NEW.report_number := next_site_report_number(NEW.company_id, EXTRACT(YEAR FROM NEW.work_date)::INTEGER);
    END IF;
    NEW.report_number := UPPER(BTRIM(NEW.report_number));
    NEW.report_type := LOWER(BTRIM(NEW.report_type));
    NEW.source_mode := LOWER(BTRIM(NEW.source_mode));
    NEW.summary := BTRIM(NEW.summary);
    NEW.details := NULLIF(BTRIM(NEW.details), '');
    NEW.status := LOWER(BTRIM(NEW.status));
    NEW.employee_signature_name := NULLIF(BTRIM(NEW.employee_signature_name), '');
    NEW.customer_signature_name := NULLIF(BTRIM(NEW.customer_signature_name), '');

    IF jsonb_typeof(NEW.structured_data) = 'object' THEN
        IF NOT NEW.structured_data ? 'workPerformed' THEN
            NEW.structured_data := jsonb_set(
                NEW.structured_data,
                '{workPerformed}',
                to_jsonb(COALESCE(NEW.details, NEW.summary)),
                TRUE
            );
        END IF;
        IF NOT NEW.structured_data ? 'personnel' THEN
            NEW.structured_data := jsonb_set(NEW.structured_data, '{personnel}', '[]'::JSONB, TRUE);
        END IF;
        IF NOT NEW.structured_data ? 'obstructions' THEN
            NEW.structured_data := jsonb_set(NEW.structured_data, '{obstructions}', 'null'::JSONB, TRUE);
        END IF;
        IF NOT NEW.structured_data ? 'openItems' THEN
            NEW.structured_data := jsonb_set(NEW.structured_data, '{openItems}', 'null'::JSONB, TRUE);
        END IF;
    END IF;

    IF NEW.status IN ('submitted', 'approved') THEN
        NEW.submitted_at := COALESCE(NEW.submitted_at, CURRENT_TIMESTAMP);
    ELSE
        NEW.submitted_at := NULL;
    END IF;
    IF NEW.status = 'approved' THEN
        NEW.approved_at := COALESCE(NEW.approved_at, CURRENT_TIMESTAMP);
        NEW.employee_signed_at := COALESCE(NEW.employee_signed_at, NEW.approved_at);
        NEW.customer_signed_at := COALESCE(NEW.customer_signed_at, NEW.approved_at);
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF NEW.company_id <> OLD.company_id OR NEW.construction_site_id <> OLD.construction_site_id
           OR NEW.report_number <> OLD.report_number OR NEW.author_user_id <> OLD.author_user_id
           OR NEW.source_document_id IS DISTINCT FROM OLD.source_document_id THEN
            RAISE EXCEPTION 'Mandant, Baustelle, Nummer, Autor und Originaldokument eines Berichts sind unveränderlich.';
        END IF;
        IF OLD.status = 'approved' THEN
            RAISE EXCEPTION 'Ein freigegebener Bericht ist unveränderlich.';
        END IF;
        IF NEW.status = 'approved' AND OLD.status <> 'submitted' THEN
            RAISE EXCEPTION 'Nur ein eingereichter Bericht darf freigegeben werden.';
        END IF;
        NEW.updated_at := CURRENT_TIMESTAMP;
        NEW.row_version := OLD.row_version + 1;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER site_reports_before_write_trigger
    BEFORE INSERT OR UPDATE ON site_reports
    FOR EACH ROW EXECUTE FUNCTION site_reports_before_write();

COMMENT ON COLUMN site_reports.structured_data IS
    'Strukturierte Leistungen, Behinderungen, offene Punkte sowie serverseitig aufgelöste Mitarbeiterstunden.';

COMMIT;
