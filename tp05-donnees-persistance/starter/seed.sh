#!/usr/bin/env bash
set -euo pipefail

DOCKER_CLI=docker
if command -v docker.exe >/dev/null 2>&1; then
  DOCKER_CLI=docker.exe
fi

"$DOCKER_CLI" compose -p "${TP05_PROJECT:-shopdata-tp05}" -f compose.yml exec -T db psql -U shop -d shop <<'SQL'
CREATE TABLE IF NOT EXISTS products(id SERIAL PRIMARY KEY, name TEXT, price NUMERIC(10,2));
CREATE TABLE IF NOT EXISTS orders(id SERIAL PRIMARY KEY, product_id INT REFERENCES products(id), quantity INT, status TEXT, created_at TIMESTAMPTZ DEFAULT now());
INSERT INTO products(name, price) SELECT 'Produit ' || g, (random()*100)::numeric(10,2) FROM generate_series(1, 500) g;
INSERT INTO orders(product_id, quantity, status, created_at)
  SELECT (random()*499+1)::int, (random()*5+1)::int, (ARRAY['pending','confirmed','rejected'])[(random()*2+1)::int], now() - (random()*365 || ' days')::interval
  FROM generate_series(1, 100000);
SELECT count(*) AS orders, md5(string_agg(id::text || status, ',' ORDER BY id)) AS checksum FROM orders;
SQL
