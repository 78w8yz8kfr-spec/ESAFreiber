BEGIN;

CREATE TABLE IF NOT EXISTS company_modules (
    company_id UUID NOT NULL,
    module_key VARCHAR(30) NOT NULL,
    is_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    changed_by_user_id UUID NOT NULL,
    enabled_at TIMESTAMPTZ,
    disabled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version BIGINT NOT NULL DEFAULT 1,
    PRIMARY KEY (company_id, module_key),
    CONSTRAINT company_modules_company_fkey
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE RESTRICT,
    CONSTRAINT company_modules_changer_fkey
        FOREIGN KEY (company_id, changed_by_user_id)
        REFERENCES users (company_id, id) ON DELETE RESTRICT,
    CONSTRAINT company_modules_key_check
        CHECK (module_key IN ('vde', 'dguv', 'lwl', 'knx')),
    CONSTRAINT company_modules_state_time_check CHECK (
        (is_enabled AND enabled_at IS NOT NULL AND disabled_at IS NULL)
        OR
        (NOT is_enabled AND disabled_at IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS company_module_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL,
    module_key VARCHAR(30) NOT NULL,
    is_enabled BOOLEAN NOT NULL,
    changed_by_user_id UUID NOT NULL,
    module_row_version BIGINT NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT company_module_events_module_fkey
        FOREIGN KEY (company_id, module_key)
        REFERENCES company_modules (company_id, module_key) ON DELETE RESTRICT,
    CONSTRAINT company_module_events_changer_fkey
        FOREIGN KEY (company_id, changed_by_user_id)
        REFERENCES users (company_id, id) ON DELETE RESTRICT,
    CONSTRAINT company_module_events_company_id_id_key UNIQUE (company_id, id),
    CONSTRAINT company_module_events_key_check
        CHECK (module_key IN ('vde', 'dguv', 'lwl', 'knx')),
    CONSTRAINT company_module_events_version_check CHECK (module_row_version >= 1)
);

CREATE INDEX IF NOT EXISTS company_module_events_history_idx
    ON company_module_events (company_id, module_key, module_row_version DESC);

CREATE OR REPLACE FUNCTION company_modules_before_write()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.module_key := LOWER(BTRIM(NEW.module_key));

    IF TG_OP = 'INSERT' THEN
        NEW.created_at := COALESCE(NEW.created_at, CURRENT_TIMESTAMP);
        NEW.updated_at := NEW.created_at;
        NEW.row_version := 1;
    ELSE
        IF NEW.company_id <> OLD.company_id
            OR NEW.module_key <> OLD.module_key
            OR NEW.created_at <> OLD.created_at THEN
            RAISE EXCEPTION 'Firma, Modulschlüssel und Erstellungszeit einer Modulfreigabe sind unveränderlich.';
        END IF;
        IF NEW.is_enabled = OLD.is_enabled THEN
            RAISE EXCEPTION 'Der Modulstatus wurde nicht verändert.';
        END IF;
        NEW.updated_at := CURRENT_TIMESTAMP;
        NEW.row_version := OLD.row_version + 1;
    END IF;

    IF NEW.is_enabled THEN
        NEW.enabled_at := NEW.updated_at;
        NEW.disabled_at := NULL;
    ELSE
        NEW.disabled_at := NEW.updated_at;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS company_modules_before_write_trigger ON company_modules;
CREATE TRIGGER company_modules_before_write_trigger
    BEFORE INSERT OR UPDATE ON company_modules
    FOR EACH ROW EXECUTE FUNCTION company_modules_before_write();

CREATE OR REPLACE FUNCTION company_modules_record_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO company_module_events (
        company_id, module_key, is_enabled, changed_by_user_id,
        module_row_version, changed_at
    ) VALUES (
        NEW.company_id, NEW.module_key, NEW.is_enabled, NEW.changed_by_user_id,
        NEW.row_version, NEW.updated_at
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS company_modules_record_event_trigger ON company_modules;
CREATE TRIGGER company_modules_record_event_trigger
    AFTER INSERT OR UPDATE ON company_modules
    FOR EACH ROW EXECUTE FUNCTION company_modules_record_event();

CREATE OR REPLACE FUNCTION company_modules_prevent_hard_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF CURRENT_SETTING('app.allow_hard_delete', TRUE) = 'on' THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'Modulfreigaben dürfen nicht hart gelöscht werden.';
END;
$$;

DROP TRIGGER IF EXISTS company_modules_prevent_hard_delete_trigger ON company_modules;
CREATE TRIGGER company_modules_prevent_hard_delete_trigger
    BEFORE DELETE ON company_modules
    FOR EACH ROW EXECUTE FUNCTION company_modules_prevent_hard_delete();

CREATE OR REPLACE FUNCTION company_module_events_prevent_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' AND CURRENT_SETTING('app.allow_hard_delete', TRUE) = 'on' THEN
        RETURN OLD;
    END IF;
    RAISE EXCEPTION 'Die Modulhistorie ist unveränderlich.';
END;
$$;

DROP TRIGGER IF EXISTS company_module_events_prevent_change_trigger ON company_module_events;
CREATE TRIGGER company_module_events_prevent_change_trigger
    BEFORE UPDATE OR DELETE ON company_module_events
    FOR EACH ROW EXECUTE FUNCTION company_module_events_prevent_change();

ALTER TABLE company_modules ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS company_modules_tenant_isolation ON company_modules;
CREATE POLICY company_modules_tenant_isolation ON company_modules
    USING (company_id = NULLIF(CURRENT_SETTING('app.current_company_id', TRUE), '')::UUID)
    WITH CHECK (company_id = NULLIF(CURRENT_SETTING('app.current_company_id', TRUE), '')::UUID);

ALTER TABLE company_module_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS company_module_events_tenant_isolation ON company_module_events;
CREATE POLICY company_module_events_tenant_isolation ON company_module_events
    USING (company_id = NULLIF(CURRENT_SETTING('app.current_company_id', TRUE), '')::UUID)
    WITH CHECK (company_id = NULLIF(CURRENT_SETTING('app.current_company_id', TRUE), '')::UUID);

GRANT SELECT, INSERT, UPDATE ON company_modules TO schaefchen_api;
GRANT SELECT, INSERT ON company_module_events TO schaefchen_api;
ALTER TABLE company_modules NO FORCE ROW LEVEL SECURITY;
ALTER TABLE company_module_events NO FORCE ROW LEVEL SECURITY;

COMMENT ON TABLE company_modules IS
    'Firmenbezogene Freigabe der optionalen Elektro-Spezialmodule; fehlende Einträge gelten als deaktiviert.';
COMMENT ON TABLE company_module_events IS
    'Unveränderliche Historie jeder Aktivierung und Deaktivierung eines Spezialmoduls.';

COMMIT;
