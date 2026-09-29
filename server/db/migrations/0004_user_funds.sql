-- Existing authentication still issues legacy string user IDs. Do not pretend
-- these reference the as-yet-unwired PostgreSQL users table.
CREATE TABLE positionassistant.user_funds (
  owner_id TEXT NOT NULL,
  code TEXT NOT NULL CHECK (code ~ '^[0-9]{6}$'),
  payload JSONB NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  PRIMARY KEY (owner_id, code)
);
