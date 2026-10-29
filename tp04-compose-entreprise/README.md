# TP04 — Une stack Compose d'entreprise : du poste du dev à la prod


## Contexte

La stack *Shop SAS* (API, worker, PostgreSQL, Redis) est aujourd'hui décrite par un `docker-compose.yml`
« qui marche sur le poste du dev » (`starter/`). On vous demande d'en faire la **référence d'exécution**
utilisée à la fois par les développeurs, la CI (TP09) et le serveur de prod. Exigences de l'équipe :

- un **même fichier de base** pour tous les environnements, avec des surcharges dev et prod ;
- **zéro secret en clair** dans les fichiers versionnés ;
- la base et Redis **inaccessibles depuis l'extérieur et depuis Internet** ; seul le reverse proxy expose le port 80 ;
- un démarrage **ordonné et fiable** (pas de `sleep 10`), des healthchecks partout, `docker compose up --wait` qui ne rend la main qu'avec une stack saine ;
- des outils (admin BDD, migrations) disponibles **à la demande** sans tourner en permanence ;
- en prod : limites de ressources, rotation des logs, redémarrage automatique, plusieurs réplicas de l'API derrière le proxy.

## Étapes

### 1. Critique du compose existant 

Listez les problèmes de `starter/docker-compose.yml` (au moins 8). Indices : `version`, `links`,
images non épinglées, ports exposés, mots de passe, `sleep`, réseau unique, pas de healthcheck,
pas de volumes nommés, `restart` incohérent, pas de limites.

### 2. Fichier de base `compose.yml` 

- `name: shop` (nom de projet stable, indépendant du dossier) ;
- deux réseaux : `front` (proxy ↔ api) et `back` (`internal: true` : api/worker ↔ db/redis) ;
- images épinglées (`postgres:16.4-alpine`, `redis:7.4-alpine`, `traefik:v3.1`) ;
- **healthchecks** sur tous les services, factorisés via une **ancre YAML** (`x-healthcheck-defaults`) ;
- `depends_on` avec `condition: service_healthy` ;
- mot de passe PostgreSQL via **`secrets:`** (fichier `./secrets/db_password.txt` gitignored),
  `POSTGRES_PASSWORD_FILE` côté base. Côté API et worker, l'application ne lit que `DATABASE_URL` :
  trouvez un moyen de construire cette URL à partir du secret **sans modifier le code** ;
- volumes nommés `pgdata`, `redisdata`, script d'initialisation `db/init.sql` ;
- reverse proxy **Traefik** piloté par labels : `api.localhost` → API, healthcheck de backend ;
- rotation des logs (`x-logging`), `restart: unless-stopped` ;
- profils : `tools` (adminer sur `adminer.localhost`) et `ops` (service `migrate` à usage unique :
  `MIGRATION=002-add-sku.sql docker compose run --rm migrate`).

Vérifiez avec `docker compose config` (le fichier résolu) et `docker compose up -d --wait && docker compose ps`.

### 3. Surcharge dev `compose.override.yml` 

Appliquée automatiquement : bind mount du code source avec rechargement (`node --watch`), ports de
debug (3000, 5432, dashboard Traefik 8080), `LOG_LEVEL=debug`. Modifiez `server.js`, observez le reload.

### 4. Surcharge prod `compose.prod.yml` 

`docker compose -f compose.yml -f compose.prod.yml config` puis `up -d --wait` :

- pas de `build` (images tirées du registre du TP03 : `REGISTRY`/`VERSION` depuis `.env`) — cherchez
  comment **supprimer** une clé héritée (`!reset`) ;
- `deploy.replicas: 2` pour l'API : vérifiez avec `docker compose ps` et plusieurs `curl` que Traefik
  répartit la charge (ajoutez l'`id` du conteneur dans la réponse ? non : regardez les logs d'accès) ;
- limites CPU/mémoire, `read_only: true` + `tmpfs`, `cap_drop: [ALL]`, `no-new-privileges` ;
- aucun port de debug, pas de dashboard.

Testez `docker compose up -d --scale api=3` puis `docker compose up -d` : que se passe-t-il ?

### 5. Outillage d'équipe 

