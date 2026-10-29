# Politique de tags

## Les tags qu'on utilise

- `1.4.2` (X.Y.Z) : une release. Elle ne change jamais. Pour corriger, on publie `1.4.3`.
- `1.4` : suit le dernier patch de la 1.4, pratique pour le staging seulement.
- `sha-<commit>` : un tag par build de la CI, pour retrouver le commit git.
- `main` / `dev` : images d'intégration, jamais en prod.
- `latest` : interdit.

Les tags `sha256-<digest>.sig` et `.att` sont créés par cosign, on ne les touche pas.

## Immuabilité

`registry:2` n'empêche pas d'écraser un tag. Dans la CI il faudra vérifier avant le push que le
tag n'existe pas déjà (un `HEAD` sur le manifeste qui répond 200 = on arrête). Harbor, ECR ou
Artifactory ont une option d'immuabilité intégrée.

## Pourquoi pas `latest` en prod

- Deux déploiements avec le même tag peuvent lancer deux images différentes.
- Il peut être réécrit sans qu'on s'en rende compte (c'est l'incident de la prod).
- Impossible de savoir vers quoi faire un rollback.
- Le scan et la signature portent sur un digest, pas sur ce que `latest` désignera demain.

## Référencer par digest

Récupérer le digest :

    curl -sI --cacert starter/registry/certs/ca.crt -u dev:dev-pull-2024 \
      -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
      https://registry.local:5000/v2/shopapi/manifests/1.4.2 | grep -i docker-content-digest

Dans le compose :

    services:
      api:
        image: registry.local:5000/shopapi:1.4.2@sha256:<digest>

Quand il y a un digest, Docker ignore le tag : c'est le digest qui fait foi.

## Retagger sans pull

    crane auth login registry.local:5000 -u ci -p ci-push-2024
    crane tag registry.local:5000/shopapi:1.4.2 1.4

ou avec skopeo :

    skopeo copy --src-creds ci:ci-push-2024 --dest-creds ci:ci-push-2024 \
      docker://registry.local:5000/shopapi:1.4.2 docker://registry.local:5000/shopapi:1.4

Le digest ne change pas, donc la signature cosign reste valable pour le nouveau tag.
