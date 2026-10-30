#!/usr/bin/env bash
# audit.sh - Vérification des règles de sécurité sur les conteneurs actifs

set -euo pipefail

ERRORS=0
CONTAINERS=$(docker ps -q)

if [ -z "$CONTAINERS" ]; then
  echo "Aucun conteneur en cours d'exécution."
  exit 0
fi

printf "%-20s %-10s %-12s %-15s %-10s %-10s %-10s %-12s\n" \
  "CONTENEUR" "USER" "PRIVILEGED" "CAPS_DROPPED" "READONLY" "MEM_LIMIT" "PID_LIMIT" "SOCKET_MOUNT"
echo "---------------------------------------------------------------------------------------------------------------"

for c in $CONTAINERS; do
  NAME=$(docker inspect --format '{{.Name}}' "$c" | sed 's/\///')
  USER=$(docker inspect --format '{{.Config.User}}' "$c")
  [ -z "$USER" ] && USER="root (default)"

  PRIVILEGED=$(docker inspect --format '{{.HostConfig.Privileged}}' "$c")
  CAPS_DROP=$(docker inspect --format '{{.HostConfig.CapDrop}}' "$c")
  READONLY=$(docker inspect --format '{{.HostConfig.ReadonlyRootfs}}' "$c")
  MEM=$(docker inspect --format '{{.HostConfig.Memory}}' "$c")
  PIDS=$(docker inspect --format '{{.HostConfig.PidsLimit}}' "$c")
  NO_NEW_PRIV=$(docker inspect --format '{{.HostConfig.SecurityOpt}}' "$c" | grep -q "no-new-privileges" && echo "true" || echo "false")

  # Vérification du montage du socket Docker
  SOCKET_MOUNT=$(docker inspect --format '{{range .Mounts}}{{if eq .Source "/var/run/docker.sock"}}true{{end}}{{end}}' "$c")
  [ -z "$SOCKET_MOUNT" ] && SOCKET_MOUNT="false"

  # Évaluation des écarts
  FAIL=0
  if [ "$USER" = "root (default)" ] || [ "$USER" = "0" ] || [ "$USER" = "root" ]; then FAIL=1; fi
  if [ "$PRIVILEGED" = "true" ]; then FAIL=1; fi
  if [ "$READONLY" = "false" ]; then FAIL=1; fi
  if [ "$MEM" = "0" ]; then FAIL=1; fi
  if [ "$PIDS" = "0" ] || [ "$PIDS" = "-1" ]; then FAIL=1; fi
  if [ "$SOCKET_MOUNT" = "true" ]; then FAIL=1; fi

  if [ $FAIL -ne 0 ]; then
    ERRORS=$((ERRORS + 1))
  fi

  printf "%-20s %-10s %-12s %-15s %-10s %-10s %-10s %-12s\n" \
    "$NAME" "$USER" "$PRIVILEGED" "$CAPS_DROP" "$READONLY" "$MEM" "$PIDS" "$SOCKET_MOUNT"
done

echo "---------------------------------------------------------------------------------------------------------------"
if [ $ERRORS -gt 0 ]; then
  echo "❌ Audit ÉCHU : $ERRORS conteneur(s) présentent des écarts de sécurité."
  exit 1
else
  echo "✅ Audit REUSSIS : Tous les conteneurs sont conformes."
  exit 0
fi