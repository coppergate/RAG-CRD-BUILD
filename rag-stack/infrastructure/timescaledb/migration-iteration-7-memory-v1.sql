-- Migration: Iteration 7 Memory System (Phase 1)
-- Description: Implements 3-stage memory (STM, LTM, Persistent)
-- Affected Tables: memory_items, memory_links, memory_events

-- 1. Cleanup legacy tables from prior iterations or partial setups
DROP TABLE IF EXISTS memory_links CASCADE;
DROP TABLE IF EXISTS memory_items CASCADE;
DROP TABLE IF EXISTS memory_events CASCADE;

-- 2. Create memory_items (The central memory store)
CREATE TABLE memory_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(project_id) ON DELETE CASCADE,
    session_id UUID REFERENCES sessions(session_id) ON DELETE CASCADE,
    user_id UUID, -- Optional user-level scope
    memory_type TEXT NOT NULL, -- short_term_memory, long_term_memory, persistent_memory
    summary TEXT NOT NULL,
    content TEXT,
    salience DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    retention_score DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    decay_state JSONB DEFAULT '{}'::jsonb,
    status TEXT NOT NULL DEFAULT 'active', -- active, archived, pruned
    pinned BOOLEAN NOT NULL DEFAULT FALSE,
    expires_at TIMESTAMPTZ, -- Expiry timestamp
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Create memory_links (Provenance and Relationship Tracking)
CREATE TABLE memory_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    memory_item_id UUID NOT NULL REFERENCES memory_items(id) ON DELETE CASCADE,
    source_message_ids JSONB DEFAULT '[]'::jsonb, -- UUIDs of messages
    ingestion_ids JSONB DEFAULT '[]'::jsonb, -- UUIDs of files/chunks
    tags JSONB DEFAULT '[]'::jsonb, -- Associated tags
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. Create memory_events (Audit and Lifecycle Tracking)
CREATE TABLE memory_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    memory_item_id UUID REFERENCES memory_items(id) ON DELETE SET NULL,
    session_id UUID REFERENCES sessions(session_id) ON DELETE CASCADE,
    event_type TEXT NOT NULL, -- write, refresh, retrieve, score_update, prune
    event_data JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. Indexes for retrieval efficiency
CREATE INDEX IF NOT EXISTS idx_memory_items_project ON memory_items(project_id);
CREATE INDEX IF NOT EXISTS idx_memory_items_session ON memory_items(session_id);
CREATE INDEX IF NOT EXISTS idx_memory_items_user ON memory_items(user_id);
CREATE INDEX IF NOT EXISTS idx_memory_items_type_status ON memory_items(memory_type, status);
CREATE INDEX IF NOT EXISTS idx_memory_items_recall ON memory_items(retention_score DESC, salience DESC);
CREATE INDEX IF NOT EXISTS idx_memory_links_item ON memory_links(memory_item_id);
CREATE INDEX IF NOT EXISTS idx_memory_events_item ON memory_events(memory_item_id);
CREATE INDEX IF NOT EXISTS idx_memory_events_session ON memory_events(session_id);

-- 6. Trigger for updated_at
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_memory_items_updated_at ON memory_items;
CREATE TRIGGER trg_memory_items_updated_at
BEFORE UPDATE ON memory_items
FOR EACH ROW
EXECUTE FUNCTION update_timestamp();
