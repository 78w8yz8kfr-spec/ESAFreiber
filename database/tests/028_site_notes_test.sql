\echo 'Teste Migration 028_create_site_notes.sql ...'

BEGIN;

DO $$
DECLARE
    target_company_id UUID;
    target_customer_id UUID;
    target_location_id UUID;
    target_project_id UUID;
    target_site_id UUID;
    target_user_id UUID;
    target_note_id UUID;
BEGIN
    SELECT id INTO target_company_id
    FROM companies
    WHERE company_number = 'F-000001';

    INSERT INTO customers (company_id, customer_type, company_name)
    VALUES (target_company_id, 'company', 'Notizentest Kunde GmbH')
    RETURNING id INTO target_customer_id;

    INSERT INTO customer_locations (
        company_id, customer_id, name, street, house_number, postal_code, city
    ) VALUES (
        target_company_id, target_customer_id, 'Notizentest', 'Hinweisweg', '28', '12345', 'Teststadt'
    ) RETURNING id INTO target_location_id;

    INSERT INTO projects (company_id, customer_id, name)
    VALUES (target_company_id, target_customer_id, 'Notizentest Projekt')
    RETURNING id INTO target_project_id;

    INSERT INTO construction_sites (
        company_id, project_id, customer_location_id, name
    ) VALUES (
        target_company_id, target_project_id, target_location_id, 'Notizentest Baustelle'
    ) RETURNING id INTO target_site_id;

    INSERT INTO users (company_id, personnel_number, first_name, last_name)
    VALUES (target_company_id, 'NOTE-1', 'Nora', 'Notiz')
    RETURNING id INTO target_user_id;

    INSERT INTO site_notes (
        company_id, construction_site_id, author_user_id, client_note_id,
        content, is_important
    ) VALUES (
        target_company_id, target_site_id, target_user_id, gen_random_uuid(),
        '  Hauptverteilung vor Wiedereinschalten prüfen.  ', TRUE
    ) RETURNING id INTO target_note_id;

    IF NOT EXISTS (
        SELECT 1
        FROM site_notes AS note
        WHERE note.id = target_note_id
          AND note.content = 'Hauptverteilung vor Wiedereinschalten prüfen.'
          AND note.is_important
          AND note.status = 'active'
          AND note.row_version = 1
    ) THEN
        RAISE EXCEPTION 'Baustellennotiz wurde nicht korrekt gespeichert';
    END IF;

    BEGIN
        UPDATE site_notes
        SET content = 'Manipulierter Hinweis'
        WHERE id = target_note_id;
        RAISE EXCEPTION USING ERRCODE = 'ZXN01', MESSAGE = 'Notizinhalt wurde verändert';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN NULL;
    END;

    UPDATE site_notes
    SET status = 'archived', archived_by_user_id = target_user_id
    WHERE id = target_note_id;

    IF NOT EXISTS (
        SELECT 1
        FROM site_notes
        WHERE id = target_note_id
          AND status = 'archived'
          AND archived_at IS NOT NULL
          AND row_version = 2
    ) THEN
        RAISE EXCEPTION 'Baustellennotiz wurde nicht nachvollziehbar archiviert';
    END IF;

    BEGIN
        DELETE FROM site_notes WHERE id = target_note_id;
        RAISE EXCEPTION USING ERRCODE = 'ZXN02', MESSAGE = 'Hartes Löschen wurde akzeptiert';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN NULL;
    END;
END;
$$;

SELECT id AS tenant_id
FROM companies
WHERE company_number = 'F-000001'
\gset

SET LOCAL ROLE schaefchen_api;
SELECT set_config('app.current_company_id', :'tenant_id', TRUE);

DO $$
BEGIN
    IF (SELECT COUNT(*) FROM site_notes) <> 1 THEN
        RAISE EXCEPTION 'API-Rolle sieht die eigene Baustellennotiz nicht';
    END IF;

    PERFORM set_config('app.current_company_id', gen_random_uuid()::TEXT, TRUE);
    IF EXISTS (SELECT 1 FROM site_notes) THEN
        RAISE EXCEPTION 'API-Rolle sieht Baustellennotizen eines anderen Mandanten';
    END IF;
END;
$$;

RESET ROLE;
ROLLBACK;

\echo 'Migration 028_create_site_notes.sql erfolgreich getestet.'
