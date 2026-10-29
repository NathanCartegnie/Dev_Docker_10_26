#!/usr/bin/env bash
set -euo pipefail

API_URL="${API_URL:-http://api.localhost}"
DOCKER_CLI=docker
if command -v docker.exe >/dev/null 2>&1; then
  DOCKER_CLI=docker.exe
fi

curl --fail --silent --show-error "$API_URL/ready" >/dev/null
curl --fail --silent --show-error "$API_URL/products" >/dev/null

shopt -s nocasematch
headers="$(curl --fail --silent --show-error -D - -o /dev/null "$API_URL/products")"
if [[ ! "$headers" =~ X-Cache:[[:space:]]*HIT ]]; then
  echo "Le cache Redis devait répondre HIT." >&2
  exit 1
fi

curl --fail --silent --show-error \
  -H 'Content-Type: application/json' \
  -d '{"productId":1,"quantity":1}' \
  "$API_URL/orders" >/dev/null

for attempt in {1..30}; do
  status="$(
    "$DOCKER_CLI" compose exec -T db sh -c \
      'PGPASSWORD="$(cat /run/secrets/db_password)" psql -U shop -d shop -Atc "SELECT status FROM orders WHERE product_id=1 ORDER BY id DESC LIMIT 1"'
  )"
  if [[ "$status" == "confirmed" ]]; then
    echo "Smoke test réussi: /ready, cache HIT et commande confirmed."
    exit 0
  fi
  sleep 1
done

echo "Le worker n'a pas confirmé la dernière commande (statut: ${status:-inconnu})." >&2
exit 1
