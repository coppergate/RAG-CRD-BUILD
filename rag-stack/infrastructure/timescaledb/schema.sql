-- RAG Session Management Schema
-- Using TimescaleDB for time-series chat history

-- 1. Projects table to group sessions
CREATE TABLE IF NOT EXISTS projects (
    project_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Sessions table
CREATE TABLE IF NOT EXISTS sessions (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(project_id) ON DELETE CASCADE,
    name TEXT UNIQUE,
    metadata JSONB, -- For any extra info
    user_id UUID,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_active_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Messages table (Hypertable)
CREATE TABLE IF NOT EXISTS chat_messages (
    message_id UUID DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES sessions(session_id) ON DELETE CASCADE,
    role TEXT NOT NULL, -- 'user', 'assistant', 'system'
    content TEXT NOT NULL,
    tokens_used INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (message_id, created_at)
);

-- convert chat_messages to a hypertable
SELECT create_hypertable('chat_messages', 'created_at', if_not_exists => TRUE);

-- 4. Archiving and Heat Management
-- Retention policy: data stays in chat_messages (Hot) for 30 days
-- Then it can be moved to a 'compressed' or 'cold' state
SELECT add_retention_policy('chat_messages', INTERVAL '90 days', if_not_exists => TRUE);

-- 5. Vector search log
CREATE TABLE IF NOT EXISTS retrieval_logs (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL, -- Refers to user message
    retrieved_chunks JSONB, -- List of paths and chunks
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Iteration 2: Ingestion and Tagging Support

-- 6. Code Ingestion Tracking
CREATE TABLE IF NOT EXISTS code_ingestion (
    ingestion_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    s3_bucket_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 7. Tag Definition
CREATE TABLE IF NOT EXISTS tag (
    tag_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tag_name TEXT NOT NULL UNIQUE
);

-- 8. Ingestion to Tag Mapping
CREATE TABLE IF NOT EXISTS code_ingestion_tag (
    ingestion_id UUID REFERENCES code_ingestion(ingestion_id) ON DELETE CASCADE,
    tag_id UUID REFERENCES tag(tag_id) ON DELETE CASCADE,
    PRIMARY KEY (ingestion_id, tag_id)
);

-- 9. Code Embedding Index (Metadata backup)
CREATE TABLE IF NOT EXISTS code_embedding (
    embedding_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ingestion_id UUID REFERENCES code_ingestion(ingestion_id) ON DELETE CASCADE,
    embedding_vector REAL[], -- Using REAL[] for compatibility, can be changed to VECTOR(384) if pgvector is available
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 10. Embedding to Tag Mapping
CREATE TABLE IF NOT EXISTS code_embedding_tag (
    embedding_id UUID REFERENCES code_embedding(embedding_id) ON DELETE CASCADE,
    tag_id UUID REFERENCES tag(tag_id) ON DELETE CASCADE,
    PRIMARY KEY (embedding_id, tag_id)
);

-- 11. Session to Tag Association
CREATE TABLE IF NOT EXISTS session_tag (
    session_id UUID REFERENCES sessions(session_id) ON DELETE CASCADE,
    tag_id UUID REFERENCES tag(tag_id) ON DELETE CASCADE,
    PRIMARY KEY (session_id, tag_id)
);

-- 12. Session Cleanup Procedure
CREATE OR REPLACE PROCEDURE expire_old_sessions(job_id int, config jsonb)
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM sessions
    WHERE last_active_at < now() - INTERVAL '24 hours';
END
$$;

-- Register cleanup job (every 1 hour)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM timescaledb_information.jobs WHERE proc_name = 'expire_old_sessions') THEN
        PERFORM add_job('expire_old_sessions', '1 hour');
    END IF;
END
$$;

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project_id);
CREATE INDEX IF NOT EXISTS idx_messages_session ON chat_messages(session_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tag_name ON tag(tag_name);
CREATE INDEX IF NOT EXISTS idx_code_ingestion_bucket ON code_ingestion(s3_bucket_id);
