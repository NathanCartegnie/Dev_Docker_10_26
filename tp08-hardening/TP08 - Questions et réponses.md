# TP08 — Durcir les conteneurs pour la production

**Rapport de synthèse - Stack Shop SAS**

---

## 1. Tableau des Expériences (Comprendre chaque mesure)

| Mesure | Commande d'expérience | Résultat observé | Explication technique | 
| ----- | ----- | ----- | ----- | 
| **`--read-only`** | `docker run --rm --read-only alpine touch /x` | `touch: /x: Read-only file system` | Empêche toute modification du système de fichiers root. On utilise `--tmpfs /tmp` pour autoriser les écritures éphémères nécessaires. | 
| **`--cap-drop ALL`** | `docker run --rm --cap-drop=ALL alpine ping 1.1.1.1` | `ping: socket: Operation not permitted` | Supprime tous les privilèges noyau Linux du conteneur. Pour refaire fonctionner `ping`, il faut ajouter `--cap-add NET_RAW`. Pour `chown`, `--cap-add CHOWN`. | 
| **`--security-opt no-new-privileges`** | `docker run --rm --security-opt no-new-privileges:true alpine passwd` | L'élévation de privilèges échoue | Interdit aux exécutables possédant les bits SetUID/SetGID d'augmenter les privilèges du processus (empêche l'escalade de privilèges). | 
| **`--pids-limit 50`** | `docker run --rm --pids-limit 50 alpine sh -c 'for i in $(seq 100); do sleep 60 & done'` | `sh: can't fork: Resource temporarily unavailable` | Limite le nombre maximal de processus utilisables par le conteneur, protégeant l'hôte contre les attaques de type Fork Bomb. | 
| **`--memory 32m`** | `docker run --rm --memory 32m python:alpine python -c "x='a'*100_000_000"` | `Killed` (Code retour 137, `OOMKilled: true`) | Limite la consommation RAM. Si le conteneur dépasse sa limite, le gestionnaire OOM (Out Of Memory) du noyau Linux le stoppe net. | 
| **`--user 1000`** | `docker run --rm --user 1000 alpine id` | `uid=1000 gid=1000` | Exécute l'application avec un utilisateur non-root. Si un volume est monté, cet UID doit avoir les droits d'accès sur le dossier hôte. | 
| **`seccomp`** | `docker run --rm alpine unshare --user` vs `--security-opt seccomp=unconfined` | `unshare: Operation not permitted` (bloqué par défaut) | Le profil seccomp par défaut de Docker filtre et interdit environ 44 appels système (*syscalls*) dangereux sur les ~300+ existants sous Linux. | 

---

## 2. Justification des directives du `starter/compose.hardened.yml`

* **`socket-proxy` (`tecnativa/docker-socket-proxy`)** : Traefik n'a plus accès direct au socket Docker de l'hôte (`/var/run/docker.sock`). Le proxy est exposé uniquement sur un réseau `internal` sans accès internet et n'autorise que les requêtes en lecture seule pour lister les conteneurs (`CONTAINERS: 1`).
* **`cap_add: [NET_BIND_SERVICE]` (Traefik)** : Nécessaire pour permettre à Traefik de s'écouter sur les ports privilégiés inférieurs à 1024 (`80` et `443`) tout en ayant supprimé toutes les autres *capabilities* (`cap_drop: [ALL]`).
* **`cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID]` (PostgreSQL `db`)** : Nécessaires pour le démarrage de PostgreSQL qui modifie le propriétaire des fichiers de données au boot et ajuste ses permissions de processus.
* **`user: "1000:1000"` (API & Worker)** : Force l'exécution sous un compte non-privilégié.
* **`read_only: true` + `tmpfs: [/tmp]`** : Verrouille l'image système en lecture seule tout en fournissant un répertoire `/tmp` temporaire en RAM pour les fichiers volatiles.

---

## 3. Réponses aux questions Côté Démon (`starter/daemon.json`)

### Q1. Effets de bord de `icc: false`
* **Fonctionnement** : Empêche la communication directe entre conteneurs sur le réseau `bridge` par défaut.
* **Impact sur la stack** : Aucun impact sur `docker compose`, car Compose crée ses propres réseaux dédiés (*user-defined bridge networks*) sur lesquels l'isolation et la résolution DNS interne restent pleinement fonctionnelles.

### Q2. Effets de bord de `userns-remap` sur les volumes
* **Fonctionnement** : Mappe l'utilisateur `root` (UID 0) du conteneur sur un utilisateur non-privilégié non-root de l'hôte (ex: UID 100000).
* **Impact sur les volumes** : Les fichiers existants créés sur l'hôte avant l'activation appartiennent à l'UID d'origine (ex: UID 0 ou 1000) et deviennent inaccessibles pour le conteneur remappé. Il est nécessaire d'exécuter un `chown -R 100000:100000` sur les répertoires de volumes hôte pour rétablir les accès.