#!/usr/bin/env bash
set -euo pipefail
export MSYS_NO_PATHCONV=1

DEST=./backups
KEEP=7
VOLUME=shopdata_pgdata
TS=$(date +%Y%m%d-%H%M%S)
MODE=${1:-all}

mkdir -p "$DEST"

logical() {
  local f="$DEST/shop-$TS.dump"
  echo "[backup] dump logique -> $f"
  if ! docker compose exec -T db pg_dump -U shop -Fc shop > "$f"; then
    rm -f "$f"
    echo "pg_dump a échoué" >&2
    exit 1
  fi
}

raw() {
  local f="$DEST/pgdata-$TS.tgz"
  echo "[backup] sauvegarde brute -> $f (arrêt propre de la base pour avoir un état cohérent)"
  docker compose stop db
  if ! docker run --rm -v "$VOLUME":/data:ro alpine tar czf - -C /data . > "$f"; then
    rm -f "$f"
    docker compose start db
    echo "tar a échoué" >&2
    exit 1
  fi
  docker compose start db
}

rotate() {
  for p in 'shop-*.dump' 'pgdata-*.tgz'; do
    ls -1t "$DEST"/$p 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f -- || true
  done
}

case "$MODE" in
  logical) logical ;;
  raw)     raw ;;
  all)     logical; raw ;;
  *) echo "usage: $0 [all|logical|raw]" >&2; exit 2 ;;
esac

rotate
echo "[backup] terminé :"
ls -lh "$DEST"