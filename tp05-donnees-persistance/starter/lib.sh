#!/usr/bin/env bash
wait_ready() {
  echo -n "[wait] attente de PostgreSQL"
  for _ in $(seq 1 60); do
    if docker compose exec -T db pg_isready -h 127.0.0.1 -U shop -q 2>/dev/null; then
      echo " ok"
      return 0
    fi
    echo -n "."
    sleep 2
  done
  echo " timeout" >&2
  return 1
}
