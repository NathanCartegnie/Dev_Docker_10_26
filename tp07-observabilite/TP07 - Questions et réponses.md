# TP07 — Observabilité : Logs, Métriques et Alertes
**Questions & Réponses - Stack Shop SAS**

---

## Étape 1 : Les logs côté Docker

### Q1. Que se passe-t-il **sans** `max-size` sur un serveur qui tourne 6 mois ?

Sans restriction de taille (`max-size`) ni de rotation (`max-file`), Docker enregistre la totalité des flux `stdout` et `stderr` de chaque conteneur dans des fichiers texte non compressés sur le disque hôte (sous `/var/lib/docker/containers/<container-id>/<container-id>-json.log`). 

Au bout de plusieurs mois de fonctionnement continu, le volume cumulé de logs peut atteindre des dizaines ou centaines de gigaoctets, entraînant une **saturation complète du disque hôte (Disk Full)**. Cela provoque le plantage en chaîne des bases de données, l'impossibilité d'écrire des fichiers temporaires, et le blocage complet du système d'exploitation.

---

### Q2. Pourquoi un conteneur doit-il écrire sur `stdout`/`stderr` et pas dans un fichier interne ?

1. **Principe des 12-Factor Apps** : Une application conteneurisée ne doit pas administrer ses propres fichiers de logs. Elle traite les journaux comme un flux continu d'événements à émettre sur la sortie standard (`stdout`) et d'erreurs (`stderr`).
2. **Éphémérité du conteneur** : L'espace de stockage interne d'un conteneur est temporaire. Si le conteneur crash, redémarre ou est mis à jour, les fichiers écrits à l'intérieur sont définitivement perdus.
3. **Découplage et centralisation** : Déléguer l'écriture du flux au moteur Docker permet de centraliser la collecte via des drivers de logs ou des agents externes (Promtail, Fluentbit) vers une stack d'observabilité (ex: Loki, Elasticsearch), sans modifier le code de l'application.

---

### Q3. Différences entre les drivers de logging (`json-file`, `local`, `journald`, `fluentd`, `awslogs`)

| Driver | Fonctionnement & Emplacement | Avantages | Inconvénients / Limites |
| :--- | :--- | :--- | :--- |
| **`json-file`** | Stocke les logs au format JSON dans `/var/lib/docker/containers/`. *(Driver par défaut)* | Nativement compatible avec la commande `docker logs`. Prise en main immédiate. | Risque de saturation disque si aucune stratégie de rotation (`max-size`) n'est définie. |
| **`local`** | Stocke les logs dans un format binaire optimisé propre à Docker. | Rotation automatique activée par défaut. Très performant et économe en espace. | Logs non lisibles directement avec des outils texte Linux classiques (`cat`, `grep`). |
| **`journald`** | Transfère le flux de logs au démon `systemd-journald` de la machine hôte. | Intégration unifiée avec tous les logs système de l'hôte Linux (`journalctl`). | Dépend directement du système d'exploitation hôte Linux (`systemd`). |
| **`fluentd`** | Transmet les flux directement à un collecteur centralisé Fluentd. | Filtrage, découpage et routage avancé multi-destinations. | Si le collecteur Fluentd est indisponible, risque d'impact sur l'application. |
| **`awslogs`** | Envoie le flux directement vers le service Amazon CloudWatch Logs. | Solution nativement intégrée pour les infrastructures hébergées sur AWS. | Génère du trafic réseau sortant et des coûts d'ingestion/stockage AWS. |

---

### Q4. Compromis entre `mode: non-blocking` et `max-buffer-size`

Par défaut, Docker utilise un mode de journalisation **bloquant (`blocking`)** : si le driver de logs ne parvient pas à traiter l'écriture immédiatement, l'application est mise en pause.

* **`mode: non-blocking`** : Le conteneur écrit ses lignes de logs dans un tampon intermédiaire en mémoire RAM au lieu de les envoyer de manière synchrone au driver. Cela garantit que l'application ne subit aucun ralentissement lié à la journalisation.
* **`max-buffer-size`** : Définit la quantité maximale de mémoire allouée à ce tampon circulaire (par exemple `4m` pour 4 Mo).
* **Le compromis** : Si le tampon mémoire devient plein (en cas de pic soudain de trafic ou de lenteur du collecteur de logs), **les logs les plus anciens sont supprimés sans être enregistrés**. On privilégie la disponibilité et la vitesse de réponse de l'application au risque d'une perte ponctuelle de traçabilité.

---

## Étape 3 : Métriques & Découverte Prometheus

### Q5. Pourquoi le job `api` utilise `dns_sd_configs` et pourquoi ne pas utiliser `docker_sd_configs` ?

* **Rôle de `dns_sd_configs`** : Dans un réseau Docker Compose, le nom de service `api` résout dynamiquement vers l'ensemble des adresses IP attribuées aux réplicas actifs du conteneur. Prometheus effectue des requêtes DNS régulières pour découvrir automatiquement tous les pods/conteneurs `api` à scraper, gérant nativement la montée en charge (*scaling*).
* **Pourquoi pas `docker_sd_configs` ?** : Pour utiliser `docker_sd_configs`, Prometheus devrait accéder directement au socket Docker de la machine hôte (`/var/run/docker.sock`).
  1. **Insécurité** : Donner accès au socket Docker équivaut à accorder des privilèges d'administration équivalents au compte `root` sur l'hôte.
  2. **Problème de permissions** : Le conteneur Prometheus s'exécute avec un utilisateur non-root (`nobody`). Monter la socket Docker entraînerait un refus de permission à moins de modifier les droits d'accès système de l'hôte.

---

## Étape 4 : Synthèse des requêtes et métriques d'urgence

* **Filtrer les erreurs critiques API (pino level 50) dans Loki** :
  `{service="api"} | json | level="50"`

* **Filtrer les tâches rejetées du worker dans Loki** :
  `{service="worker"} |= "rejected"`

* **Calculer le taux de requêtes HTTP par seconde par code de statut dans Prometheus (PromQL)** :
  `sum(rate(http_request_duration_seconds_count[1m])) by (status)`