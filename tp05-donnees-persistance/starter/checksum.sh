#!/usr/bin/env bash
set -euo pipefail
docker compose exec -T db psql -U shop -d shop -At -c \
  "SELECT count(*) || '|' || md5(string_agg(id::text || status, ',' ORDER BY id)) FROM orders;"
