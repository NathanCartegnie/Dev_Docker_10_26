# TP05 — Questions et réponses

Nathan Cartegnie — M1 Ynov Campus Lille — Docker, Shop SAS

## Étape 1 — Anatomie du stockage

**Où sont écrites les données de la writable layer et celles du volume ?**

Le volume `shopdata_pgdata` est monté sur `/var/lib/postgresql/data`. Il est stocké dans `/var/lib/docker/volumes/shopdata_pgdata/_data`, donc dans la VM de Docker Desktop et pas dans Windows. Pour la writable layer, j'ai créé `/tmp/x` dans le conteneur, et `docker diff` donne :

```
C /run
C /run/postgresql
A /run/postgresql/.s.PGSQL.5432
A /run/postgresql/.s.PGSQL.5432.lock
C /tmp
A /tmp/x
```

`/tmp/x` vit dans la couche du conteneur et part avec lui. Rien de `/var/lib/postgresql/data` n'apparaît dans le diff : les données de la base sont dans le volume et lui survivent.

**Que devient `pgdata` avec `down`, `down -v`, `rm` et `volume prune` ?**

J'ai testé sur une copie jetable (projet `essai`) :

| Commande | Résultat | Volume |
|---|---|---|
| `down` | conteneur et réseau supprimés ; après `up`, `SELECT * FROM t` renvoie bien 42 | conservé |
| `stop` puis `rm -f -v` | conteneur supprimé (`-v` ne touche que les volumes anonymes) | conservé |
| `volume prune -f` | `Total reclaimed space: 0B` | conservé |
| `volume prune -a -f` | `Deleted Volumes: essai_pgdata, vide` (52,18 MB) | supprimé |
| `down -v` | `Volume essai_pgdata Removed` | supprimé |

Le volume ne disparaît donc qu'avec `down -v` ou `prune -a`. Ce dernier supprime tout volume nommé qu'aucun conteneur n'utilise, même celui d'un autre projet : ici, le filtre par label l'a limité à `essai`.

**Volume anonyme : où sont les données, que devient le volume avec `docker rm` puis `docker rm -v`, et pourquoi est-ce un piège ?**

Sans `-v`, l'image `postgres` crée un volume anonyme, car elle déclare `VOLUME /var/lib/postgresql/data`. `docker inspect anon` donne un nom de 64 caractères (`222896e5…`) et la source `/var/lib/docker/volumes/222896e5…/_data`.

Après `docker rm -f anon`, le volume reste, orphelin, dans `docker volume ls --filter dangling=true`. Avec `docker rm -fv anon` sur un second conteneur, il est supprimé avec lui.

Le piège : le nom est illisible, les orphelins s'accumulent, on perd la trace de ce qu'ils contiennent, et `rm -v` ou `prune` les détruit sans prévenir. Sur ma machine, la liste `dangling` contenait aussi `mysql-data` et `kennel-data`, que `docker volume prune -a` aurait emportés. On nomme donc toujours les volumes qui contiennent des données.

**Bind mount, volume nommé, tmpfs : quand utiliser chacun, et quelles performances sur Docker Desktop ?**

- **Volume nommé** : pour les données persistantes (une base). Il est géré par Docker, vit dans le système de fichiers de la VM Linux et a donc des performances natives.
- **Bind mount** : pour partager un fichier de l'hôte (code en dev, `init.sql`, config). Sur Docker Desktop il traverse le partage de fichiers hôte/VM, nettement plus lent, avec des soucis de permissions et de `fsync`. Je l'éviterais pour `pgdata`.
- **tmpfs** : en mémoire, perdu à l'arrêt. Pratique pour des secrets temporaires, un cache, ou une base jetable en test.

**Pourquoi `db/init.sql` n'est-il pas rejoué au redémarrage, et comment forcer une ré-initialisation ?**

Après `docker compose restart db`, les logs affichent :

```
PostgreSQL Database directory appears to contain a database; Skipping initialization
```

L'image n'exécute `/docker-entrypoint-initdb.d/*` que si le répertoire de données est vide. Pour forcer, on supprime le volume (`docker compose down -v`, destructif) ou on rejoue le script à la main : `Get-Content db\init.sql | docker compose exec -T db psql -U shop -d shop`.

## Étape 2 — Sauvegarde et restauration

**Dans quel cas la sauvegarde brute est-elle incohérente, et comment la rendre cohérente ?**

Quand PostgreSQL tourne pendant le `tar` : les fichiers sont copiés à des instants différents, une page peut être écrite à moitié, et les fichiers de données ne correspondent plus au WAL. Au redémarrage, la base peut refuser de démarrer, ou pire, être corrompue sans le dire.

Pour la rendre cohérente, trois options :

