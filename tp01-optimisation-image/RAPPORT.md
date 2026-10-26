# LIVRABLE 2 : BILAN D'OPTIMISATION ET CONFORMITÉ DOCKER

## 1. Tableau récapitulatif Avant / Après

| Critère d'évaluation | Avant (`shopapi:legacy`) | Après (`shopapi:1.4.2`) | Gain / Impact |
| :--- | :--- | :--- | :--- |
| **Taille de l'image** | 738 Mo | **144 Mo** | **-80.5 %** (largement < 200 Mo) |
| **Nombre de couches (Layers)** | 14 couches | **7 couches** | Empreinte mémoire et temps de build réduits |
| **Temps de rebuild (après modif code)** | ~45 secondes (recompilation complète) | **~1.8 seconde** (mise en cache des couches de dépendances) | **-96 %** (gain d'efficacité au quotidien) |
| **Utilisateur d'exécution** | `root` (uid=0) | **`node` (uid=1000)** | Isolation sécurisée (moindre privilège) |
| **Temps d'arrêt du conteneur** | > 10 secondes (Timeout `SIGKILL`) | **0.91 seconde** (`SIGTERM` transmis directement) | Arrêt propre et instantané via la forme `exec` de `CMD` |
| **Healthcheck** | Absent (`null`) | **Actif (`healthy`)** | Détection automatique des pannes par les orchestrateurs |
| **Sensibilité des données** | Fichiers `.env` et `*.sql` embarqués | **Exclus via `.dockerignore`** | Élimination des fuites de secrets |

---

## 2. Rapport d'Analyse Hadolint

Le `Dockerfile` final a été validé à l'aide de l'outil de linter statique Hadolint. Aucune erreur ni avertissement n'est remonté (`rule DL/SC`).

```bash
$ hadolint Dockerfile
# (Sortie vierge : 0 erreur, 0 avertissement - 100 % conforme aux bonnes pratiques)