#!/usr/bin/env bash
# release-gate.sh IMAGE [--push REGISTRY_IMAGE]
# Refuse l'image si elle ne respecte pas la politique Shop SAS.
# Si tout est bon et --push : SBOM, push, signature et attestation.
set -euo pipefail

# jq.exe sous Windows ajoute des \r : on les retire
jq() { command jq "$@" | tr -d '\r'; }

IMAGE="${1:?usage: release-gate.sh IMAGE [--push REGISTRY_IMAGE]}"
PUSH=""
if [ "${2:-}" = "--push" ]; then
  PUSH="${3:?il manque la destination après --push}"
fi

erreurs=0
echo "== Contrôle de $IMAGE =="

# 1. labels OCI
for label in org.opencontainers.image.version org.opencontainers.image.revision org.opencontainers.image.source; do
  valeur=$(docker inspect "$IMAGE" | jq -r --arg l "$label" '.[0].Config.Labels[$l] // empty')
  if [ -z "$valeur" ]; then
    echo "ECHEC : label $label absent"
    erreurs=$((erreurs + 1))
  else
    echo "OK    : $label = $valeur"
  fi
done

# 2. utilisateur
user=$(docker inspect -f '{{.Config.User}}' "$IMAGE")
case "$user" in
  ""|root|0|root:*|0:*)
    echo "ECHEC : l'image tourne en root"
    erreurs=$((erreurs + 1)) ;;
  *) echo "OK    : utilisateur $user" ;;
esac

# 3. healthcheck
hc=$(docker inspect -f '{{.Config.Healthcheck}}' "$IMAGE")
if [ "$hc" = "<nil>" ]; then
  echo "ECHEC : pas de HEALTHCHECK"
  erreurs=$((erreurs + 1))
else
  echo "OK    : HEALTHCHECK présent"
fi

# 4. CVE HIGH/CRITICAL qu'on peut corriger
if trivy image -q --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 "$IMAGE" > /tmp/gate-vuln.txt 2>&1; then
  echo "OK    : pas de CVE HIGH/CRITICAL corrigeable"
else
  echo "ECHEC : CVE trouvées (détail dans /tmp/gate-vuln.txt)"
  erreurs=$((erreurs + 1))
fi

# 5. secrets
if trivy image -q --scanners secret --exit-code 1 "$IMAGE" > /tmp/gate-secret.txt 2>&1; then
  echo "OK    : pas de secret"
else
  echo "ECHEC : secret détecté (détail dans /tmp/gate-secret.txt)"
  erreurs=$((erreurs + 1))
fi

if [ "$erreurs" -gt 0 ]; then
  echo "REFUSÉ ($erreurs erreur(s))"
  exit 1
fi
echo "ACCEPTÉ"

# publication
[ -n "$PUSH" ] || exit 0

export COSIGN_PASSWORD=""
REPO="${PUSH%:*}"      # on enlève le tag

syft "$IMAGE" -o spdx-json > sbom.json

docker tag "$IMAGE" "$PUSH"
sortie=$(docker push "$PUSH")
echo "$sortie"
DIGEST=$(echo "$sortie" | grep -oE 'sha256:[0-9a-f]{64}' | tail -1)

# on signe le digest, pas le tag
cosign sign --yes --key cosign.key "$REPO@$DIGEST"
cosign attest --yes --key cosign.key --type spdxjson --predicate sbom.json "$REPO@$DIGEST"
echo "Publié : $REPO@$DIGEST"
