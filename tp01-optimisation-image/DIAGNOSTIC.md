# DIAGNOSTIC DOCKER - shopapi:legacy

## 1. TAILLE ET PERFORMANCE

### 1.1 Empreinte disque excessive de l'image
- **Preuve :**
```bash
$ docker image ls shopapi:legacy
REPOSITORY       TAG      IMAGE ID       CREATED        SIZE
shopapi          legacy   87b61be9eb75   12 minutes ago 738MB
```

* **Impact :** Une image de 738 Mo pour une API Node.js ralentit le transfert dans le registre et surcharge le réseau lors des déploiements.

### 1.2 Conservation du cache du gestionnaire de paquets

* **Preuve :**

```bash
$ docker history shopapi:legacy
RUN /bin/sh -c apt-get update # 81.3MB

# Hadolint
Dockerfile:4 DL3009 info: Delete the apt lists (/var/lib/apt/lists) after installing something
```

* **Impact :** Les fichiers d'index d'apt restent stockés dans le layer, gonflant inutilement le poids de l'image de plus de 80 Mo.

### 1.3 Multiplying instructions RUN (Layers superflus)

* **Preuve :**

```bash
# Hadolint
Dockerfile:5 DL3059 info: Multiple consecutive RUN instructions. Consider consolidation.
Dockerfile:8 DL3059 info: Multiple consecutive RUN instructions. Consider consolidation.
```

* **Impact :** L'absence de chaînage des commandes `RUN` génère des couches d'image supplémentaires et dégrade le temps de build.

### 1.4 Présence de dépendances de dev en production

* **Preuve :**

```bash
$ docker history shopapi:legacy
RUN /bin/sh -c npm install -g nodemon # 5.1MB
```

* **Impact :** L'installation de `nodemon` augmente inutilement la surface d'attaque et le poids de l'image pour un environnement de prod.

## 2. SÉCURITÉ

### 2.1 Exécution de l'application en privilèges Root

* **Preuve :**

```bash
$ docker run --rm shopapi:legacy id
uid=0(root) gid=0(root) groups=0(root)
```

* **Impact :** Si l'application subit une RCE, l'attaquant contrôle le conteneur avec les accès utilisateur complets (UID 0), augmentant les risques d'évasion (*container escape*).

### 2.2 Exposition de secrets et chaîne de connexion dans l'environnement

* **Preuve :**

```bash
$ docker run --rm shopapi:legacy env | grep -i database
DATABASE_URL=postgres://shop:S3cret!@db.internal:5432/shop
```

* **Impact :** Le mot de passe de la BDD est écrit en dur dans l'image. Il est lisible par n'importe qui ayant accès à Docker ou à l'historique du conteneur.

### 2.3 Absence de versionning explicite sur les packages

* **Preuve :**

```bash
# Hadolint
Dockerfile:5 DL3008 warning: Pin versions in apt get install. Instead of `apt-get install <package>` use `apt-get install <package>=<version>`
Dockerfile:8 DL3016 warning: Pin versions in npm. Instead of `npm install <package>` use `npm install <package>@<version>`
```

* **Impact :** Instabilité des builds suivants qui risquent d'embarquer des dépendances cassantes ou de nouvelles vulnérabilités non auditées.

### 2.4 Briques de compilation et outils réseau embarqués

* **Preuve :**

```bash
$ docker run --rm shopapi:legacy which curl wget gcc nc
/usr/bin/curl
/usr/bin/wget
/usr/bin/gcc
```

* **Impact :** La présence de `gcc` permet la compilation locale de payloads malveillants, tandis que `curl`/`wget` facilitent le téléversement ou l'exfiltration de données.

## 3. EXPLOITABILITÉ ET MAINTENANCE

### 3.1 Absences de Healthcheck

* **Preuve :**

```bash
$ docker inspect --format='{{json .Config.Healthcheck}}' shopapi:legacy
null
```

* **Impact :** Impossible pour l'orchestrateur de connaître l'état réel du service en cas de freeze de l'application (le conteneur reste taggué "Running").

### 3.2 Fichiers hors scope et données sensibles embarqués (Pas de .dockerignore)

* **Preuve :**

```bash
$ docker run --rm shopapi:legacy ls -la /app
total 140
-rwxr-xr-x 1 root root   183 Oct 26 08:35 .env
-rwxr-xr-x 1 root root    48 Oct 26 08:35 dump-prod-2024.sql
drwxr-xr-x 2 root root  4096 Oct 26 08:36 test
```

* **Impact :** Des secrets locaux (`.env`) et des données métier (`dump-prod-2024.sql`) ont été copiés dans le conteneur via `COPY . /app`, provoquant une fuite de données de production.

