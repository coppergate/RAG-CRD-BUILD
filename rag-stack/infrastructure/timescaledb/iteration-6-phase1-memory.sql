-- Iteration 6 Phase 1: Memory model foundation
-- Apply after infrastructure/timescaledb/schema.sql (unified base schema).

-- 1) Canonical memory rows
CREATE TABLE IF NOT EXISTS memory_items (
    memory_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    memory_type TEXT NOT NULL CHECK (memory_type IN ('short_term_memory', 'long_term_memory', 'persistent_memory')),
    session_id UUID REFERENCES sessions(session_id) ON DELETE CASCADE,
    user_id UUID,
    project_id UUID REFERENCES projects(project_id) ON DELETE CASCADE,
    summary TEXT NOT NULL,
    content TEXT,
    salience DOUBLE PRECISION NOT NULL DEFAULT 0.5 CHECK (salience >= 0.0 AND salience <= 1.0),
    retention_score DOUBLE PRECISION NOT NULL DEFAULT 0.5 CHECK (retention_score >= 0.0 AND retention_score <= 1.0),
    decay_state JSONB NOT NULL DEFAULT '{}'::jsonb,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived', 'pruned')),
    pinned BOOLEAN NOT NULL DEFAULT FALSE,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    expires_at TIMESTAMPTZ,
    last_accessed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (session_id IS NOT NULL OR user_id IS NOT NULL OR project_id IS NOT NULL)
);

-- 2) Provenance and correction links
CREATE TABLE IF NOT EXISTS memory_links (
    link_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    memory_id UUID NOT NULL REFERENCES memory_items(memory_id) ON DELETE CASCADE,
    source_kind TEXT NOT NULL CHECK (source_kind IN ('prompt', 'response', 'ingestion', 'manual', 'system')),
    source_id TEXT NOT NULL,
    relation_type TEXT NOT NULL CHECK (relation_type IN ('derived_from', 'supports', 'contradicts', 'corrects')),
    weight DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (memory_id, source_kind, source_id, relation_type)
);

-- 3) Audit trail for write/retrieve/retention actions
CREATE TABLE IF NOT EXISTS memory_events (
    event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    memory_id UUID REFERENCES memory_items(memory_id) ON DELETE SET NULL,
    event_type TEXT NOT NULL CHECK (event_type IN ('write', 'refresh', 'retrieve', 'score_update', 'pin', 'unpin', 'prune', 'delete')),
    reason TEXT,
    actor_service TEXT,
    request_id TEXT,
    correlation_id TEXT,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4) Update trigger for memory_items.updated_at
CREATE OR REPLACE FUNCTION set_memory_items_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_set_memory_items_updated_at ON memory_items;
CREATE TRIGGER trg_set_memory_items_updated_at
BEFORE UPDATE ON memory_items
FOR EACH ROW
EXECUTE FUNCTION set_memory_items_updated_at();

-- 5) Indexes for core phase-1 access patterns
CREATE INDEX IF NOT EXISTS idx_memory_items_scope
    ON memory_items (session_id, user_id, project_id);

CREATE INDEX IF NOT EXISTS idx_memory_items_type_status
    ON memory_items (memory_type, status, pinned);

CREATE INDEX IF NOT EXISTS idx_memory_items_rank
    ON memory_items (retention_score DESC, salience DESC, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_memory_items_expires
    ON memory_items (expires_at)
    WHERE expires_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_memory_items_metadata_gin
    ON memory_items USING GIN (metadata);

CREATE INDEX IF NOT EXISTS idx_memory_links_source
    ON memory_links (source_kind, source_id);

CREATE INDEX IF NOT EXISTS idx_memory_events_memory_time
    ON memory_events (memory_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_memory_events_type_time
    ON memory_events (event_type, created_at DESC);