`Makefile` (ou `justfile`) : `make up`, `make prod-up`, `make migrate M=002-add-sku.sql`, `make test`
(script `smoke-test.sh` : `/ready`, `/products` avec cache HIT, création d'une commande, vérification
qu'elle est passée `confirmed` par le worker).

> **Livrables** : `compose.yml`, `compose.override.yml`, `compose.prod.yml`, `.env.example`, `Makefile`,
> `smoke-test.sh`, et la liste de l'étape 1.

## Bonus

- **B1** : `docker compose watch` (section `develop.watch`) à la place du bind mount : `sync` vs `rebuild`.
- **B2** : TLS local sur Traefik avec `mkcert` et redirection 80 → 443.
- **B3** : `docker compose --profile tools up` lance adminer sur le réseau `back` qui est `internal` :
  adminer peut-il quand même être joint via Traefik ? Pourquoi (deux réseaux) ?
- **B4** : variables obligatoires : `${REGISTRY:?REGISTRY doit être défini}` en prod. Testez l'erreur.
- **B5** : `docker compose alpha publish` / `include:` pour découper le compose en plusieurs fichiers partagés entre équipes.

---

## Réalisation

### 1. Critique du compose de départ

1. `version: '3'` est obsolète avec Compose moderne et n'apporte plus de compatibilité utile.
2. `postgres` et `redis` ne sont pas épinglés : un rebuild peut tirer une version différente.
3. La base et Redis publient leurs ports sur l'hôte, donc ne sont pas confinés au réseau Docker.
4. Le mot de passe PostgreSQL `postgres` est faible et écrit en clair dans le compose.
5. `DATABASE_URL` contient aussi des identifiants en clair et est incohérente avec `POSTGRES_PASSWORD`.
6. `links` est ancien, redondant avec le DNS de Compose et ne garantit pas la disponibilité des dépendances.
7. `sleep 10` est une attente arbitraire : elle ne vérifie ni la santé de PostgreSQL ni celle de Redis.
8. Aucun service n'a de healthcheck, donc `depends_on` ne peut pas ordonner un démarrage sain.
9. Tous les services partagent le même réseau, sans frontière entre trafic public et données internes.
10. Les données ne sont pas conservées dans des volumes nommés.
11. L'API est reconstruite implicitement sans image/tag explicite ; les images de base ne sont pas verrouillées.
12. Les politiques de redémarrage sont absentes pour la plupart des services et `always` n'est pas cohérent avec un arrêt volontaire.
13. Il n'y a ni limites CPU/mémoire, ni rotation des logs, ni séparation entre outils ponctuels et services permanents.
14. L'API expose directement son port au lieu de passer par un reverse proxy.

### 2. Utilisation

Les sources de l'API et du worker sont incluses dans `apps/`. Créez le secret local (ignoré par Git) avant
le premier démarrage :

```sh
mkdir -p secrets
openssl rand -hex 32 > secrets/db_password.txt
docker compose config
docker compose up -d --build --wait
docker compose ps
make test
```

Le fichier secret n'est jamais interpolé par Compose : l'API et le worker construisent leur `DATABASE_URL`
à l'exécution en lisant `/run/secrets/db_password`. L'initialisation SQL est exécutée seulement lors de la
création initiale du volume `pgdata`. Pour une migration ultérieure :

```sh
MIGRATION=002-add-sku.sql docker compose run --rm migrate
# ou : make migrate M=002-add-sku.sql
```

`docker compose --profile tools up -d` ajoute Adminer sur `http://adminer.localhost`. Adminer est joint à
`front` et `back` : Traefik le contacte sur `front`, tandis qu'Adminer atteint PostgreSQL sur `back`,
même si `back` est `internal`.

L'override automatique active `node --watch`, monte `apps/shopapi/src`, et publie les ports de
développement (API 3000, PostgreSQL 5432, dashboard Traefik 8080). Modifiez `apps/shopapi/src/server.js`
pour observer le rechargement. Si l'UI du registre TP03 utilise déjà le port 8080, arrêtez-la avant
de démarrer TP04 :

```powershell
docker stop registry-ui-1
docker compose up -d --build --wait
```

Le proxy TP04 occupe ensuite le port 8080. Après les tests, libérez-le avant de relancer le registre :

```powershell
docker compose down
docker start registry-ui-1
```

Ces ports de développement ne sont pas publiés par la configuration de production ; son dashboard
Traefik est désactivé.

Avec Docker Engine 29, l'API minimale annoncée par le daemon est 1.40, alors que Traefik `v3.1` demande
l'API 1.24. Dans cet environnement, le provider Docker de Traefik est donc refusé par le daemon et les
requêtes à `api.localhost` reçoivent une 404. Pour tester le routage avec cette version du TP, utilisez un
moteur Docker compatible avec l'API 1.24 ou une version Traefik dont le client négocie une API récente ;
le test applicatif peut être lancé indépendamment avec `API_URL=http://localhost:3000 make test`.

Pour la production, copiez `.env.example` en `.env`, renseignez les références d'images disponibles dans
le registre, puis lancez :

```sh
docker compose -f compose.yml -f compose.prod.yml config
docker compose -f compose.yml -f compose.prod.yml up -d --wait
docker compose -f compose.yml -f compose.prod.yml ps
```

Le fichier de production supprime les options `build` héritées avec `!reset`, impose les images du registre,
et configure deux réplicas API. Vérifiez la répartition avec plusieurs requêtes sur
`http://api.localhost`, puis consultez `docker compose -f compose.yml -f compose.prod.yml logs proxy` :
les access logs JSON montrent les requêtes traitées par Traefik. `--scale api=3` remplace temporairement
le nombre de réplicas demandé ; un `up -d` ultérieur sans `--scale` revient à `deploy.replicas: 2`.

Le proxy est le seul service exposé sur le port 80 en configuration de base et en production. Le réseau
`back` est interne ; en développement, PostgreSQL est volontairement publié sur `5432` pour le TP.
