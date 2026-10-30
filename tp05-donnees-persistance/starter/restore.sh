#!/usr/bin/env bash
set -euo pipefail
export MSYS_NO_PATHCONV=1

source ./lib.sh
VOLUME=shopdata_pgdata
FILE=${1:-$(ls -1t ./backups/shop-*.dump | head -n 1)}

[ -f "$FILE" ] || { echo "fichier introuvable : $FILE" >&2; exit 1; }
echo "[restore] source : $FILE"

case "$FILE" in
  *.dump)
    wait_ready
    docker compose exec -T db pg_restore -U shop -d shop --clean --if-exists --no-owner < "$FILE"
    ;;
  *.tgz)
    docker compose stop db
    docker run --rm -i -v "$VOLUME":/data alpine \
      sh -c 'find /data -mindepth 1 -delete && tar xzf - -C /data' < "$FILE"
    docker compose start db
    wait_ready
    ;;
  *) echo "extension non gérée (.dump ou .tgz)" >&2; exit 2 ;;
esac

echo "[restore] checksum après restauration :"
bash ./checksum.sh