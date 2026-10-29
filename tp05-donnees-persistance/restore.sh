#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${TP05_PROJECT:-shopdata-tp05}"
COMPOSE_FILE="${TP05_COMPOSE_FILE:-$SCRIPT_DIR/starter/compose.yml}"
DOCKER_CLI=docker

if command -v docker.exe >/dev/null 2>&1; then
  DOCKER_CLI=docker.exe
fi

if [[ "$DOCKER_CLI" == docker.exe ]]; then
  if command -v wslpath >/dev/null 2>&1; then
    COMPOSE_FILE="$(wslpath -w "$COMPOSE_FILE")"
  elif command -v cygpath >/dev/null 2>&1; then
    COMPOSE_FILE="$(cygpath -w "$COMPOSE_FILE")"
  fi
fi

dc() {
  "$DOCKER_CLI" compose -p "$PROJECT" -f "$COMPOSE_FILE" "$@"
}

if (($# != 1)); then
  echo "Usage: $0 <fichier-shop_*.dump>" >&2
  exit 2
fi

dump_file="$1"
if [[ ! -f "$dump_file" ]]; then
  echo "Dump introuvable: $dump_file" >&2
  exit 1
fi

dc up -d --wait db
dc exec -T db pg_restore \
  --username=shop \
  --dbname=shop \
  --clean \
  --if-exists \
  --no-owner \
  --no-acl < "$dump_file"

echo "Restauration terminée depuis: $dump_file"
