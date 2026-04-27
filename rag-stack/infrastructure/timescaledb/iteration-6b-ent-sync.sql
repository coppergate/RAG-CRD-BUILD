-- Sync database with Ent schema changes

-- 1. Update retrieval_logs
ALTER TABLE retrieval_logs ADD COLUMN IF NOT EXISTS session_id UUID REFERENCES sessions(session_id) ON DELETE SET NULL;
ALTER TABLE retrieval_logs ADD COLUMN IF NOT EXISTS query TEXT;

-- 2. Update memory_events
ALTER TABLE memory_events ADD COLUMN IF NOT EXISTS session_id UUID REFERENCES sessions(session_id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_memory_events_session ON memory_events(session_id);
