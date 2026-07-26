\echo 'Teste Migration 029_create_company_modules.sql ...'

BEGIN;

DO $$
DECLARE
    target_company_id UUID;
    target_user_id UUID;
    target_event_id UUID;
BEGIN
    SELECT id INTO target_company_id
    FROM companies
    WHERE company_number = 'F-000001';

    INSERT INTO users (company_id, personnel_number, first_name, last_name)
    VALUES (target_company_id, 'MODULE-1', 'Maja', 'Module')
    RETURNING id INTO target_user_id;

    INSERT INTO company_modules (
        company_id, module_key, is_enabled, changed_by_user_id
    ) VALUES (
        target_company_id, 'VDE', TRUE, target_user_id
    );

    IF NOT EXISTS (
        SELECT 1
        FROM company_modules
        WHERE company_id = target_company_id
          AND module_key = 'vde'
          AND is_enabled
          AND enabled_at IS NOT NULL
          AND disabled_at IS NULL
          AND row_version = 1
    ) THEN
        RAISE EXCEPTION 'VDE-Modul wurde nicht korrekt aktiviert';
    END IF;

    SELECT id INTO target_event_id
    FROM company_module_events
    WHERE company_id = target_company_id
      AND module_key = 'vde'
      AND module_row_version = 1;

    IF target_event_id IS NULL THEN
        RAISE EXCEPTION 'Aktivierung wurde nicht historisiert';
    END IF;

    UPDATE company_modules
    SET is_enabled = FALSE, changed_by_user_id = target_user_id
    WHERE company_id = target_company_id AND module_key = 'vde';

    IF NOT EXISTS (
        SELECT 1
        FROM company_modules
        WHERE company_id = target_company_id
          AND module_key = 'vde'
          AND NOT is_enabled
          AND enabled_at IS NOT NULL
          AND disabled_at IS NOT NULL
          AND row_version = 2
    ) THEN
        RAISE EXCEPTION 'VDE-Modul wurde nicht nachvollziehbar deaktiviert';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM company_module_events
        WHERE company_id = target_company_id AND module_key = 'vde'
    ) <> 2 THEN
        RAISE EXCEPTION 'Modulhistorie ist unvollständig';
    END IF;

    BEGIN
        INSERT INTO company_modules (
            company_id, module_key, is_enabled, changed_by_user_id
        ) VALUES (
            target_company_id, 'rechnung', TRUE, target_user_id
        );
        RAISE EXCEPTION USING ERRCODE = 'ZXM01', MESSAGE = 'Unbekanntes Modul wurde akzeptiert';
    EXCEPTION
        WHEN check_violation THEN NULL;
        WHEN SQLSTATE 'P0001' THEN NULL;
    END;

    BEGIN
        UPDATE company_module_events
        SET is_enabled = TRUE
        WHERE id = target_event_id;
        RAISE EXCEPTION USING ERRCODE = 'ZXM02', MESSAGE = 'Modulhistorie wurde verändert';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN NULL;
    END;

    BEGIN
        DELETE FROM company_modules
        WHERE company_id = target_company_id AND module_key = 'vde';
        RAISE EXCEPTION USING ERRCODE = 'ZXM03', MESSAGE = 'Modulfreigabe wurde hart gelöscht';
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
    IF (SELECT COUNT(*) FROM company_modules) <> 1 THEN
        RAISE EXCEPTION 'API-Rolle sieht die eigene Modulfreigabe nicht';
    END IF;
    IF (SELECT COUNT(*) FROM company_module_events) <> 2 THEN
        RAISE EXCEPTION 'API-Rolle sieht die eigene Modulhistorie nicht';
    END IF;

    PERFORM set_config('app.current_company_id', gen_random_uuid()::TEXT, TRUE);
    IF EXISTS (SELECT 1 FROM company_modules) OR EXISTS (SELECT 1 FROM company_module_events) THEN
        RAISE EXCEPTION 'API-Rolle sieht Modulfreigaben eines anderen Mandanten';
    END IF;
END;
$$;

RESET ROLE;
ROLLBACK;

\echo 'Migration 029_create_company_modules.sql erfolgreich getestet.'
