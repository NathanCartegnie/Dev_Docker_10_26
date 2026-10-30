#!/usr/bin/env bash
set -euo pipefail
export MSYS_NO_PATHCONV=1

source ./lib.sh
OLD=(-f compose.yml)
NEW=(-f compose.yml -f compose.pg16.yml)
DEST=./backups
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p "$DEST"

if [ "${1:-}" = "rollback" ]; then
  echo "[rollback] retour sur PostgreSQL 14 (volume pgdata)"
  docker compose "${NEW[@]}" down
  docker compose "${OLD[@]}" up -d
  wait_ready
  bash ./checksum.sh
  exit 0
fi

echo "== 1/6 Checksum avant (PG14)"
docker compose "${OLD[@]}" up -d
wait_ready
AVANT=$(bash ./checksum.sh)
echo "avant : $AVANT"
docker compose exec -T db psql -U shop -d shop -At -c "SHOW server_version;"

echo "== 2/6 Dumps (pg_dumpall = filet de sécurité, pg_dump -Fc = celui qu'on restaure)"
docker compose exec -T db pg_dumpall -U shop > "$DEST/pg14-full-$TS.sql"
docker compose exec -T db pg_dump -U shop -Fc shop > "$DEST/pg14-shop-$TS.dump"
[ -s "$DEST/pg14-shop-$TS.dump" ] || { echo "dump vide, on arrête" >&2; exit 1; }
ls -lh "$DEST"/pg14-*-"$TS".*

echo "== 3/6 Arrêt de PG14 (volume pgdata conservé : pas de -v !)"
docker compose "${OLD[@]}" down
docker volume rm -f shopdata_pgdata16 >/dev/null

echo "== 4/6 Démarrage de PG16 sur un nouveau volume (pgdata16)"
docker compose "${NEW[@]}" up -d db
wait_ready
docker compose exec -T db psql -U shop -d shop -At -c "SHOW server_version;"

echo "== 5/6 Restauration + ANALYZE (les statistiques ne sont pas dans le dump)"
docker compose exec -T db pg_restore -U shop -d shop --no-owner < "$DEST/pg14-shop-$TS.dump"
docker compose exec -T db psql -U shop -d shop -c "ANALYZE;"

echo "== 6/6 Checksum après (PG16)"
APRES=$(bash ./checksum.sh)
echo "après : $APRES"

if [ "$AVANT" = "$APRES" ]; then
  echo "VERDICT : OK, aucune perte ($AVANT)"
else
  echo "VERDICT : KO, checksums différents. Retour arrière : bash ./upgrade-pg.sh rollback" >&2
  exit 1
fi