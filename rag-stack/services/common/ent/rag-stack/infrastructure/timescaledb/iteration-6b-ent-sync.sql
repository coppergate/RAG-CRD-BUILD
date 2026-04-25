-- Sync database with Ent schema changes

-- 1. Update retrieval_logs
ALTER TABLE retrieval_logs ADD COLUMN IF NOT EXISTS session_id UUID REFERENCES sessions(session_id) ON DELETE SET NULL;
ALTER TABLE retrieval_logs ADD COLUMN IF NOT EXISTS query TEXT;

-- 2. Create memory_events if not exists
CREATE TABLE IF NOT EXISTS memory_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    memory_item_id UUID REFERENCES memory_items(memory_id) ON DELETE CASCADE,
    session_id UUID REFERENCES sessions(session_id) ON DELETE SET NULL,
    event_type TEXT NOT NULL,
    event_data JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_memory_events_session ON memory_events(session_id);
CREATE INDEX IF NOT EXISTS idx_memory_events_memory ON memory_events(memory_item_id);
CREATE INDEX IF NOT EXISTS idx_memory_events_created ON memory_events(created_at DESC);
