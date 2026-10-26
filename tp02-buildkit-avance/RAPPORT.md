# Rapport TP02
---

## 1. Prouver la fuite de secrets (Étape 1)

L'utilisation d'instructions `ARG` ou du drapeau `--build-arg` pour passer des identifiants (`PIP_INDEX_URL`) expose les secrets à au moins trois endroits :

1. **Historique des couches (`docker history`)** : les instructions `ARG` et les lignes `RUN` qui les consomment sont écrites en clair dans l'historique de l'image.
2. **Métadonnées de l'image (`docker inspect`)** : la section `Config.ArgsEscaped` et les variables d'environnement de build conservent la valeur transmise.
3. **Cache BuildKit / Couches intermédiaires** : les couches intermédiaires créées lors du build restent stockées dans le daemon local et restent accessibles à quiconque interroge le cache.

---

## 2. Secret Mount (Étape 2)

Le mount de type secret (`--mount=type=secret`) permet de monter temporairement un fichier depuis l'hôte dans un système de fichiers en mémoire (**tmpfs**) uniquement pendant l'exécution de la commande `RUN`. Une fois l'instruction terminée, le secret n'existe plus et n'est jamais écrit dans les couches de l'image finale.

### Alternatives
* `--mount=type=ssh` : permet d'utiliser les clés SSH de l'hôte via un agent SSH pour cloner des dépôts Git privés sans jamais embarquer la clé privée dans l'image.
* `--mount=type=secret,id=TOKEN,env=TOKEN` : permet d'injecter une variable d'environnement de build de façon sécurisée sans passer par un fichier physique.

---

## 3. Cache Mount (Étape 3)

### Différence entre cache de couches et cache mount
* **Cache de couches** : réutilise le résultat complet d'une instruction `RUN` si les fichiers sources n'ont pas changé. Si le fichier `requirements.txt` est modifié, toute la couche est invalidée et réexécutée de zéro.
* **Cache mount (`--mount=type=cache`)** : persiste un dossier spécifique (ex: `/root/.cache/pip`) indépendamment de l'invalidation des couches. Même si `requirements.txt` change, `pip` réutilise les packages déjà téléchargés dans le dossier de cache local.

### Comportement avec `--no-cache`
Le drapeau `--no-cache` force l'invalidation de toutes les couches du Dockerfile, mais **ne vide pas** le cache mount. Si un cache mount est déclaré sur un dossier, les données mises en cache y restent disponibles pendant le build.

---

## 4. Multi-architecture (Étape 4)

### Questions & Réponses

* **Pourquoi `--push` ou `-o` est-il obligatoire avec plusieurs plateformes ?**  
  Le moteur Docker traditionnel (Docker Engine local) ne supporte pas le stockage d'images multi-architectures sous le même tag. BuildKit doit donc envoyer le résultat vers un registre distant (`--push`) ou exporter une archive OCI (`-o type=oci,dest=worker.tar`).

* **Que contient le *manifest list* ?**  
  Un *manifest list* (ou index d'images) est un objet JSON qui pointe vers les sous-manifests spécifiques de chaque architecture (`linux/amd64`, `linux/arm64`). Lorsque le client tire l'image, le daemon Docker sélectionne automatiquement le manifest qui correspond à son architecture CPU.

* **Comment utiliser `TARGETARCH` dans le Dockerfile pour isoler le cache pip par architecture ?**  
  On utilise la variable automatique BuildKit `${TARGETARCH}` dans le chemin du cache mount :  
  `RUN --mount=type=cache,target=/root/.cache/pip/${TARGETARCH} ...`

* **Pourquoi le build `arm64` est-il plus lent sur une machine `amd64` (QEMU) et quelle est l'alternative ?**  
  L'émulation matérielle via QEMU traduit chaque instruction CPU au niveau utilisateur, ce qui génère une surcharge importante (3 à 10 fois plus lent).  
  **Alternatives** :
    1. Utiliser des nœuds distants natifs (un builder `amd64` et un builder `arm64`) reliés dans un même instance BuildKit multi-nœuds.
    2. Compiler sur des runners de CI natifs (ex: instances AWS Graviton pour `arm64`).

---

## 5. Cache distant (Étape 5)

### Différence entre `mode=min` et `mode=max`
* `mode=min` (défaut) : exporte uniquement les métadonnées de cache pour l'étape (stage) finale du Dockerfile.
* `mode=max` : exporte les métadonnées de cache pour **tous** les stages intermédiaire (y compris le stage `builder` et `test`), ce qui optimise les builds multi-stage en CI.

---

## 6. Docker Buildx Bake (Étape 6)

Voir le fichier `docker-bake.hcl` joint au dépôt pour l'implémentation complète des cibles et groupes.