## Documentation technique — API de scoring Churn (XGBoost + Plumber)

- **Auteur du code source :** @Madiba
- **Stack :** R 4.4 - Plumber - XGBoost - Recipes
- **Version API :** 1.3.0 (*Secure Demo — Durcissement Sécurité*)
- **Version précédente :** 1.2.0

---

## 1. Objectif de l'API

L'API expose un modèle XGBoost entraîné pour prédire la probabilité de résiliation (*churn*) d'un client télécom, à partir de ses caractéristiques contractuelles et d'usage. Elle prend en charge le prétraitement (normalisation), la validation d'entrée, l'authentification, la journalisation, l'inférence, et retourne une décision binaire selon un seuil optimal pré-calculé.

---

## 2. Ce qui change par rapport à la v1.2.0

| Domaine | v1.2.0 | v1.3.0 |
|---|---|---|
| Authentification | Aucune | Clé API optionnelle (`X-API-Key`), activable via `API_KEY` |
| CORS | Toujours `*` | Restreignable via `ALLOWED_ORIGIN` |
| Valeurs manquantes (`tenure`, `MonthlyCharges`) | Silencieusement exclues du contrôle (`na.rm = TRUE`), puis mises à 0 après `bake()` | Rejetées explicitement en `400` |
| Colonnes dummifiées (`Contract_*`, `InternetService_*`...) | Non contrôlées | Doivent valoir strictement `0` ou `1`, sinon `400` |
| Taille de payload | Illimitée | Plafonnée (`MAX_BODY_SIZE_MB`, défaut 2 Mo) |
| Nombre de clients par requête | Illimité | Plafonné (`MAX_CLIENTS_PER_REQUEST`, défaut 200) |
| `/health` | Vérifie uniquement que les artefacts sont non-`NULL` | Exécute en plus une inférence factice de bout en bout |
| Traçabilité des prédictions | Aucun numéro de version dans la réponse | Champ `model_version` dans `/predict` et `/health` |
| Logs | `message()` texte libre, uniquement en cas d'erreur | Ligne JSON structurée pour **chaque** requête, avec `request_id` |

Tous les nouveaux comportements sont **désactivés par défaut** (valeurs de configuration permissives) afin de ne rien casser sans action explicite — voir section 4.

---

## 3. Architecture générale

```
Client (Shiny / Postman / autre)
        │  JSON (array d'objets) + en-tête X-API-Key (si activé)
        ▼
   Filtre logger   ──► log JSON (request_id, méthode, route, statut, durée)
        │
        ▼
   Filtre CORS      ──► origine autorisée ou wildcard selon ALLOWED_ORIGIN
        │
        ▼
   Filtre auth       ──► vérifie X-API-Key sur /predict si API_KEY définie
        │
        ▼
   Endpoint /predict
        │
        ├─► Contrôle de taille du payload (413 si dépassement)
        ├─► Parsing JSON
        ├─► Contrôle du nombre de clients (413 si dépassement)
        ├─► Validation de présence des colonnes obligatoires
        ├─► Rejet des valeurs manquantes (NA) sur tenure / MonthlyCharges
        ├─► Validation des bornes métier (tenure, MonthlyCharges ≥ 0)
        ├─► Validation stricte des colonnes dummifiées (0 ou 1)
        ├─► bake() — application de la recette de normalisation
        ├─► Complétion des colonnes manquantes (valeur 0)
        ├─► predict() — inférence XGBoost
        └─► Application du seuil de décision
        ▼
   Réponse JSON (probabilité + classe + décision + version du modèle)
```

L'ordre d'exécution des filtres (`logger` → `cors` → `auth`) est important : le logger capture systématiquement la requête, y compris celles rejetées par l'authentification, ce qui permet de détecter des tentatives d'accès non autorisées dans les logs.

### Chargement des artefacts (warm-up)

Inchangé par rapport à la v1.2.0 :

