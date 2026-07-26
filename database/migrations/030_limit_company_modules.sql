BEGIN;

UPDATE company_modules
SET is_enabled = FALSE
WHERE module_key IN ('lwl', 'knx')
  AND is_enabled;

CREATE OR REPLACE FUNCTION company_modules_require_supported_key()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF LOWER(BTRIM(NEW.module_key)) NOT IN ('vde', 'dguv') THEN
        RAISE EXCEPTION 'Als Elektro-Spezialmodule sind nur VDE und DGUV vorgesehen.';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS company_modules_supported_keys_trigger ON company_modules;
CREATE TRIGGER company_modules_supported_keys_trigger
    BEFORE INSERT OR UPDATE ON company_modules
    FOR EACH ROW EXECUTE FUNCTION company_modules_require_supported_key();

COMMENT ON TABLE company_modules IS
    'Firmenbezogene Freigabe der optionalen VDE- und DGUV-Module; fehlende Einträge gelten als deaktiviert.';
COMMENT ON TABLE company_module_events IS
    'Unveränderliche Historie jeder Aktivierung und Deaktivierung eines VDE- oder DGUV-Moduls.';

COMMIT;
