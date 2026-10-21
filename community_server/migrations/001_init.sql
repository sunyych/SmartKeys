CREATE TABLE IF NOT EXISTS batches (
    batch_id CHAR(32) PRIMARY KEY CHECK (batch_id ~ '^[0-9a-f]{32}$'),
    token_hash BYTEA NOT NULL CHECK (octet_length(token_hash) = 32),
    payload_hash BYTEA NOT NULL CHECK (octet_length(payload_hash) = 32),
    received_at BIGINT NOT NULL,
    received_day BIGINT NOT NULL,
    tag TEXT,
    withdrawn BOOLEAN NOT NULL DEFAULT FALSE
);

ALTER TABLE batches ADD COLUMN IF NOT EXISTS tag TEXT;
DO $$ BEGIN
    ALTER TABLE batches ADD CONSTRAINT batches_tag_allowlist CHECK (tag IS NULL OR tag IN ('software_engineering','design','video_editing','office','other'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS batch_items (
    batch_id CHAR(32) NOT NULL REFERENCES batches(batch_id),
    shortcut_id TEXT NOT NULL CHECK (shortcut_id IN ('copy','paste','cut','undo','redo','select_all','save','find','new','open','print','new_tab','close_tab','bold','italic')),
    count BIGINT NOT NULL CHECK (count BETWEEN 1 AND 100000),
    PRIMARY KEY (batch_id, shortcut_id)
);

CREATE INDEX IF NOT EXISTS batches_active_received ON batches(received_at, batch_id) WHERE withdrawn = FALSE;
CREATE INDEX IF NOT EXISTS batch_items_shortcut_batch ON batch_items(shortcut_id, batch_id);

CREATE TABLE IF NOT EXISTS shortcut_totals (
    shortcut_id TEXT PRIMARY KEY CHECK (shortcut_id IN ('copy','paste','cut','undo','redo','select_all','save','find','new','open','print','new_tab','close_tab','bold','italic')),
    count BIGINT NOT NULL DEFAULT 0 CHECK (count >= 0),
    contributions BIGINT NOT NULL DEFAULT 0 CHECK (contributions >= 0)
);

INSERT INTO shortcut_totals(shortcut_id) VALUES
    ('copy'),('paste'),('cut'),('undo'),('redo'),('select_all'),('save'),('find'),('new'),('open'),('print'),('new_tab'),('close_tab'),('bold'),('italic')
ON CONFLICT (shortcut_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS shortcut_daily_totals (
    received_day BIGINT NOT NULL,
    shortcut_id TEXT NOT NULL CHECK (shortcut_id IN ('copy','paste','cut','undo','redo','select_all','save','find','new','open','print','new_tab','close_tab','bold','italic')),
    count BIGINT NOT NULL CHECK (count >= 0),
    contributions BIGINT NOT NULL CHECK (contributions >= 0),
    PRIMARY KEY(received_day, shortcut_id)
);

CREATE INDEX IF NOT EXISTS shortcut_daily_category_day ON shortcut_daily_totals(shortcut_id, received_day);

CREATE TABLE IF NOT EXISTS shortcut_tag_totals (
    tag TEXT NOT NULL CHECK (tag IN ('software_engineering','design','video_editing','office','other')),
    shortcut_id TEXT NOT NULL CHECK (shortcut_id IN ('copy','paste','cut','undo','redo','select_all','save','find','new','open','print','new_tab','close_tab','bold','italic')),
    count BIGINT NOT NULL DEFAULT 0 CHECK (count >= 0),
    contributions BIGINT NOT NULL DEFAULT 0 CHECK (contributions >= 0),
    PRIMARY KEY(tag,shortcut_id)
);

CREATE TABLE IF NOT EXISTS shortcut_tag_daily_totals (
    tag TEXT NOT NULL CHECK (tag IN ('software_engineering','design','video_editing','office','other')),
    received_day BIGINT NOT NULL,
    shortcut_id TEXT NOT NULL CHECK (shortcut_id IN ('copy','paste','cut','undo','redo','select_all','save','find','new','open','print','new_tab','close_tab','bold','italic')),
    count BIGINT NOT NULL CHECK (count >= 0),
    contributions BIGINT NOT NULL CHECK (contributions >= 0),
    PRIMARY KEY(tag,received_day,shortcut_id)
);

CREATE INDEX IF NOT EXISTS shortcut_tag_daily_category_day ON shortcut_tag_daily_totals(tag,shortcut_id,received_day);

CREATE TABLE IF NOT EXISTS account_backups (
    google_sub TEXT PRIMARY KEY CHECK (length(google_sub) BETWEEN 1 AND 255),
    updated_at BIGINT NOT NULL,
    backup JSONB NOT NULL
);

-- Keep each HTTP submission to one PostgreSQL round trip. Inputs are validated
-- and canonicalized by Rust before this function updates these derived totals.
CREATE OR REPLACE FUNCTION community_hash_equal(p_left BYTEA,p_right BYTEA)
RETURNS BOOLEAN LANGUAGE plpgsql IMMUTABLE STRICT AS $$
DECLARE
    v_diff INTEGER := 0;
    v_index INTEGER;
BEGIN
    IF length(p_left)<>length(p_right) THEN RETURN FALSE; END IF;
    FOR v_index IN 0..length(p_left)-1 LOOP
        v_diff := v_diff | (get_byte(p_left,v_index) # get_byte(p_right,v_index));
    END LOOP;
    RETURN v_diff=0;
END;
$$;

CREATE OR REPLACE FUNCTION submit_community_batch(
    p_batch_id CHAR(32), p_token_hash BYTEA, p_payload_hash BYTEA,
    p_received_at BIGINT, p_received_day BIGINT, p_tag TEXT, p_items JSONB
) RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
    v_rows BIGINT;
    v_old_payload BYTEA;
    v_old_token BYTEA;
    v_withdrawn BOOLEAN;
    v_item RECORD;
BEGIN
    INSERT INTO batches(batch_id,token_hash,payload_hash,received_at,received_day,tag,withdrawn)
    VALUES(p_batch_id,p_token_hash,p_payload_hash,p_received_at,p_received_day,p_tag,FALSE)
    ON CONFLICT(batch_id) DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 1 THEN
        FOR v_item IN SELECT key AS shortcut_id,value::BIGINT AS item_count FROM jsonb_each_text(p_items) ORDER BY key LOOP
            INSERT INTO batch_items(batch_id,shortcut_id,count) VALUES(p_batch_id,v_item.shortcut_id,v_item.item_count);
            UPDATE shortcut_totals SET count=count+v_item.item_count,contributions=contributions+1 WHERE shortcut_id=v_item.shortcut_id;
            GET DIAGNOSTICS v_rows = ROW_COUNT;
            IF v_rows<>1 THEN RAISE EXCEPTION 'global aggregate missing'; END IF;
            INSERT INTO shortcut_daily_totals(received_day,shortcut_id,count,contributions)
            VALUES(p_received_day,v_item.shortcut_id,v_item.item_count,1)
            ON CONFLICT(received_day,shortcut_id) DO UPDATE SET count=shortcut_daily_totals.count+EXCLUDED.count,contributions=shortcut_daily_totals.contributions+1;
            IF p_tag IS NOT NULL THEN
                INSERT INTO shortcut_tag_totals(tag,shortcut_id,count,contributions) VALUES(p_tag,v_item.shortcut_id,v_item.item_count,1)
                ON CONFLICT(tag,shortcut_id) DO UPDATE SET count=shortcut_tag_totals.count+EXCLUDED.count,contributions=shortcut_tag_totals.contributions+1;
                INSERT INTO shortcut_tag_daily_totals(tag,received_day,shortcut_id,count,contributions)
                VALUES(p_tag,p_received_day,v_item.shortcut_id,v_item.item_count,1)
                ON CONFLICT(tag,received_day,shortcut_id) DO UPDATE SET count=shortcut_tag_daily_totals.count+EXCLUDED.count,contributions=shortcut_tag_daily_totals.contributions+1;
            END IF;
        END LOOP;
        RETURN 'created';
    END IF;
    SELECT payload_hash,token_hash,withdrawn INTO v_old_payload,v_old_token,v_withdrawn
    FROM batches WHERE batch_id=p_batch_id FOR UPDATE;
    IF v_withdrawn THEN RETURN 'withdrawn'; END IF;
    IF community_hash_equal(v_old_payload,p_payload_hash) AND community_hash_equal(v_old_token,p_token_hash) THEN RETURN 'duplicate'; END IF;
    RETURN 'conflict';
END;
$$;

CREATE OR REPLACE FUNCTION withdraw_community_batch(p_batch_id CHAR(32),p_token_hash BYTEA)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
    v_expected_token BYTEA;
    v_withdrawn BOOLEAN;
    v_day BIGINT;
    v_tag TEXT;
    v_item RECORD;
    v_rows BIGINT;
BEGIN
    SELECT token_hash,withdrawn,received_day,tag INTO v_expected_token,v_withdrawn,v_day,v_tag
    FROM batches WHERE batch_id=p_batch_id FOR UPDATE;
    IF NOT FOUND THEN RETURN 'not_found'; END IF;
    IF NOT community_hash_equal(v_expected_token,p_token_hash) THEN RETURN 'forbidden'; END IF;
    IF v_withdrawn THEN RETURN 'already_withdrawn'; END IF;
    FOR v_item IN SELECT shortcut_id,count AS item_count FROM batch_items WHERE batch_id=p_batch_id ORDER BY shortcut_id FOR UPDATE LOOP
        UPDATE shortcut_totals SET count=count-v_item.item_count,contributions=contributions-1
        WHERE shortcut_id=v_item.shortcut_id AND count>=v_item.item_count AND contributions>0;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows<>1 THEN RAISE EXCEPTION 'aggregate update failed'; END IF;
        UPDATE shortcut_daily_totals SET count=count-v_item.item_count,contributions=contributions-1
        WHERE received_day=v_day AND shortcut_id=v_item.shortcut_id AND count>=v_item.item_count AND contributions>0;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows<>1 THEN RAISE EXCEPTION 'daily aggregate update failed'; END IF;
        IF v_tag IS NOT NULL THEN
            UPDATE shortcut_tag_totals SET count=count-v_item.item_count,contributions=contributions-1
            WHERE tag=v_tag AND shortcut_id=v_item.shortcut_id AND count>=v_item.item_count AND contributions>0;
            GET DIAGNOSTICS v_rows = ROW_COUNT;
            IF v_rows<>1 THEN RAISE EXCEPTION 'tag aggregate update failed'; END IF;
            UPDATE shortcut_tag_daily_totals SET count=count-v_item.item_count,contributions=contributions-1
            WHERE tag=v_tag AND received_day=v_day AND shortcut_id=v_item.shortcut_id AND count>=v_item.item_count AND contributions>0;
            GET DIAGNOSTICS v_rows = ROW_COUNT;
            IF v_rows<>1 THEN RAISE EXCEPTION 'tag daily aggregate update failed'; END IF;
        END IF;
    END LOOP;
    DELETE FROM batch_items WHERE batch_id=p_batch_id;
    UPDATE batches SET withdrawn=TRUE WHERE batch_id=p_batch_id;
    RETURN 'withdrawn';
END;
$$;