| Artefact | Fichier | Rôle |
|---|---|---|
| Modèle | `xgb-classifier-model.json` | Modèle XGBoost entraîné |
| Liste de features | `xgb-model-features.rds` | Ordre et nom des colonnes attendues par le modèle |
| Recette | `recipe_prep.rds` | Transformation `recipes` (normalisation `tenure`, `MonthlyCharges`) |
| Seuil optimal | `optimal_threshold.rds` *(optionnel)* | Seuil de décision (Youden) ; 0.5 par défaut si absent |

Chaque chargement reste enveloppé dans un `tryCatch` retournant `NULL` en cas d'échec, sans faire crasher le démarrage du conteneur.

---

## 4. Configuration (variables d'environnement)

Nouveau en v1.3.0 : la configuration sensible et opérationnelle passe désormais par des variables d'environnement plutôt que par des valeurs codées en dur.

| Variable | Défaut | Effet |
|---|---|---|
| `API_KEY` | *(vide)* | Si définie, requise en en-tête `X-API-Key` pour appeler `/predict`. Si vide, authentification désactivée (mode développement). |
| `ALLOWED_ORIGIN` | `*` | Liste d'origines autorisées pour le CORS, séparées par des virgules. `*` = wildcard (comportement identique à la v1.2.0). |
| `MAX_CLIENTS_PER_REQUEST` | `200` | Nombre maximal de clients (lignes) acceptés dans un seul appel à `/predict`. |
| `MAX_BODY_SIZE_MB` | `2` | Taille maximale du corps de requête acceptée, en mégaoctets. |

**Avertissements au démarrage** : si `API_KEY` est vide ou `ALLOWED_ORIGIN` vaut `*`, un message `[WARN]` est émis dans les logs du conteneur au lancement, pour que la configuration non sécurisée par défaut ne passe jamais inaperçue en production.

---

## 5. Endpoints exposés

### 5.1 `GET /health`

Non protégé par clé API (accessible sans authentification), afin de rester compatible avec les probes Docker `HEALTHCHECK` et Kubernetes `livenessProbe`/`readinessProbe`.

**Vérifications effectuées :**
1. Les trois artefacts critiques (`xgb_model`, `rec_prep`, `features`) sont chargés en mémoire (non `NULL`).
2. **Nouveau en v1.3.0** — une inférence factice est exécutée sur un vecteur de zéros aligné sur les features du modèle. Un modèle chargé mais corrompu (fichier tronqué, format incompatible) est ainsi détecté, alors qu'il aurait pu passer inaperçu en v1.2.0 (simple test de non-nullité).

**Réponse 200 (sain) :**
```json
{
  "status": "healthy",
  "timestamp": "2026-08-16 10:00:00",
  "model_loaded": true,
  "model_version": "1.3.0",
  "features_count": 22,
  "decision_thresh": 0.54
}
```

**Réponse 503 — artefacts non chargés :**
```json
{
  "status": "unhealthy",
  "timestamp": "2026-08-16 10:00:00",
  "model_version": "1.3.0",
  "error": "Artefacts ML non chargés ou corrompus."
}
```

**Réponse 503 — nouveau cas en v1.3.0, artefact chargé mais inerte :**
```json
{
  "status": "unhealthy",
  "timestamp": "2026-08-16 10:00:00",
  "model_version": "1.3.0",
  "error": "Le modèle est chargé mais échoue au test d'inférence (fichier potentiellement corrompu)."
}
```

### 5.2 `POST /predict`

**Protégé par clé API** si `API_KEY` est configurée côté serveur (voir section 4).

**En-tête requis (si authentification activée) :**
```
X-API-Key: <valeur de API_KEY>
```

**Réponse 401 si absente ou invalide :**
```json
{
  "error": "Unauthorized",
  "message": "Authentification requise : en-tête 'X-API-Key' manquant ou invalide."
}
```

**Entrée attendue :** identique à la v1.2.0 — tableau JSON d'objets, chaque objet représentant un client avec ses variables brutes et ses variables déjà dummifiées.

