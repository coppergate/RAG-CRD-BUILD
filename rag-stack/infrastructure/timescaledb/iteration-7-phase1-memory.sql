-- Iteration 7 Phase 1: Local Prompt Memory + Recall Foundation
-- Apply after infrastructure/timescaledb/schema.sql

-- 1) memory_items (Canonical memory rows)
CREATE TABLE IF NOT EXISTS memory_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID,
    session_id UUID REFERENCES sessions(session_id) ON DELETE CASCADE,
    user_id UUID,
    type TEXT NOT NULL, -- e.g., short_term_memory, long_term_memory, persistent_memory
    summary TEXT NOT NULL,
    content TEXT,
    salience DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    retention_score DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    decay_state JSONB DEFAULT '{}'::jsonb,
    status TEXT NOT NULL DEFAULT 'active', -- active, pruned, archived
    pinning BOOLEAN NOT NULL DEFAULT FALSE,
    ttl BIGINT, -- TTL in seconds
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2) memory_links (Provenance and association)
CREATE TABLE IF NOT EXISTS memory_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    memory_item_id UUID NOT NULL REFERENCES memory_items(id) ON DELETE CASCADE,
    source_message_ids JSONB DEFAULT '[]'::jsonb,
    ingestion_ids JSONB DEFAULT '[]'::jsonb,
    tags JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3) memory_events (Audit trail for memory actions)
CREATE TABLE IF NOT EXISTS memory_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    memory_item_id UUID NOT NULL REFERENCES memory_items(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL, -- write, update, prune, audit
    event_data JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4) Indexes
CREATE INDEX IF NOT EXISTS idx_memory_items_tenant ON memory_items(tenant_id);
CREATE INDEX IF NOT EXISTS idx_memory_items_session ON memory_items(session_id);
CREATE INDEX IF NOT EXISTS idx_memory_items_user ON memory_items(user_id);
CREATE INDEX IF NOT EXISTS idx_memory_items_type ON memory_items(type);
CREATE INDEX IF NOT EXISTS idx_memory_items_status ON memory_items(status);
CREATE INDEX IF NOT EXISTS idx_memory_links_item ON memory_links(memory_item_id);
CREATE INDEX IF NOT EXISTS idx_memory_events_item ON memory_events(memory_item_id);
CREATE INDEX IF NOT EXISTS idx_memory_events_type ON memory_events(event_type);
CREATE INDEX IF NOT EXISTS idx_memory_events_time ON memory_events(created_at DESC);

-- 5) Update trigger for memory_items.updated_at
CREATE OR REPLACE FUNCTION set_updated_at()
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
EXECUTE FUNCTION set_updated_at();
