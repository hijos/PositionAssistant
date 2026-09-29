CREATE TABLE positionassistant.market_snapshots (
  symbol TEXT NOT NULL CHECK (symbol ~ '^[A-Za-z0-9.^=-]{1,20}$'),
  trade_date DATE NOT NULL,
  price NUMERIC(20,10) NOT NULL CHECK (price > 0),
  source TEXT NOT NULL,
  source_url TEXT NOT NULL,
  fetched_at TIMESTAMPTZ NOT NULL,
  payload JSONB NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  PRIMARY KEY (symbol, trade_date, source)
);
CREATE INDEX market_snapshots_latest_idx ON positionassistant.market_snapshots (symbol, trade_date DESC, fetched_at DESC);