**Colonnes strictement obligatoires** : `tenure`, `MonthlyCharges` (inchangé).

**Contrôles métier appliqués :**

| Contrôle | v1.2.0 | v1.3.0 |
|---|---|---|
| `tenure` / `MonthlyCharges` numériques et ≥ 0 | ✅ | ✅ |
| `tenure` / `MonthlyCharges` non manquants (`NA`/`null`) | ❌ (silencieusement accepté) | ✅ **rejeté en 400** |
| Colonnes dummifiées valant 0 ou 1 | ❌ | ✅ **rejeté en 400 sinon** |
| Nombre de clients ≤ `MAX_CLIENTS_PER_REQUEST` | ❌ | ✅ **rejeté en 413 sinon** |
| Taille du corps ≤ `MAX_BODY_SIZE_MB` | ❌ | ✅ **rejeté en 413 sinon** |

**Identifiant client** : recherche automatique inchangée parmi `customerID`, `customer_id`, `id_client`, `id`, `client_id`.

**Réponse 200 :**
```json
[
  {
    "id_client": "CLIENT_1",
    "churn_proba": 0.7321,
    "churn_class": 1,
    "decision": "Churn",
    "model_version": "1.3.0"
  }
]
```
> Le champ `model_version` est nouveau en v1.3.0 : il permet de tracer a posteriori quelle version du modèle a produit une prédiction donnée.

**Réponses d'erreur :**

| Code | Cas | Statut |
|---|---|---|
| 401 | Clé API manquante ou invalide | Nouveau v1.3.0 |
| 400 | JSON invalide ou vide | Inchangé |
| 400 | Payload non tabulaire | Inchangé |
| 400 | Colonnes obligatoires manquantes | Inchangé |
| 400 | `tenure` ou `MonthlyCharges` manquant (`NA`/`null`) | Nouveau v1.3.0 |
| 400 | `tenure` ou `MonthlyCharges` invalide (négatif / non numérique) | Inchangé |
| 400 | Colonne dummifiée hors de `{0, 1}` | Nouveau v1.3.0 |
| 413 | Nombre de clients supérieur à `MAX_CLIENTS_PER_REQUEST` | Nouveau v1.3.0 |
| 413 | Corps de requête supérieur à `MAX_BODY_SIZE_MB` | Nouveau v1.3.0 |
| 500 | Erreur pendant `bake()` ou `predict()` | Inchangé (détail loggé côté serveur uniquement) |

### 5.3 CORS

Comportement par défaut inchangé (`*`), mais désormais restreignable sans modification de code via `ALLOWED_ORIGIN`. Réponse aux requêtes `OPTIONS` (pré-vol) conservée, avec l'en-tête `X-API-Key` désormais inclus dans `Access-Control-Allow-Headers`.

---

## 6. Journalisation (nouveau en v1.3.0)

Chaque requête, quelle que soit sa route ou son issue, génère une ligne de log JSON sur la sortie standard (donc capturée par `docker logs`) :

```json
{
  "timestamp": "2026-08-16T10:00:00.123Z",
  "request_id": "20260816100000123-a1b2c3",
  "method": "POST",
  "path": "/predict",
  "status": 200,
  "duration_ms": 42.7
}
```

Le `request_id` est également réutilisé dans les logs d'erreur d'inférence (`[ERROR] ... request_id=... Erreur d'inférence : ...`), ce qui permet de relier une ligne de log d'erreur métier à la requête HTTP correspondante — utile pour le support et le débogage en production, notamment avec plusieurs requêtes concurrentes.

Ce format JSON reste directement exploitable par un collecteur de logs centralisé (Loki, ELK, CloudWatch...), sans nécessiter de parsing par expression régulière.

---

## 7. Déploiement (Docker)

Inchangé par rapport à la v1.2.0 :
- Image de base : `rocker/r-ver:4.4` (Ubuntu Noble 24.04).
- Build multi-étapes, packages installés via les binaires précompilés Posit Package Manager.
- Utilisateur non-root pour l'exécution du conteneur.
- `HEALTHCHECK` intégré basé sur `/health`, désormais capable de détecter un modèle corrompu en plus d'un artefact manquant.
- Port exposé : `8080`.

