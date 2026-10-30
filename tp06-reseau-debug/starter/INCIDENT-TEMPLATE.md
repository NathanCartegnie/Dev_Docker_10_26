# Rapport d'incident — préprod Shop SAS

**Heure de début** : 9h12 · **Heure de résolution** : 10h41 · **Impact** : préprod indisponible (`localhost:8081` ne renvoie pas le catalogue)

## Chronologie du diagnostic

| Heure | Symptôme observé | Commande / preuve | Hypothèse | Résultat |
|-------|------------------|-------------------|-----------|----------|
| 9h18 | Le port 8081 répond, mais par une page Apache 404 | `curl.exe -s localhost:8081/health` | Ce n'est pas notre front qui répond | Réponse `Apache/2.4.66 (Debian)` : autre conteneur sur le port |
| 9h24 | Port 8081 occupé | `docker ps --filter "publish=8081" --format "{{.Names}}  {{.Ports}}"` | Un conteneur d'un autre TP publie 8081 | `host2-phpmyadmin-1`, arrêté avec `docker stop` |
| 9h38 | Revue du compose avant lancement | Relecture de `compose.yml` et `nginx/default.conf` | Plusieurs erreurs visibles à la lecture | 14 anomalies repérées (voir tableau, #1 à #14) |
| 9h52 | `docker compose up --build` échoue (`failed to execute bake`) | `Test-Path ..\..\tp04-compose-entreprise\solution\apps\shopapi` (False), puis sans `solution` (True) | Mauvais chemin de build | Le dossier `solution` n'existe pas, chemins corrigés (#15) |
| 10h08 | `incident-api-1` en `restarting`, jamais healthy | `docker compose logs --tail 40 api`, `docker inspect incident-api-1 --format '{{json .State}}'` | Le conteneur plante au démarrage | `Cannot find module '/app/server.js'` : le fichier est dans `src/` (#16) |
| 10h15 | Confirmation de la bonne commande de lancement | `Select-String ...\Dockerfile -Pattern "CMD"` | L'image sait déjà démarrer l'API | `CMD ["node", "src/server.js"]`, `command` retiré du compose |
| 10h27 | Front `unhealthy` alors que `curl` fonctionne | `docker inspect incident-front-1 --format '{{json .State.Health.Log}}'` | Le healthcheck est en cause, pas nginx | `wget: Connection refused` sur `localhost` (résolu en IPv6, nginx écoute en IPv4) |
| 10h34 | Healthcheck du front corrigé | healthcheck passé sur `http://127.0.0.1/health` puis `docker compose up -d --wait` | `127.0.0.1` évite le problème IPv6 | Les 4 services passent `healthy` |
| 10h41 | Validation finale | `docker compose ps`, `curl.exe -s localhost:8081/health`, `curl.exe -si localhost:8081/products \| Select-String "X-Cache"` (x2) | Stack corrigée | Tout `healthy`, `front ok`, catalogue renvoyé avec `X-Cache: HIT` |

## Anomalies trouvées

| # | Fichier / service | Anomalie | Correction | Catégorie (réseau / config / cycle de vie / stockage) |
|---|-------------------|----------|------------|----------|
| 1 | compose / front | `./nginx` monté sur `/etc/nginx/conf.d/default.conf` (un dossier sur un fichier) | `./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro` | stockage |
| 2 | compose / réseau `public` | `internal: true` sur le réseau du front : le port 8081 ne peut pas être publié | `public` en réseau normal | réseau |
| 3 | default.conf | `proxy_pass http://localhost:3000` : `localhost` est le conteneur nginx lui-même | `proxy_pass http://api:8080` | réseau |
| 4 | default.conf | Port 3000 alors que l'API reçoit `PORT=8080` | Port aligné sur 8080 | config |
| 5 | compose / api | `databse` dans `DATABASE_URL` | `db` | config |
| 6 | compose / api | `container_name: api` avec `replicas: 2` : deux conteneurs ne peuvent pas porter le même nom | `replicas` supprimé | cycle de vie |
| 7 | compose / api | API sur `public` uniquement, DB sur `backend` : aucun chemin réseau entre les deux | API sur `public` et `backend` | réseau |
| 8 | compose / api | `REDIS_URL` sans mot de passe alors que Redis a `--requirepass` | `redis://:${REDIS_PASSWORD}@redis:6379` | config |
| 9 | compose / redis | `network_mode: host` : hors réseaux compose, pas de résolution du nom `redis` | Redis sur le réseau `backend` | réseau |
| 10 | compose / db | Healthcheck `pg_isready -U postgres` alors que l'utilisateur est `shop` | `pg_isready -U shop -d shop` | cycle de vie |
| 11 | compose / front, api, redis | Aucun healthcheck, `depends_on` du front sans condition | Healthchecks ajoutés, `condition: service_healthy` | cycle de vie |
| 12 | compose / backend | DB et Redis sur un réseau non isolé | `backend` en `internal: true` | sécurité |
| 13 | compose | Mots de passe en clair dans le compose | Variables dans `.env` (non versionné) | sécurité |
| 14 | compose | Pas de politique de redémarrage | `restart: unless-stopped` | cycle de vie |
| 15 | compose / api, db | Chemins `build` et `init.sql` vers `tp04-compose-entreprise/solution/...`, dossier inexistant | Chemins corrigés vers `tp04-compose-entreprise/apps/shopapi` et `.../db/init.sql` | config |
| 16 | compose / api | `command: node server.js` alors que l'app est dans `src/` : redémarrage en boucle | `command` supprimé, l'image utilise son `CMD` | cycle de vie |

## Pourquoi ça n'a pas été détecté avant ?

Le compose a été modifié directement avant un congé, sans relecture ni test derrière. Aucune CI ne lançait `docker compose config` ou un smoke test, et sans healthchecks, `docker compose up` ne montrait pas que la stack ne fonctionnait pas. Plusieurs erreurs (faute de frappe, mauvais port, mauvais chemin) sont faciles à rater à l'œil. Enfin, un autre conteneur occupait déjà le port 8081 et répondait à la place de la stack, ce qui pouvait faire croire à un problème différent.

## Actions de prévention

1. **CI avec validation + smoke test** : `docker compose config -q`, puis `docker compose up -d --build --wait` et un `curl` sur `/health` et `/products` à chaque modification du compose.
2. **Revue de code obligatoire** sur le `compose.yml` et la conf nginx (merge request avec un second relecteur), avec un linter de compose.
3. **Healthchecks sur tous les services** avec `depends_on: condition: service_healthy` et `--wait`, pour que l'échec soit visible tout de suite. Dans les healthchecks, utiliser `127.0.0.1` plutôt que `localhost` pour éviter les écarts IPv4/IPv6.
