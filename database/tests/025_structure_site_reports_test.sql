\echo 'Teste Migration 025_structure_site_reports.sql ...'

BEGIN;

DO $$
DECLARE
    tenant_id UUID;
    author_id UUID;
    customer_id UUID;
    location_id UUID;
    project_id UUID;
    site_id UUID;
    report_id UUID;
BEGIN
    SELECT id INTO tenant_id FROM companies WHERE company_number = 'F-000001';
    SELECT id INTO author_id FROM users WHERE company_id = tenant_id ORDER BY created_at LIMIT 1;

    INSERT INTO customers (company_id, customer_type, company_name)
    VALUES (tenant_id, 'company', 'Strukturbericht Testkunde GmbH')
    RETURNING id INTO customer_id;
    INSERT INTO customer_locations (
        company_id, customer_id, name, street, house_number, postal_code, city
    ) VALUES (
        tenant_id, customer_id, 'Strukturbericht Testort', 'Testweg', '25', '12345', 'Teststadt'
    ) RETURNING id INTO location_id;
    INSERT INTO projects (company_id, customer_id, name)
    VALUES (tenant_id, customer_id, 'Strukturbericht Testprojekt')
    RETURNING id INTO project_id;
    INSERT INTO construction_sites (
        company_id, project_id, customer_location_id, name
    ) VALUES (
        tenant_id, project_id, location_id, 'Strukturbericht Testbaustelle'
    ) RETURNING id INTO site_id;

    INSERT INTO site_reports (
        company_id, construction_site_id, report_number, report_type, work_date,
        source_mode, summary, status, author_user_id, structured_data
    ) VALUES (
        tenant_id, site_id, NULL, 'daily', DATE '2026-08-05',
        'digital', 'Strukturierter Bautagesbericht', 'submitted', author_id,
        jsonb_build_object(
            'workPerformed', 'Leitungswege und Unterverteilung vorbereitet',
            'obstructions', 'Materiallieferung verspätet',
            'openItems', 'Beschriftung abschließen',
            'personnel', jsonb_build_array(jsonb_build_object(
                'userId', author_id,
                'name', 'Struktur Test',
                'minutes', 480
            ))
        )
    ) RETURNING id INTO report_id;

    IF NOT EXISTS (
        SELECT 1
        FROM site_reports
        WHERE id = report_id
          AND structured_data ->> 'workPerformed' = 'Leitungswege und Unterverteilung vorbereitet'
          AND structured_data #>> '{personnel,0,minutes}' = '480'
    ) THEN
        RAISE EXCEPTION 'Strukturierte Berichtsdaten wurden nicht vollständig gespeichert';
    END IF;

    BEGIN
        UPDATE site_reports
        SET structured_data = jsonb_build_object(
            'workPerformed', '',
            'personnel', '[]'::JSONB
        )
        WHERE id = report_id;
        RAISE EXCEPTION USING ERRCODE = 'ZXA01', MESSAGE = 'Leere ausgeführte Leistungen wurden akzeptiert';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        UPDATE site_reports
        SET structured_data = jsonb_build_object(
            'workPerformed', 'Test',
            'personnel', jsonb_build_array(
                jsonb_build_object('userId', author_id, 'name', 'Doppelt', 'minutes', 60),
                jsonb_build_object('userId', author_id, 'name', 'Doppelt', 'minutes', 60)
            )
        )
        WHERE id = report_id;
        RAISE EXCEPTION USING ERRCODE = 'ZXA02', MESSAGE = 'Doppelte Mitarbeiterstunden wurden akzeptiert';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
END;
$$;

ROLLBACK;

\echo 'Migration 025_structure_site_reports.sql erfolgreich getestet.'
