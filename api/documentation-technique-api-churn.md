# Documentation technique — API de scoring Churn (XGBoost + Plumber)

**Auteur du code source :** @Madiba
**Stack :** R 4.4 · Plumber · XGBoost · Recipes
**Version API :** 1.2.0 (*Secure Demo*)

---

## 1. Objectif de l'API

L'API expose un modèle XGBoost entraîné pour prédire la probabilité de résiliation (*churn*) d'un client télécom, à partir de ses caractéristiques contractuelles et d'usage. Elle prend en charge le prétraitement (normalisation), la validation d'entrée, l'inférence, et retourne une décision binaire selon un seuil optimal pré-calculé.

---

## 2. Architecture générale

```
Client (Shiny / Postman / autre) 
        │  JSON (array d'objets)
        ▼
   Filtre CORS
        │
        ▼
   Endpoint /predict
        │
        ├─► Parsing JSON
        ├─► Validation de présence des colonnes obligatoires
        ├─► Validation des bornes métier (tenure, MonthlyCharges ≥ 0)
        ├─► bake() — application de la recette de normalisation
        ├─► Complétion des colonnes manquantes (valeur 0)
        ├─► predict() — inférence XGBoost
        └─► Application du seuil de décision
        ▼
   Réponse JSON (probabilité + classe + décision)
```

### Chargement des artefacts (warm-up)

Au démarrage du processus (pas à chaque requête), l'API charge une fois pour toutes :

| Artefact | Fichier | Rôle |
|---|---|---|
| Modèle | `xgb-classifier-model.json` | Modèle XGBoost entraîné |
| Liste de features | `xgb-model-features.rds` | Ordre et nom des colonnes attendues par le modèle |
| Recette | `recipe_prep.rds` | Transformation `recipes` (normalisation `tenure`, `MonthlyCharges`) |
| Seuil optimal | `optimal_threshold.rds` *(optionnel)* | Seuil de décision (Youden) ; **0.5 par défaut si absent** |

**Nouveau en v1.2.0 :** chaque chargement est enveloppé dans un `tryCatch` qui retourne `NULL` en cas d'échec, au lieu de faire crasher le processus R au démarrage. Un artefact manquant ou corrompu ne bloque donc plus le lancement du conteneur — il dégrade l'API en mode "unhealthy", détectable via `/health`.

---

## 3. Endpoints exposés

### 3.1 `GET /health`

Vérifie que le processus est démarré et que **les trois artefacts critiques** (`xgb_model`, `rec_prep`, `features`) sont effectivement chargés en mémoire.

**Réponse 200 (sain) :**
```json
{
  "status": "healthy",
  "timestamp": "2026-08-15 10:00:00",
  "model_loaded": true,
  "features_count": 22,
  "decision_thresh": 0.42
}
```

**Réponse 503 (dégradé)** — nouveau en v1.2.0, si un artefact n'a pas pu être chargé :
```json
{
  "status": "unhealthy",
  "timestamp": "2026-08-15 10:00:00",
  "error": "Artefacts ML non chargés ou corrompus."
}
```

Ce comportement est compatible avec les probes Docker `HEALTHCHECK` et Kubernetes `livenessProbe`/`readinessProbe`, qui interprètent un code HTTP ≥ 400/500 comme un signal d'indisponibilité.

### 3.2 `POST /predict`

Reçoit un ou plusieurs clients et retourne une prédiction de churn pour chacun.

**Entrée attendue :** tableau JSON d'objets, chaque objet représentant un client avec ses variables brutes (non normalisées) et ses variables déjà dummifiées (`Contract_Month_to_month`, `InternetService_DSL`, etc.).

**Colonnes strictement obligatoires** :
- `tenure`
- `MonthlyCharges`

**Contrôles métier appliqués (nouveau en v1.2.0)** :
- `tenure` doit être numérique et **≥ 0**
- `MonthlyCharges` doit être numérique et **≥ 0**

**Identifiant client** : recherche automatique parmi `customerID`, `customer_id`, `id_client`, `id`, `client_id` (insensible à la casse). À défaut, un identifiant est généré (`CLIENT_1`, `CLIENT_2`, ...).

**Réponse 200 :**
```json
[
  {
    "id_client": "CLIENT_1",
    "churn_proba": 0.7321,
    "churn_class": 1,
    "decision": "Churn"
  }
]
```

**Réponses d'erreur :**

| Code | Cas | Corps |
|---|---|---|
| 400 | JSON invalide ou vide | `{"error": "Bad Request", "message": "JSON invalide ou corps de requête vide."}` |
| 400 | Payload non tabulaire | `{"error": "Bad Request", "message": "Impossible d'interpréter le payload comme un tableau d'observations."}` |
| 400 | Colonnes obligatoires manquantes | `{"error": "Bad Request", "message": "...", "missing_columns": [...]}` |
| 400 | `tenure` ou `MonthlyCharges` invalide (négatif / non numérique) | `{"error": "Bad Request", "message": "Validation échouée : ..."}` |
| 500 | Erreur pendant `bake()` ou `predict()` | `{"error": "Internal Server Error", "message": "Une erreur est survenue..."}` *(détail technique loggé côté serveur uniquement, non transmis au client)* |

### 3.3 CORS

Un filtre `@filter cors` autorise les appels cross-origin (`Access-Control-Allow-Origin: *`) et répond directement aux requêtes `OPTIONS` (pré-vol).

---

## 4. Logique de traitement de `/predict` (détail)

