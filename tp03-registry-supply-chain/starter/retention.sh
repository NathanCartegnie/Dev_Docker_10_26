#!/bin/bash
# retention.sh : garde les N tags les plus récents (hors semver) d'un dépôt
# usage : ./retention.sh shopapi 3          (simulation)
#         ./retention.sh shopapi 3 --apply  (supprime vraiment)
set -e

# jq.exe sous Windows ajoute des \r : on les retire
jq() { command jq "$@" | tr -d '\r'; }

REGISTRY=https://registry.local:5000
CREDS=ci:ci-push-2024
CACERT=starter/registry/certs/ca.crt

REPO=$1
N=${2:-5}
APPLY=$3
ACCEPT="Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"

reg() { curl -s --cacert $CACERT -u $CREDS "$@"; }

get_digest() {
  reg -I -H "$ACCEPT" $REGISTRY/v2/$REPO/manifests/$1 | grep -i docker-content-digest | awk '{print $2}' | tr -d '\r'
}

# la date de build est dans le blob de config de l'image
get_date() {
  cfg=$(reg -H "$ACCEPT" $REGISTRY/v2/$REPO/manifests/$1 | jq -r .config.digest)
  reg $REGISTRY/v2/$REPO/blobs/$cfg | jq -r .created
}

all=$(reg $REGISTRY/v2/$REPO/tags/list | jq -r '.tags[]')

# on ignore les tags semver et les signatures cosign (sha256-...)
candidats=$(echo "$all" | grep -Ev '^v?[0-9]+\.[0-9]+\.[0-9]+' | grep -Ev '^sha256-' || true)

for t in $candidats; do
  echo "$(get_date $t) $t"
done | sort -r > /tmp/tags_tries.txt

drop=$(tail -n +$((N + 1)) /tmp/tags_tries.txt | awk '{print $2}')

# digests à ne pas supprimer : ceux des tags qu'on garde
garde=""
for t in $all; do
  if ! echo "$drop" | grep -qx "$t"; then
    garde="$garde $(get_digest $t)"
  fi
done

for t in $drop; do
  d=$(get_digest $t)
  if echo "$garde" | grep -q "$d"; then
    echo "on garde $t (même digest qu'un tag conservé)"
  elif [ "$APPLY" = "--apply" ]; then
    code=$(reg -X DELETE -o /dev/null -w "%{http_code}" $REGISTRY/v2/$REPO/manifests/$d)
    echo "supprimé $t ($d) -> $code"
  else
    echo "simulation : je supprimerais $t ($d)"
  fi
done
