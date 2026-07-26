BEGIN;

CREATE TABLE IF NOT EXISTS site_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL,
    construction_site_id UUID NOT NULL,
    author_user_id UUID NOT NULL,
    client_note_id UUID NOT NULL,
    content TEXT NOT NULL,
    is_important BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    archived_at TIMESTAMPTZ,
    archived_by_user_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    row_version BIGINT NOT NULL DEFAULT 1,
    CONSTRAINT site_notes_company_fkey
        FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE RESTRICT,
    CONSTRAINT site_notes_site_fkey
        FOREIGN KEY (company_id, construction_site_id)
        REFERENCES construction_sites (company_id, id) ON DELETE RESTRICT,
    CONSTRAINT site_notes_author_fkey
        FOREIGN KEY (company_id, author_user_id)
        REFERENCES users (company_id, id) ON DELETE RESTRICT,
    CONSTRAINT site_notes_archiver_fkey
        FOREIGN KEY (company_id, archived_by_user_id)
        REFERENCES users (company_id, id) ON DELETE RESTRICT,
    CONSTRAINT site_notes_company_id_id_key UNIQUE (company_id, id),
    CONSTRAINT site_notes_client_id_key UNIQUE (company_id, author_user_id, client_note_id),
    CONSTRAINT site_notes_content_check CHECK (
        BTRIM(content) <> '' AND CHAR_LENGTH(content) <= 2000
    ),
    CONSTRAINT site_notes_status_check CHECK (status IN ('active', 'archived')),
    CONSTRAINT site_notes_archive_check CHECK (
        (status = 'active' AND archived_at IS NULL AND archived_by_user_id IS NULL)
        OR
        (status = 'archived' AND archived_at IS NOT NULL AND archived_by_user_id IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS site_notes_site_status_idx
    ON site_notes (company_id, construction_site_id, status, is_important DESC, created_at DESC);

CREATE OR REPLACE FUNCTION site_notes_before_write()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.content := BTRIM(NEW.content);
    NEW.status := LOWER(BTRIM(NEW.status));

    IF TG_OP = 'INSERT' THEN
        NEW.status := 'active';
        NEW.archived_at := NULL;
        NEW.archived_by_user_id := NULL;
    ELSE
        IF NEW.company_id <> OLD.company_id
            OR NEW.construction_site_id <> OLD.construction_site_id
            OR NEW.author_user_id <> OLD.author_user_id
            OR NEW.client_note_id <> OLD.client_note_id
            OR NEW.content <> OLD.content
            OR NEW.is_important <> OLD.is_important
            OR NEW.created_at <> OLD.created_at THEN
            RAISE EXCEPTION 'Baustellennotizen sind inhaltlich unveränderlich.';
        END IF;

        IF NEW.status = 'archived' AND OLD.status = 'active' THEN
            IF NEW.archived_by_user_id IS NULL THEN
                RAISE EXCEPTION 'Das Archivieren benötigt einen verantwortlichen Benutzer.';
            END IF;
            NEW.archived_at := COALESCE(NEW.archived_at, CURRENT_TIMESTAMP);
        ELSIF NEW.status = 'active' AND OLD.status = 'archived' THEN
            NEW.archived_at := NULL;
            NEW.archived_by_user_id := NULL;
        END IF;

        NEW.updated_at := CURRENT_TIMESTAMP;
        NEW.row_version := OLD.row_version + 1;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS site_notes_before_write_trigger ON site_notes;
CREATE TRIGGER site_notes_before_write_trigger
    BEFORE INSERT OR UPDATE ON site_notes
    FOR EACH ROW EXECUTE FUNCTION site_notes_before_write();

CREATE OR REPLACE FUNCTION site_notes_prevent_hard_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF CURRENT_SETTING('app.allow_hard_delete', TRUE) = 'on' THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'Baustellennotizen dürfen nicht hart gelöscht werden.';
END;
$$;

DROP TRIGGER IF EXISTS site_notes_prevent_hard_delete_trigger ON site_notes;
CREATE TRIGGER site_notes_prevent_hard_delete_trigger
    BEFORE DELETE ON site_notes
    FOR EACH ROW EXECUTE FUNCTION site_notes_prevent_hard_delete();

ALTER TABLE site_notes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS site_notes_tenant_isolation ON site_notes;
CREATE POLICY site_notes_tenant_isolation ON site_notes
    USING (company_id = NULLIF(CURRENT_SETTING('app.current_company_id', TRUE), '')::UUID)
    WITH CHECK (company_id = NULLIF(CURRENT_SETTING('app.current_company_id', TRUE), '')::UUID);

GRANT SELECT, INSERT, UPDATE ON site_notes TO schaefchen_api;
ALTER TABLE site_notes NO FORCE ROW LEVEL SECURITY;

COMMENT ON TABLE site_notes IS
    'Eigene thematische Baustellennotizen ohne Aktivitätschronik; Inhalte bleiben unverändert erhalten.';
COMMENT ON COLUMN site_notes.client_note_id IS
    'Vom Client erzeugte UUID für eine idempotente mobile Speicherung.';

COMMIT;
