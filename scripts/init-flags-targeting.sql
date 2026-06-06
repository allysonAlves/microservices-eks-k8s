-- Creates flags_db and targeting_db on the shared postgres instance
CREATE DATABASE targeting_db;

-- flags table (used in the default 'flags_db' database set via POSTGRES_DB)
\c flags_db
CREATE TABLE IF NOT EXISTS flags (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    is_enabled BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ language 'plpgsql';

CREATE TRIGGER update_flags_updated_at BEFORE UPDATE ON flags
    FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- targeting_rules table
\c targeting_db
CREATE TABLE IF NOT EXISTS targeting_rules (
    id SERIAL PRIMARY KEY,
    flag_name VARCHAR(100) NOT NULL UNIQUE,
    is_enabled BOOLEAN DEFAULT true,
    rules JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ language 'plpgsql';

CREATE TRIGGER update_targeting_rules_updated_at BEFORE UPDATE ON targeting_rules
    FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
