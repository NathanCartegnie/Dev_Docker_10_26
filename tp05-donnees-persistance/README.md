# TP05 — Données : persistance, sauvegarde, restauration, montée de version


## Contexte

L'incident du mois dernier chez *Shop SAS* : un `docker compose down -v` lancé « pour nettoyer » sur le
serveur de préprod a effacé la base. Aucune sauvegarde testée n'existait. La DSI exige désormais :

1. de **comprendre précisément** où vivent les données de chaque conteneur ;
2. une **procédure de sauvegarde/restauration** scriptée et **testée** (une sauvegarde non restaurée n'existe pas) ;
3. la **montée de version majeure** PostgreSQL 14 → 16 sur la base legacy, **sans perte** et avec retour arrière possible.

## Étapes

### 1. Anatomie du stockage 

Avec la stack du TP04 démarrée :

```bash
docker inspect $(docker compose ps -q db) --format '{{json .Mounts}}' | jq
docker volume inspect shop_pgdata
docker system df -v | head -40
```

Répondez, preuves à l'appui :

- Où sont écrites les données des couches du conteneur (writable layer) vs du volume ? Montrez avec
  `docker exec db touch /tmp/x` puis `docker diff`.
- Que se passe-t-il pour `pgdata` lors de `docker compose down` ? `down -v` ? `docker compose rm` ?
  `docker volume prune` ? Testez chaque cas (sur une copie de la stack !).
- Volume **anonyme** : lancez `docker run -d postgres:16-alpine` sans `-v`. Où sont les données ? Que
  devient le volume au `docker rm` ? Et avec `docker rm -v` ? Pourquoi est-ce un piège classique ?
- Bind mount vs volume nommé vs `tmpfs` : quand utiliser chacun ? Performances sur Docker Desktop (macOS/Windows) ?
- Pourquoi `db/init.sql` n'est-il **pas rejoué** au redémarrage ? Comment forcer une ré-initialisation ?

### 2. Sauvegarde et restauration 

Écrivez `backup.sh` (sans client `psql` sur l'hôte : tout via conteneurs) :

- dump logique `pg_dump -Fc` horodaté ;
- sauvegarde **brute** du volume via un conteneur `alpine` + `tar` (`-v vol:/data:ro`). Dans quel cas la
  sauvegarde brute est-elle incohérente ? Comment la rendre cohérente (arrêt, `pg_backup_start`) ?
- rétention des 7 derniers.

Écrivez `restore.sh` et **prouvez** la restauration : seedez (`starter/seed.sh`, ≈ 100 000 lignes), notez
le checksum affiché, sauvegardez, détruisez (`down -v`), recréez, restaurez, comparez le checksum.

Ajoutez à la stack du TP04 un sidecar de sauvegarde planifiée (`compose.backup.yml`,
image `prodrigestivill/postgres-backup-local`) : vérifiez qu'un dump apparaît (`SCHEDULE: "@every 1m"` pour le test).

### 3. Montée de version majeure PostgreSQL 

`starter/compose.yml` fait tourner PostgreSQL 14. Changer simplement le tag en `16` ne marche pas : constatez-le
(`docker compose up` → lisez l'erreur dans les logs). Pourquoi ?

Écrivez `upgrade-pg.sh` : checksum avant → `pg_dumpall` + `pg_dump -Fc` → arrêt PG14 (volume conservé) →
PG16 sur **nouveau volume** → `pg_restore` → checksum après → verdict. Documentez le retour arrière.

Questions : différence `pg_dumpall` / `pg_dump` ? Pourquoi un **nouveau** volume plutôt qu'écraser ?
Temps d'indisponibilité : comment le réduire (réplication logique, `pg_upgrade --link` dans un conteneur
contenant les deux binaires, ex. `tianon/postgres-upgrade`) ?

### 4. Redis 

`redis-server --save 60 1` vs `--appendonly yes` : quelle perte maximale de données dans chaque cas ?
Dans notre stack, que contient Redis (cache + file) et quel niveau de persistance est justifié ?

> **Livrables** : réponses de l'étape 1 avec preuves, `backup.sh`, `restore.sh`, `upgrade-pg.sh`,
> transcript (copie du terminal) de la restauration et de la montée de version avec les checksums.

---

## Réalisation — étapes 1 et 2

Les commandes destructives ci-dessous ciblent le projet isolé `shopdata-tp05`, pas la base du TP04
(`shop_pgdata`). Depuis la racine `tp05-donnees-persistance`, les scripts utilisent par défaut
`starter/compose.yml` et ce nom de projet. Le TP04 reste démarré et ses données ne sont pas modifiées.

### Étape 1 — Anatomie du stockage

Sur la stack TP04 démarrée, l'inspection de `shop-db-1` montre trois montages :

| Destination dans le conteneur | Type | Source / rôle |
|---|---|---|
| `/var/lib/postgresql/data` | volume nommé | `shop_pgdata`, données PostgreSQL persistantes |
| `/docker-entrypoint-initdb.d/001-init.sql` | bind mount en lecture seule | `db/init.sql` du TP04, script d'initialisation |
| `/run/secrets/db_password` | bind mount géré par Compose | fichier secret local, lecture seule |

`docker volume inspect shop_pgdata` confirme le nom du volume et le pilote `local`. Les données écrites
dans la couche inscriptible du conteneur ne sont pas dans ce volume. Preuve faite sur le conteneur DB :

```text
$ docker exec shop-db-1 touch /tmp/tp05-layer-check
$ docker diff shop-db-1
A /tmp/tp05-layer-check
```

Le préfixe `A` signifie que ce fichier a été ajouté dans la couche inscriptible du conteneur. En revanche,
les fichiers sous `/var/lib/postgresql/data` sont stockés dans `shop_pgdata`, indépendamment de la durée
de vie du conteneur. `docker system df -v` permet de voir ce volume référencé et sa taille.

Comportement des commandes Compose/Docker pour une copie de TP isolée :

| Opération | Conteneur | Volume nommé Compose |
|---|---|---|
| `docker compose down` | supprimé | conservé |
| `docker compose rm -f db` | conteneur arrêté supprimé | conservé |
| `docker compose down -v` | supprimé | supprimé |
| `docker volume prune` | sans effet direct | supprime les volumes anonymes inutilisés ; `docker volume prune -a` inclut aussi les volumes nommés inutilisés |

Ne lancez pas `docker volume prune` sur un hôte partagé pour ce TP : la commande n'est pas limitée au
projet Compose. Les essais de suppression de données sont effectués sur le projet jetable
`shopdata-tp05` décrit à l'étape 2, jamais sur `shop_pgdata`.

Un conteneur `postgres` crée un volume **anonyme** même si `-v` n'est pas fourni, car son image déclare
`VOLUME /var/lib/postgresql/data`. `docker rm` laisse ce volume anonyme orphelin ; `docker rm -v`
supprime le volume anonyme associé. C'est un piège car les données ne sont ni dans le conteneur ni dans
un volume nommé facile à retrouver, et le conteneur supprimé ne fournit plus son identifiant.

* **Bind mount** : fichiers du poste à éditer/partager (code source, scripts d'initialisation).
* **Volume nommé** : données persistantes gérées par Docker (PostgreSQL, Redis), sans dépendre du chemin du poste.
* **tmpfs** : données temporaires en mémoire, non persistantes après arrêt ; utile pour secrets temporaires ou fichiers éphémères.
* Sur Docker Desktop Windows/macOS, les bind mounts traversent la frontière hôte/VM et peuvent être moins performants pour de nombreux petits fichiers. Les volumes nommés restent dans la VM Linux et sont généralement préférables pour les bases.

`db/init.sql` est monté dans le répertoire d'initialisation de l'image officielle PostgreSQL. Ces scripts ne
sont exécutés que lorsque le répertoire de données est vide, pas à chaque redémarrage. Pour le rejouer,
arrêtez la copie isolée puis supprimez son volume avec `docker compose down -v` avant de recréer la base ;
cela détruit toutes les données de ce volume.

### Étape 2 — Sauvegarde et restauration

Les scripts `backup.sh` et `restore.sh` n'installent pas de client PostgreSQL sur l'hôte. Le dump logique
`pg_dump -Fc` est exécuté dans le conteneur `db`. La copie brute utilise `alpine:3.20` pour archiver le
volume monté en lecture seule. Pour qu'elle soit cohérente, `backup.sh` arrête brièvement PostgreSQL avant
le `tar`, puis le redémarre avec attente de santé. Copier à chaud le répertoire de données avec `tar`
seul peut capturer des fichiers à des moments différents et donner une sauvegarde incohérente. L'autre
méthode consiste à encadrer la copie avec les fonctions de sauvegarde physique PostgreSQL (`pg_backup_start`
et `pg_backup_stop`) et à conserver les WAL requis.

Lancement du test de restauration sur une base isolée (Bash, WSL ou Git Bash avec Docker disponible) :

```bash
cd tp05-donnees-persistance
export TP05_PROJECT=shopdata-tp05
docker compose -p "$TP05_PROJECT" -f starter/compose.yml up -d --wait
(cd starter && bash ./seed.sh)
docker compose -p "$TP05_PROJECT" -f starter/compose.yml exec -T db \
  psql -U shop -d shop -Atc \
  "SELECT count(*) || '|' || md5(string_agg(id::text || status, ',' ORDER BY id)) FROM orders"
./backup.sh
docker compose -p "$TP05_PROJECT" -f starter/compose.yml down -v
./restore.sh backups/shop_<horodatage>.dump
docker compose -p "$TP05_PROJECT" -f starter/compose.yml exec -T db \
  psql -U shop -d shop -Atc \
  "SELECT count(*) || '|' || md5(string_agg(id::text || status, ',' ORDER BY id)) FROM orders"
```

Remplacez `<horodatage>` par le suffixe affiché par `backup.sh`. Les deux lignes de checksum doivent
être identiques et commencer par `100000|`. `restore.sh` démarre une base vide si besoin et restaure le
dump logique. Le script conserve au plus sept dumps logiques et les archives brutes correspondantes.

Le sidecar pour la stack TP04 est fourni dans `tp04-compose-entreprise/compose.backup.yml`. Il lit le même
secret Compose que PostgreSQL (`POSTGRES_PASSWORD_FILE`), écrit dans le volume nommé `shop_backups` et
planifie un dump toutes les minutes pour le test :

```bash
cd tp04-compose-entreprise
docker compose -f compose.yml -f compose.override.yml -f compose.backup.yml config
docker compose -f compose.yml -f compose.override.yml -f compose.backup.yml \
  up -d --wait pg-backup
docker compose -f compose.yml -f compose.override.yml -f compose.backup.yml \
  exec pg-backup ls -R /backups
```

Après vérification, retirez seulement le service de sauvegarde sans supprimer le volume de sauvegardes :

```bash
docker compose -f compose.yml -f compose.override.yml -f compose.backup.yml stop pg-backup
docker compose -f compose.yml -f compose.override.yml -f compose.backup.yml rm -f pg-backup
```

Le sidecar est réseau uniquement sur `back` et ne publie aucun port. Pour un déploiement durable,
remplacez le test `@every 1m` par un horaire adapté et exportez les sauvegardes hors de la machine :
un volume local ne protège pas contre la perte de l'hôte ou du disque.

## Bonus

- **B1** : testez `pg_upgrade --link` avec `tianon/postgres-upgrade:14-to-16` et comparez la durée.
- **B2** : chiffrez le dump (`age` ou `gpg`) et poussez-le vers un bucket S3 compatible (MinIO en conteneur).
- **B3** : volume sur un driver distant : NFS (`driver_opts: type: nfs`) ou un plugin (rexray, local-persist).
  Qu'est-ce qui change pour la sauvegarde et la haute disponibilité ?
- **B4** : *Point-in-time recovery* : archivage WAL vers un volume et restauration à T-5 min.
