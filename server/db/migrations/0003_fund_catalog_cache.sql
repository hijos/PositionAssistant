CREATE TABLE positionassistant.fund_catalog_cache (
  source text PRIMARY KEY,
  snapshot jsonb NOT NULL CHECK (jsonb_typeof(snapshot) = 'object')
);
