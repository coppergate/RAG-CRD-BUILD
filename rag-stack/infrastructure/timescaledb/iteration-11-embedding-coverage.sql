-- Iteration 11: Embedding Coverage Tracking
-- Creates the tag_embedding_coverage table which tracks which tags have been
-- embedded with which model, and what the current status is (pending / building /
-- complete / stale).

CREATE TABLE IF NOT EXISTS tag_embedding_coverage (
    id               BIGSERIAL    PRIMARY KEY,
    tag_id           INT          NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    embedding_model  VARCHAR(100) NOT NULL,
    vector_dims      INT          NOT NULL,
    vector_count     BIGINT       NOT NULL DEFAULT 0,
    file_count       INT          NOT NULL DEFAULT 0,
    status           VARCHAR(20)  NOT NULL DEFAULT 'pending',
    -- status values: pending | building | complete | stale
    -- Constrained by application logic (not a DB CHECK) to allow zero-downtime
    -- additions of new status values.
    last_embedded_at TIMESTAMPTZ,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (tag_id, embedding_model)
);

CREATE INDEX IF NOT EXISTS idx_tec_tag_model
    ON tag_embedding_coverage (tag_id, embedding_model);

CREATE INDEX IF NOT EXISTS idx_tec_status
    ON tag_embedding_coverage (status);