1. **Parsing** du corps JSON, avec capture d'erreur robuste (400 en cas de JSON malformé).
2. **Validation de présence** des colonnes `tenure` et `MonthlyCharges`.
3. **Validation de bornes** : `tenure ≥ 0` et `MonthlyCharges ≥ 0`, rejet en 400 sinon.
4. **`bake()`** applique la recette de normalisation enregistrée.
5. **Complétion automatique** : toute colonne du modèle absente du payload après `bake()` est ajoutée avec la valeur **0**, sans erreur ni avertissement.
6. **Alignement strict** de la matrice sur l'ordre exact des `features`, conversion numérique forcée, `NA` résiduels remplacés par **0**.
7. **Inférence** XGBoost puis application du seuil (`best_thresh`).
8. **Logging serveur** de toute erreur d'inférence via `message()` (horodatage + détail), sans exposition au client.

---

## 5. Déploiement (Docker)

- Image de base : `rocker/r-ver:4.4` (Ubuntu Noble 24.04).
- Packages installés via les binaires précompilés Posit Package Manager.
- Utilisateur non-root pour l'exécution du conteneur.
- `HEALTHCHECK` intégré basé sur `/health` — désormais capable de détecter un état dégradé (503) grâce à la vérification des trois artefacts.
- Port exposé : `8080`.

---

## 6. Limites actuelles de l'API

### 6.1 Sécurité
- **Aucune authentification** — choix assumé pour cette démo (`Sans Clé API` dans le titre du fichier), mais **à corriger avant toute exposition au-delà d'un réseau de confiance**.
- **CORS entièrement ouvert** (`*`) : à restreindre à des origines nommées en production.
- **Pas de limitation de débit (rate limiting)**.
- Fuite d'information en 500 : **corrigée** en v1.2.0 (le détail technique n'est plus renvoyé au client, seulement loggé côté serveur).

### 6.2 Validation des données
- Les bornes ne sont vérifiées que sur **2 colonnes** (`tenure`, `MonthlyCharges`) ; les autres variables (dummies `Contract_*`, `InternetService_*`, etc.) ne sont pas contrôlées (pas de vérification qu'elles valent bien 0/1 par exemple).
- **Valeurs manquantes (`NA`/`null`) non détectées explicitement** : la validation utilise `na.rm = TRUE`, ce qui exclut les valeurs manquantes du contrôle de bornes. Un `tenure: null` passe donc la validation sans erreur, puis se retrouve silencieusement remplacé par **0 dans l'espace normalisé** après `bake()` — une valeur qui ne correspond pas à "tenure = 0" réel mais reflète approximativement la moyenne d'entraînement. Le client n'est jamais averti que sa donnée était incomplète.
- Les colonnes de features manquantes du modèle sont toujours **complétées silencieusement à 0**, sans avertissement dans la réponse.

### 6.3 Robustesse / Performance
- **Aucune limite de taille de payload** ni de nombre maximal de clients par requête.
- **Plumber en mode mono-processus par défaut** : les requêtes sont traitées séquentiellement sans configuration additionnelle (plusieurs workers, réplicas derrière un load-balancer, etc.).
- Pas de timeout serveur explicite pour les payloads volumineux.

### 6.4 Observabilité
- **`/health` teste la présence des artefacts, pas leur validité fonctionnelle** : un modèle chargé mais corrompu resterait "healthy" tant qu'il n'est pas `NULL` — pas de test d'inférence de bout en bout (ex. requête factice à chaque health-check).
- Le logging des erreurs d'inférence (`message()`) reste **non structuré et non persistant** au-delà de la sortie standard capturée par `docker logs` — pas de format JSON, pas de niveaux de sévérité, pas de rotation ni d'export vers un système centralisé.
- Aucune métrique exposée (latence, taux d'erreur, volumétrie) pour un monitoring type Prometheus/Grafana.

### 6.5 Versionnement et cycle de vie du modèle
- Les artefacts sont chargés **une seule fois au démarrage** : toute mise à jour du modèle nécessite un redéploiement complet (pas de rechargement à chaud).
- Le numéro de version (`1.2.0`) figure dans les métadonnées Swagger de l'API, mais **n'est pas renvoyé dans les réponses de `/predict`** — impossible de tracer a posteriori quelle version du modèle a produit une prédiction donnée.
- Le seuil de décision (`best_thresh`) est figé au démarrage, non surchargeable par requête.

### 6.6 Portabilité
- Sensibilité à la casse des noms de fichiers déjà corrigée pour `xgb-model-features.rds` — point de vigilance à conserver pour tout nouvel artefact ajouté à l'avenir (environnement Windows en dev vs Linux en conteneur).

---

## 7. Axes d'amélioration recommandés (non implémentés à ce jour)

| Priorité | Amélioration |
|---|---|
| Haute | Authentification par clé API ou token sur `/predict` |
| Haute | Rejet explicite (400) des valeurs manquantes sur `tenure`/`MonthlyCharges` plutôt que remplacement silencieux |
| Moyenne | Validation des colonnes dummifiées (contrôle 0/1) |
| Moyenne | Restriction CORS à des origines nommées |
| Moyenne | Logging structuré (JSON) vers stdout, avec ID de corrélation par requête |
| Moyenne | Limite de taille de payload / nombre de clients par requête |
| Basse | `/health` avec test d'inférence factice de bout en bout |
| Basse | Champ `model_version` dans les réponses de `/predict` |
| Basse | Support de plusieurs workers Plumber pour la montée en charge |

---

## 8. Fichiers de référence

- `plumber.R` — code source de l'API (v1.2.0)
- `Dockerfile` — build et exécution du conteneur
- `models/` — artefacts (modèle, recette, features, seuil)
