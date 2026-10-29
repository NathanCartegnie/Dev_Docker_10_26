#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${TP05_PROJECT:-shopdata-tp05}"
COMPOSE_FILE="${TP05_COMPOSE_FILE:-$SCRIPT_DIR/starter/compose.yml}"
BACKUP_DIR="${TP05_BACKUP_DIR:-$SCRIPT_DIR/backups}"
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

if ! dc exec -T db pg_isready -U shop -d shop >/dev/null; then
  echo "La base $PROJECT n'est pas démarrée ou n'est pas prête." >&2
  exit 1
fi

container_id="$(dc ps -q db)"
if [[ -z "$container_id" ]]; then
  echo "Impossible de trouver le conteneur PostgreSQL du projet $PROJECT." >&2
  exit 1
fi

volume_name="$(
  "$DOCKER_CLI" inspect "$container_id" \
    --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}'
)"
if [[ -z "$volume_name" ]]; then
  echo "Aucun volume monté sur /var/lib/postgresql/data." >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
dump_file="$BACKUP_DIR/shop_$timestamp.dump"
volume_file="$BACKUP_DIR/shop_$timestamp.volume.tar.gz"
dump_tmp="$dump_file.tmp"
volume_tmp="$volume_file.tmp"
db_stopped=0

cleanup() {
  result=$?
  if (( db_stopped )); then
    echo "Redémarrage de PostgreSQL après la sauvegarde brute..." >&2
    dc up -d --wait db || echo "ERREUR: PostgreSQL n'a pas redémarré automatiquement." >&2
  fi
  rm -f -- "$dump_tmp" "$volume_tmp"
  exit "$result"
}
trap cleanup EXIT

dc exec -T db pg_dump -U shop -d shop -Fc > "$dump_tmp"
mv -- "$dump_tmp" "$dump_file"
echo "Dump logique créé: $dump_file"

echo "Arrêt temporaire de PostgreSQL pour obtenir une copie cohérente du volume..."
dc stop db
db_stopped=1
"$DOCKER_CLI" run --rm --network none \
  -v "$volume_name:/data:ro" \
  alpine:3.20 tar -C /data -czf - . > "$volume_tmp"
mv -- "$volume_tmp" "$volume_file"
dc up -d --wait db
db_stopped=0

echo "Copie brute créée: $volume_file"

shopt -s nullglob
dumps=("$BACKUP_DIR"/shop_*.dump)
if ((${#dumps[@]} > 7)); then
  for ((index = 0; index < ${#dumps[@]} - 7; index++)); do
    old_dump="${dumps[$index]}"
    old_volume="${old_dump%.dump}.volume.tar.gz"
    rm -f -- "$old_dump" "$old_volume"
  done
fi

echo "Rétention appliquée: 7 sauvegardes logiques et leurs copies brutes au maximum."
