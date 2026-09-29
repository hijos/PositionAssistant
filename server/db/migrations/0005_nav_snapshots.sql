CREATE TABLE positionassistant.nav_snapshots (
  code TEXT NOT NULL CHECK (code ~ '^[0-9]{6}$'),
  nav_date DATE NOT NULL,
  nav NUMERIC(20,10) NOT NULL CHECK (nav > 0),
  source TEXT NOT NULL,
  source_url TEXT NOT NULL,
  fetched_at TIMESTAMPTZ NOT NULL,
  payload JSONB NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  PRIMARY KEY (code, nav_date, source)
);
CREATE INDEX nav_snapshots_latest_idx ON positionassistant.nav_snapshots (code, nav_date DESC, fetched_at DESC);
