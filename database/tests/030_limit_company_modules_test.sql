\echo 'Teste Migration 030_limit_company_modules.sql ...'

BEGIN;

DO $$
DECLARE
    target_company_id UUID;
    target_user_id UUID;
BEGIN
    SELECT id INTO target_company_id
    FROM companies
    WHERE company_number = 'F-000001';

    INSERT INTO users (company_id, personnel_number, first_name, last_name)
    VALUES (target_company_id, 'MODULE-2', 'Dora', 'DGUV')
    RETURNING id INTO target_user_id;

    INSERT INTO company_modules (
        company_id, module_key, is_enabled, changed_by_user_id
    ) VALUES (
        target_company_id, 'dguv', TRUE, target_user_id
    );

    IF NOT EXISTS (
        SELECT 1
        FROM company_modules
        WHERE company_id = target_company_id
          AND module_key = 'dguv'
          AND is_enabled
    ) THEN
        RAISE EXCEPTION 'DGUV-Modul wurde nicht akzeptiert';
    END IF;

    BEGIN
        INSERT INTO company_modules (
            company_id, module_key, is_enabled, changed_by_user_id
        ) VALUES (
            target_company_id, 'lwl', TRUE, target_user_id
        );
        RAISE EXCEPTION USING ERRCODE = 'ZXL01', MESSAGE = 'LWL-Modul wurde akzeptiert';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN NULL;
    END;

    BEGIN
        INSERT INTO company_modules (
            company_id, module_key, is_enabled, changed_by_user_id
        ) VALUES (
            target_company_id, 'knx', TRUE, target_user_id
        );
        RAISE EXCEPTION USING ERRCODE = 'ZXL02', MESSAGE = 'KNX-Modul wurde akzeptiert';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN NULL;
    END;
END;
$$;

ROLLBACK;

\echo 'Migration 030_limit_company_modules.sql erfolgreich getestet.'
