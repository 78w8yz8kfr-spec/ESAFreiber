\echo 'Teste Migration 026_automatic_site_foreman.sql ...'

BEGIN;

DO $$
DECLARE
    tenant_id UUID;
    installer_id UUID;
    customer_id UUID;
    location_id UUID;
    project_id UUID;
    site_id UUID;
    assignment_id UUID;
BEGIN
    SELECT id INTO tenant_id FROM companies WHERE company_number = 'F-000001';

    INSERT INTO users (company_id, personnel_number, first_name, last_name)
    VALUES (tenant_id, 'AUTO-FOREMAN', 'Alleiniger', 'Monteur')
    RETURNING id INTO installer_id;

    INSERT INTO customers (company_id, customer_type, company_name)
    VALUES (tenant_id, 'company', 'Automatischer Vorarbeiter Testkunde GmbH')
    RETURNING id INTO customer_id;
    INSERT INTO customer_locations (
        company_id, customer_id, name, street, house_number, postal_code, city
    ) VALUES (
        tenant_id, customer_id, 'Automatischer Vorarbeiter Testort', 'Testweg', '26', '12345', 'Teststadt'
    ) RETURNING id INTO location_id;
    INSERT INTO projects (company_id, customer_id, name)
    VALUES (tenant_id, customer_id, 'Automatischer Vorarbeiter Testprojekt')
    RETURNING id INTO project_id;
    INSERT INTO construction_sites (
        company_id, project_id, customer_location_id, name
    ) VALUES (
        tenant_id, project_id, location_id, 'Automatischer Vorarbeiter Testbaustelle'
    ) RETURNING id INTO site_id;

    INSERT INTO site_assignments (
        company_id, user_id, construction_site_id, work_date, sequence_number,
        status, report_responsible, report_responsibility_source
    ) VALUES (
        tenant_id, installer_id, site_id, DATE '2026-08-06', 1,
        'released', TRUE, 'automatic'
    ) RETURNING id INTO assignment_id;

    IF NOT EXISTS (
        SELECT 1 FROM site_assignments
        WHERE id = assignment_id
          AND report_responsible
          AND report_responsibility_source = 'automatic'
    ) THEN
        RAISE EXCEPTION 'Alleiniger Monteur wurde nicht als automatischer Vorarbeiter gespeichert';
    END IF;

    BEGIN
        INSERT INTO site_assignments (
            company_id, user_id, construction_site_id, work_date, sequence_number,
            status, report_responsible, report_responsibility_source
        ) VALUES (
            tenant_id, installer_id, site_id, DATE '2026-08-07', 1,
            'released', TRUE, 'manual'
        );
        RAISE EXCEPTION USING ERRCODE = 'ZXA01', MESSAGE = 'Monteur wurde als manueller Vorarbeiter akzeptiert';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN NULL;
    END;
END;
$$;

ROLLBACK;

\echo 'Migration 026_automatic_site_foreman.sql erfolgreich getestet.'
