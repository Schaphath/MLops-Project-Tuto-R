# Telco Churn AI — Documentation Technique
### Système de scoring de churn client par XGBoost

**Auteur :** Madiba
**Dernière mise à jour :** Août 2026
**Statut :** Fonctionnel en production

---

## 1. Vue d'ensemble

Cette application permet de prédire la probabilité de résiliation (*churn*) d'un client télécom à partir de ses caractéristiques contractuelles et démographiques. Le système est composé de **deux services indépendants**, conteneurisés et orchestrés ensemble :

| Service | Rôle | Technologie | Port |
|---|---|---|---|
| **api** | Scoring / inférence du modèle XGBoost | R + Plumber | 8080 (interne) |
| **shiny** | Interface utilisateur (formulaire de saisie) | R + Shiny | 3838 (public) |

```
┌─────────────────────┐        HTTP interne        ┌──────────────────────┐
│   Conteneur shiny    │  ─────────────────────▶   │    Conteneur api      │
│  (port 3838, public) │   http://api:8080/predict  │  (port 8080, interne) │
└─────────────────────┘        ◀─────────────────    └──────────────────────┘
         ▲
         │ port 3838
         │
     Utilisateur final
```

Les deux services communiquent via un réseau Docker interne (`churn-net`) et **ne sont jamais joignables l'un l'autre en `127.0.0.1`** — voir la section [5. Pièges connus](#5-pièges-connus--erreurs-fréquentes) pour le détail.

---

## 2. Architecture des dossiers

```
projet/
├── docker-compose.yml
├── api/
│   ├── Dockerfile
│   ├── plumber.R
│   └── models/
│       ├── xgb-classifier-model.json     # Modèle XGBoost entraîné
│       ├── xgb-model-features.rds        # Liste ordonnée des features attendues
│       ├── recipe_prep.rds               # Pipeline de pré-traitement (package recipes)
│       └── optimal_threshold.rds         # Seuil de décision optimisé
└── shiny/
    ├── Dockerfile
    └── shiny.R
```

---

## 3. Le service API (`api/`)

### 3.1 Rôle
Expose un modèle XGBoost entraîné sur les données de churn Telco via une API REST simple, avec validation stricte des entrées.

### 3.2 Endpoints

#### `GET /health`
Vérifie que les artefacts ML (modèle, recette, features) sont bien chargés en mémoire.

- **200** → service opérationnel
- **503** → artefacts manquants ou corrompus (le conteneur ne doit alors pas recevoir de trafic)

```json
{
  "status": "healthy",
  "timestamp": "2026-08-16T10:00:00Z",
  "model_loaded": true,
  "features_count": 21,
  "decision_thresh": 0.42
}
```

#### `POST /predict`
Reçoit un tableau JSON d'observations clients et retourne la probabilité de churn.

**Validations appliquées avant inférence :**
- présence des colonnes obligatoires (`tenure`, `MonthlyCharges`)
- `tenure` et `MonthlyCharges` doivent être numériques et ≥ 0
- alignement automatique des colonnes one-hot manquantes (complétées à 0)

**Exemple de payload attendu** (un client) :
```json
{
  "SeniorCitizen": 0,
  "Partner": 1,
  "Dependents": 0,
  "tenure": 1,
  "PaperlessBilling": 1,
  "MonthlyCharges": 29.85,
  "MultipleLines_No": 0,
  "MultipleLines_No_phone_service": 1,
  "MultipleLines_Yes": 0,
  "InternetService_DSL": 1,
  "InternetService_Fiber_optic": 0,
  "InternetService_No": 0,
  "Contract_Month_to_month": 1,
  "Contract_One.year": 0,
  "Contract_Two.year": 0,
  "PaymentMethod_Bank_transfer": 0,
  "PaymentMethod_Credit_card": 0,
  "PaymentMethod_Electronic_check": 1,
  "PaymentMethod_Mailed_check": 0,
  "ServiceSup_No": 0,
  "ServiceSup_No_internet_service": 0,
  "ServiceSup_Yes": 1
}
```

**Réponse :**
```json
{
  "id_client": "CLIENT_1",
  "churn_proba": 0.7321,
  "churn_class": 1,
  "decision": "Churn"
}
```

**Codes d'erreur :**
| Code | Cas |
|---|---|
| 400 | JSON invalide, colonnes manquantes, valeurs hors bornes |
| 500 | Erreur interne lors de l'inférence (détail masqué au client, loggé côté serveur) |

### 3.3 Sécurité
- CORS ouvert (`Access-Control-Allow-Origin: *`) — à restreindre si l'API devient publique un jour
- Aucune authentification par clé actuellement — l'API n'est **pas exposée sur l'hôte** en production, uniquement accessible depuis le réseau interne Docker

---

## 4. Le service Shiny (`shiny/`)

### 4.1 Rôle
Formulaire web permettant à un utilisateur de saisir le profil d'un client et de déclencher une prédiction via l'API.

### 4.2 Fonctionnement
1. L'utilisateur remplit le formulaire (profil, facturation, offres)
2. Au clic sur **"Lancer la prédiction"**, le client Shiny :
   - vérifie que l'API est joignable (test de socket)
   - construit le payload JSON avec encodage one-hot manuel
   - envoie une requête `POST /predict` (timeout 3s)
3. Le résultat (probabilité + décision) s'affiche sous forme de badge coloré

### 4.3 Variable d'environnement clé

| Variable | Description | Valeur en prod |
|---|---|---|
| `API_URL` | URL de base de l'API, utilisée pour tous les appels HTTP **et** pour le test de disponibilité | `http://api:8080` |

> ⚠️ En environnement Docker, le service Shiny et le service API tournent dans des conteneurs distincts, chacun avec son propre `127.0.0.1`. Le nom `api` dans `API_URL` est résolu automatiquement par Docker Compose via le réseau interne `churn-net` — c'est le mécanisme de *service discovery* natif de Compose.

---

## 5. Pièges connus & erreurs fréquentes

### 5.1 "L'API Plumber n'est pas démarrée" alors qu'elle tourne

**Symptôme :** notification d'erreur permanente côté Shiny, même quand l'API est saine et que `docker ps` la montre "healthy".

**Cause :** le test de disponibilité dans `shiny.R` testait historiquement `127.0.0.1:8080` en dur, au lieu de se baser sur `API_URL`. Dans un environnement multi-conteneurs, `127.0.0.1` désigne toujours le conteneur courant — jamais un conteneur voisin.

**Correctif appliqué (déjà en place dans la version actuelle) :** le host et le port sont désormais extraits dynamiquement de `API_URL` :
```r
api_host <- sub("^https?://([^:/]+).*$", "\\1", API_URL)
api_port_raw <- sub("^https?://[^:/]+:?([0-9]*).*$", "\\1", API_URL)
api_port <- if (nzchar(api_port_raw)) as.integer(api_port_raw) else 80L
```

**Point de vigilance pour tout nouveau développeur :** si vous ajoutez un nouvel appel réseau vers l'API ailleurs dans le code, n'utilisez jamais `127.0.0.1` ou `localhost` en dur — passez toujours par `API_URL`.

### 5.2 Réponse batch (plusieurs clients à la fois)

L'API accepte déjà un tableau de plusieurs observations en entrée et renverra alors un tableau de résultats (plusieurs lignes). **Le client Shiny actuel n'est prévu que pour un seul client à la fois** — `results_ui` ne gère pas l'affichage d'un `data.frame` multi-lignes. Pour du scoring en masse, prévoir une évolution de l'UI (ex. `DT::datatable`, déjà importé dans les dépendances).

### 5.3 Port de l'API non accessible depuis l'extérieur

C'est un choix volontaire de sécurité : en production, `api` n'est pas publié sur l'hôte (`expose` et non `ports` dans le compose). Si vous devez déboguer l'API directement depuis votre machine, publiez temporairement le port en local, mais ne le laissez pas exposé en production.

---

## 6. Déploiement

### 6.1 Prérequis
- Docker + Docker Compose (v2)
- Artefacts du modèle présents dans `api/models/`

### 6.2 Commandes

```bash
# Build des deux images
docker compose build

# Démarrage en arrière-plan
docker compose up -d

# Vérifier l'état de santé des services
docker compose ps

# Consulter les logs
docker compose logs -f api
docker compose logs -f shiny

# Arrêt
docker compose down
```

### 6.3 Mise à jour du modèle sans rebuild

Les artefacts du modèle sont montés en volume (`./api/models:/app/models:ro`). Il suffit de remplacer les fichiers dans `api/models/` sur l'hôte puis de redémarrer le conteneur API :
```bash
docker compose restart api
```

### 6.4 Accès

| Service | URL |
|---|---|
| Interface utilisateur | `http://<adresse-serveur>:3838` |
| API (interne uniquement) | non accessible depuis l'extérieur |

---

## 7. Contacts & responsabilités

| Domaine | Contact |
|---|---|
| Modèle ML (entraînement, features) | Madiba |
| API Plumber | Madiba |
| Interface Shiny | Madiba |
| Infrastructure / Docker | *(à compléter)* |

---

## 8. Historique des versions

| Date | Modification |
|---|---|
| Août 2026 | Correction du test de disponibilité API (host/port dynamiques via `API_URL`) |
| Août 2026 | Mise en place du `docker-compose.yml` de production (réseau interne, healthchecks, limites de ressources) |
| — | Version initiale : API Plumber + client Shiny |