1. arrêter proprement la base pendant la copie, c'est ce que fait mon `backup.sh` (stop, tar, start) ;
2. faire une sauvegarde en ligne avec `pg_start_backup` / `pg_stop_backup` en PG14 (devenues `pg_backup_start` / `pg_backup_stop` en PG15) plus les WAL archivés, ou plus simplement `pg_basebackup` ;
3. prendre un snapshot atomique du système de fichiers.

Pour le sidecar planifié (`compose.backup.yml`, `@every 1m`), un dump `shop-20261030-085521.sql.gz` est bien apparu dans `/backups/last` après 75 s, et les logs se terminent par `SQL backup created successfully`.

**Preuve de restauration.** J'ai rempli la base avec `seed.sql`, lancé `backup.sh`, puis `docker compose down -v` et recréé la stack à vide avant `restore.sh`. Le checksum est identique avant et après : `200000|77764967b7ab7e303e34786fe85a6ebc`. J'ai 200 000 commandes au lieu de 100 000 parce que le seed a été joué deux fois, ce qui ne change rien à la preuve.

## Étape 3 — Montée de version PostgreSQL 14 → 16

**Pourquoi changer le tag en `16` ne marche pas ?**

Le conteneur démarre puis s'arrête, et les logs disent :

```
FATAL:  database files are incompatible with server
DETAIL:  The data directory was initialized by PostgreSQL version 14, which is not compatible with this version 16.4.
```

Le format des fichiers de données change à chaque version majeure, donc un PG16 ne sait pas lire un répertoire PG14. Seules les versions mineures (14.x) partagent le même format. Il faut passer par un export/import, ou par `pg_upgrade`.

**Quelle différence entre `pg_dumpall` et `pg_dump` ?**

`pg_dump` exporte une seule base, avec plusieurs formats et une restauration sélective ou parallèle via `pg_restore`. `pg_dumpall` exporte tout le cluster, y compris les rôles et les tablespaces, mais seulement en SQL texte. Dans `upgrade-pg.sh`, `pg_dump -Fc` sert à restaurer et `pg_dumpall` de filet de sécurité.

**Pourquoi un nouveau volume plutôt qu'écraser l'ancien ?**

L'ancien volume reste intact, donc le retour arrière est immédiat : on relance `compose.yml` seul et on retrouve PG14. Si on écrase et que la restauration échoue à mi-chemin, il ne reste ni PG14 ni PG16. De plus, PG16 doit démarrer sur un répertoire vide pour faire son `initdb`. Seules les écritures faites sur PG16 après la migration sont perdues au retour arrière.

**Comment réduire le temps d'indisponibilité ?**

Avec dump/restore, le service est coupé pendant tout l'export et l'import, donc plus la base est grosse, plus c'est long. Deux pistes :

- `pg_upgrade --link` : liens physiques, quelques secondes quelle que soit la taille, dans un conteneur qui a les deux jeux de binaires (par exemple `tianon/postgres-upgrade:14-to-16`) ;
- la réplication logique de PG14 vers PG16, puis bascule des applications : quelques secondes de coupure.

Dans tous les cas, on garde une sauvegarde avant de commencer.

**Preuve de la montée de version.** `upgrade-pg.sh` a fait passer la base de PostgreSQL 14.13 à 16.4 sur le nouveau volume `shopdata_pgdata16`. Verdict : OK, même checksum avant et après (`200000|77764967b7ab7e303e34786fe85a6ebc`). Les deux dumps (`pg_dumpall` 9,9 Mo, `pg_dump -Fc` 3,1 Mo) sont dans `backups/`.

## Étape 4 — Redis

**`--save 60 1` ou `--appendonly yes` : quelle perte maximale dans chaque cas ?**

- `--save 60 1` : un snapshot si au moins une écriture en 60 s, donc jusqu'à environ 60 s de données perdues (plus si le crash tombe pendant un snapshot).
- `--appendonly yes` : journal AOF avec `appendfsync everysec` par défaut, donc environ 1 s perdue. Avec `always`, presque rien, mais c'est plus lent.

J'ai écrit une clé `k`, attendu 3 s, puis fait un `docker kill` (SIGKILL, car `docker stop` ferait d'abord une sauvegarde) :

```
r_rdb ->
r_aof -> v
```

La clé est perdue avec RDB (pas encore de snapshot) et conservée avec AOF.

**Que contient Redis dans notre stack (cache + file) et quel niveau de persistance est justifié ?**

Ma proposition : le cache n'a pas besoin de persistance, il se reconstruit. La file contient des tâches qu'on ne veut pas perdre, donc `--appendonly yes` en `everysec`, avec un volume nommé sur `/data`. Perdre une seconde de messages est acceptable si les consommateurs sont idempotents ; sinon, `appendfsync always`.
