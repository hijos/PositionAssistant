#!/bin/sh
set -eu

db_path="${QUOTA_DB_PATH:-/app/data/db.json}"
seed_path="${QUOTA_SEED_PATH:-/app/seed.json}"

mkdir -p "$(dirname "$db_path")"
if [ ! -f "$db_path" ]; then
  cp "$seed_path" "$db_path"
fi

exec node quota-service/index.js