**Nouveau en v1.3.0** — variables d'environnement à injecter dans le `docker-compose.yml` du service `api` pour activer les protections :
```yaml
environment:
  API_KEY: "${API_KEY}"                  # à définir en secret, ne jamais committer en clair
  ALLOWED_ORIGIN: "https://votre-domaine.com"
  MAX_CLIENTS_PER_REQUEST: "200"
  MAX_BODY_SIZE_MB: "2"
```

> ⚠️ Si `API_KEY` est activée côté API, le client Shiny (et tout autre consommateur de l'API) doit envoyer l'en-tête `X-API-Key` sur ses appels à `/predict`, faute de quoi il recevra systématiquement une erreur `401`.

---

## 8. Limites actuelles de l'API (après v1.3.0)

### 8.1 Sécurité
- L'authentification reste une **clé API unique et partagée**, pas un système de comptes/rôles ni de rotation automatique — suffisant pour un accès de confiance restreint, pas pour une exposition publique à grande échelle.
- Pas encore de limitation de débit (*rate limiting*) par client/IP : un appelant authentifié peut toujours saturer le service en fréquence d'appel, même dans les limites de taille de payload désormais imposées.
- Le CORS reste en wildcard par défaut tant que `ALLOWED_ORIGIN` n'est pas explicitement configuré — la protection existe mais n'est pas activée d'office.

### 8.2 Validation des données
- La validation dummifiée (0/1) ne s'applique qu'aux colonnes **présentes dans le payload** ; une colonne totalement absente reste complétée silencieusement à 0 après `bake()`, comportement inchangé et volontairement conservé pour la compatibilité avec des clients envoyant un sous-ensemble de features.

### 8.3 Robustesse / Performance
- Plumber reste en **mode mono-processus** par défaut : les requêtes sont traitées séquentiellement. Ce point n'a pas été traité dans cette version car il relève d'une décision de déploiement (plusieurs workers/réplicas derrière un load-balancer) plutôt que d'une modification du code applicatif.

### 8.4 Versionnement et cycle de vie du modèle
- Les artefacts restent chargés une seule fois au démarrage : toute mise à jour du modèle nécessite toujours un redémarrage du conteneur (pas de rechargement à chaud). Le champ `model_version` permet désormais au moins de tracer a posteriori quelle version a produit quelle prédiction.

---

## 9. Axes d'amélioration restants

| Priorité | Amélioration | Statut |
|---|---|---|
| Haute | Authentification par clé API sur `/predict` | ✅ Fait en v1.3.0 |
| Haute | Rejet explicite des valeurs manquantes | ✅ Fait en v1.3.0 |
| Moyenne | Validation des colonnes dummifiées | ✅ Fait en v1.3.0 |
| Moyenne | Restriction CORS à des origines nommées | ✅ Fait en v1.3.0 (à activer) |
| Moyenne | Logging structuré avec ID de corrélation | ✅ Fait en v1.3.0 |
| Moyenne | Limite de taille de payload / nombre de clients | ✅ Fait en v1.3.0 |
| Basse | `/health` avec test d'inférence factice | ✅ Fait en v1.3.0 |
| Basse | Champ `model_version` dans les réponses | ✅ Fait en v1.3.0 |
| Basse | Support de plusieurs workers Plumber | ⏳ Non traité — relève du déploiement |
| Nouveau | Limitation de débit (rate limiting) par client/IP | ⏳ Non traité |
| Nouveau | Rotation ou expiration de la clé API | ⏳ Non traité |

---

## 10. Fichiers de référence

- `plumber.R` — code source de l'API (v1.3.0)
- `Dockerfile` — build et exécution du conteneur (inchangé)
- `docker-compose.yml` — orchestration, variables d'environnement de sécurité à y ajouter
- `models/` — artefacts (modèle, recette, features, seuil)
