# ==============================================================================#
# API REST Plumber pour scoring Churn XGBoost (v1.3.0 - Durcissement Sécurité)  #
# Auteur : Madiba                                                               #
# ==============================================================================#
#
# Historique des évolutions par rapport à la v1.2.0 :
#   - Authentification par clé API sur /predict (section 0 + filtre "auth")
#   - Rejet explicite des valeurs manquantes (NA/null) sur tenure/MonthlyCharges
#   - Validation stricte des colonnes dummifiées (doivent valoir 0 ou 1)
#   - CORS restreignable à des origines nommées via variable d'environnement
#   - Logging structuré JSON avec identifiant de corrélation par requête
#   - Limite de taille de payload et de nombre de clients par requête
#   - /health : test d'inférence factice de bout en bout
#   - Ajout du champ model_version dans les réponses de /predict et /health
#
# ============================================================================== #

library(plumber)
library(jsonlite)
library(dplyr)
library(xgboost)
library(recipes)

# ============================================================================== #
# 0. Configuration (variables d'environnement)                                  #
# ============================================================================== #
# AMÉLIORATION v1.3.0 : toute la configuration sensible/opérationnelle passe
# désormais par des variables d'environnement, avec des valeurs par défaut
# permissives pour ne pas casser le fonctionnement en développement local,
# mais accompagnées d'un avertissement explicite au démarrage.

MODEL_VERSION <- "1.3.0"

# Clé API attendue sur l'en-tête "X-API-Key" pour appeler /predict.
# Si non définie -> authentification désactivée (mode développement uniquement).
API_KEY <- Sys.getenv("API_KEY", unset = "")

# Origines autorisées pour le CORS, séparées par des virgules.
# Ex: "https://monapp.example.com,https://partenaire.com"
# Valeur par défaut "*" conservée pour compatibilité avec l'existant (démo/dev).
ALLOWED_ORIGIN <- Sys.getenv("ALLOWED_ORIGIN", unset = "*")

# Nombre maximal de clients (lignes) acceptés dans un seul appel à /predict.
MAX_CLIENTS_PER_REQUEST <- as.integer(Sys.getenv("MAX_CLIENTS_PER_REQUEST", unset = "200"))

# Taille maximale du corps de requête acceptée, en Mo.
MAX_BODY_SIZE_MB <- as.numeric(Sys.getenv("MAX_BODY_SIZE_MB", unset = "2"))
MAX_BODY_SIZE_BYTES <- MAX_BODY_SIZE_MB * 1024 * 1024

# Avertissements de démarrage : visibles dans `docker logs`, pour que la
# configuration non sécurisée par défaut ne passe jamais inaperçue en prod.
if (!nzchar(API_KEY)) {
  message("[WARN] API_KEY non définie : /predict est accessible SANS authentification. ",
          "A ne pas utiliser en production sans définir la variable API_KEY.")
}
if (ALLOWED_ORIGIN == "*") {
  message("[WARN] ALLOWED_ORIGIN='*' : CORS entièrement ouvert. ",
          "Restreindre via la variable d'environnement ALLOWED_ORIGIN en production.")
}

# ============================================================================== #
# 1. Chargement global des artefacts (Warm-up au démarrage)                     #
# ============================================================================== #

app_root <- getwd()
models_dir <- file.path(app_root, "models")

xgb_model <- tryCatch(xgb.load(file.path(models_dir, "xgb-classifier-model.json")), error = function(e) NULL)
features  <- tryCatch(readRDS(file.path(models_dir, "xgb-model-features.rds")), error = function(e) NULL)
rec_prep  <- tryCatch(readRDS(file.path(models_dir, "recipe_prep.rds")), error = function(e) NULL)

best_thresh <- if (file.exists(file.path(models_dir, "optimal_threshold.rds"))) {
  readRDS(file.path(models_dir, "optimal_threshold.rds"))
} else {
  0.5
}

required_raw_cols <- c("tenure", "MonthlyCharges")

#* @apiTitle XGBoost Churn Prediction API (Secure Demo)
#* @apiDescription API de scoring avec validation rigoureuse des données d'entrée et authentification par clé API.
#* @apiVersion 1.3.0

# ============================================================================== #
# 2. Filtre : Journalisation structurée (nouveau en v1.3.0)                     #
# ============================================================================== #
# AMÉLIORATION v1.3.0 : chaque requête reçoit un identifiant unique et génère
# une ligne de log JSON (timestamp, méthode, route, statut, durée) sur stdout,
# exploitable par tout collecteur de logs (Docker, Loki, ELK...) sans parsing
# fragile de texte libre.

#* @filter logger
function(req, res) {
  request_id <- paste0(
    format(Sys.time(), "%Y%m%d%H%M%OS3"), "-",
    paste0(sample(c(0:9, letters[1:6]), 6, replace = TRUE), collapse = "")
  )
  req$request_id <- request_id
  start_time <- Sys.time()
  
  result <- plumber::forward()
  
  duration_ms <- round(as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1000, 1)
  
  log_line <- list(
    timestamp   = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"),
    request_id  = request_id,
    method      = req$REQUEST_METHOD,
    path        = req$PATH_INFO,
    status      = res$status,
    duration_ms = duration_ms
  )
  message(toJSON(log_line, auto_unbox = TRUE))
  
  result
}

# ============================================================================== #
# 3. Filtre CORS (restreignable en v1.3.0)                                      #
# ============================================================================== #
# AMÉLIORATION v1.3.0 : n'autorise plus systématiquement "*" mais reflète
# l'origine appelante uniquement si elle figure dans ALLOWED_ORIGIN.
# Comportement inchangé (wildcard) tant que ALLOWED_ORIGIN n'est pas défini,
# pour ne pas casser les intégrations existantes sans action explicite.

#* @filter cors
function(req, res) {
  if (ALLOWED_ORIGIN == "*") {
    res$setHeader("Access-Control-Allow-Origin", "*")
  } else {
    allowed_list <- trimws(strsplit(ALLOWED_ORIGIN, ",")[[1]])
    origin <- req$HTTP_ORIGIN
    if (!is.null(origin) && origin %in% allowed_list) {
      res$setHeader("Access-Control-Allow-Origin", origin)
      res$setHeader("Vary", "Origin")
    }
  }
  
  if (req$REQUEST_METHOD == "OPTIONS") {
    res$setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    res$setHeader("Access-Control-Allow-Headers", "Content-Type, X-API-Key")
    res$status <- 200
    return(list())
  } else {
    plumber::forward()
  }
}

# ============================================================================== #
# 4. Filtre : Authentification par clé API (nouveau en v1.3.0)                  #
# ============================================================================== #
# AMÉLIORATION v1.3.0 : protège uniquement /predict (le endpoint qui consomme
# des ressources de calcul et renvoie une donnée métier), pas /health qui doit
# rester accessible sans clé pour les probes Docker/Kubernetes.
# Si API_KEY n'est pas définie côté serveur, l'authentification est simplement
# désactivée (voir avertissement de démarrage) : aucune régression en local.

#* @filter auth
function(req, res) {
  is_protected_call <- req$PATH_INFO == "/predict" && req$REQUEST_METHOD == "POST"
  
  if (is_protected_call && nzchar(API_KEY)) {
    provided_key <- req$HTTP_X_API_KEY
    
    if (is.null(provided_key) || !identical(provided_key, API_KEY)) {
      res$status <- 401
      return(list(
        error = "Unauthorized",
        message = "Authentification requise : en-tête 'X-API-Key' manquant ou invalide."
      ))
    }
  }
  
  plumber::forward()
}

# ============================================================================== #
# 5. Endpoint : Health Check (test d'inférence de bout en bout en v1.3.0)       #
# ============================================================================== #
# AMÉLIORATION v1.3.0 : au-delà de vérifier que les artefacts sont chargés
# (non-NULL), on exécute désormais une inférence factice sur un vecteur de
# zéros. Un modèle chargé mais corrompu (fichier tronqué, format incompatible)
# est ainsi détecté ici, alors qu'il aurait pu passer inaperçu auparavant.

#* Vérifier l'état de santé du service et la disponibilité des modèles
#* @get /health
#* @serializer json
function(res) {
  artefacts_ok <- !is.null(xgb_model) && !is.null(rec_prep) && !is.null(features)
  
  if (!artefacts_ok) {
    res$status <- 503
    return(list(
      status = "unhealthy",
      timestamp = Sys.time(),
      model_version = MODEL_VERSION,
      error = "Artefacts ML non chargés ou corrompus."
    ))
  }
  
  # Test d'inférence factice de bout en bout
  inference_ok <- tryCatch({
    dummy_matrix <- matrix(0, nrow = 1, ncol = length(features))
    colnames(dummy_matrix) <- features
    storage.mode(dummy_matrix) <- "numeric"
    invisible(predict(xgb_model, dummy_matrix))
    TRUE
  }, error = function(e) {
    message(sprintf("[ERROR] /health - échec du test d'inférence factice : %s", conditionMessage(e)))
    FALSE
  })
  
  if (!inference_ok) {
    res$status <- 503
    return(list(
      status = "unhealthy",
      timestamp = Sys.time(),
      model_version = MODEL_VERSION,
      error = "Le modèle est chargé mais échoue au test d'inférence (fichier potentiellement corrompu)."
    ))
  }
  
  res$status <- 200
  list(
    status = "healthy",
    timestamp = Sys.time(),
    model_loaded = TRUE,
    model_version = MODEL_VERSION,
    features_count = length(features),
    decision_thresh = best_thresh
  )
}

# ============================================================================== #
# 6. Endpoint : Scoring Client avec Validation & Bornes                         #
# ============================================================================== #

#* Prédiction du Churn avec contrôle strict des données d'entrée
#* @parser json
#* @post /predict
#* @serializer json
function(req, res) {
  
  # A. Limite de taille de payload (nouveau en v1.3.0)
  # Empêche un client (volontaire ou non) d'envoyer un corps de requête
  # démesuré qui saturerait la mémoire ou le temps de traitement du service.
  raw_body <- req$postBody
  body_size_bytes <- if (is.character(raw_body)) nchar(raw_body, type = "bytes") else 0
  if (body_size_bytes > MAX_BODY_SIZE_BYTES) {
    res$status <- 413
    return(list(
      error = "Payload Too Large",
      message = sprintf("Le corps de la requête dépasse la limite autorisée de %.1f Mo.", MAX_BODY_SIZE_MB)
    ))
  }
  
  # B. Parsing du body JSON
  body_data <- tryCatch({
    if (is.character(raw_body)) {
      fromJSON(raw_body)
    } else {
      req$args$body
    }
  }, error = function(e) NULL)
  
  if (is.null(body_data) || length(body_data) == 0) {
    res$status <- 400
    return(list(error = "Bad Request", message = "JSON invalide ou corps de requête vide."))
  }
  
  df_input <- tryCatch(as.data.frame(body_data), error = function(e) NULL)
  
  if (is.null(df_input) || nrow(df_input) == 0) {
    res$status <- 400
    return(list(error = "Bad Request", message = "Impossible d'interpréter le payload comme un tableau d'observations."))
  }
  
  # C. Limite de nombre de clients par requête (nouveau en v1.3.0)
  if (nrow(df_input) > MAX_CLIENTS_PER_REQUEST) {
    res$status <- 413
    return(list(
      error = "Payload Too Large",
      message = sprintf("Nombre de clients (%d) supérieur à la limite autorisée (%d) par requête.",
                        nrow(df_input), MAX_CLIENTS_PER_REQUEST)
    ))
  }
  
  # D. Validation de la présence des colonnes obligatoires minimales
  missing_raw <- setdiff(required_raw_cols, names(df_input))
  if (length(missing_raw) > 0) {
    res$status <- 400
    return(list(
      error = "Bad Request",
      message = "Colonnes obligatoires manquantes dans le payload.",
      missing_columns = missing_raw
    ))
  }
  
  # E. Rejet explicite des valeurs manquantes (nouveau en v1.3.0)
  # Avant : `na.rm = TRUE` excluait silencieusement les NA du contrôle de
  # bornes, qui étaient ensuite remplacés par 0 dans l'espace normalisé après
  # bake() sans jamais avertir le client. Un tenure=null passait inaperçu.
  # Désormais : toute valeur manquante sur les colonnes obligatoires est
  # explicitement rejetée en 400, avant même le contrôle de bornes.
  if (any(is.na(df_input$tenure))) {
    res$status <- 400
    return(list(
      error = "Bad Request",
      message = "Validation échouée : la variable 'tenure' ne peut pas être manquante (null)."
    ))
  }
  if (any(is.na(df_input$MonthlyCharges))) {
    res$status <- 400
    return(list(
      error = "Bad Request",
      message = "Validation échouée : la variable 'MonthlyCharges' ne peut pas être manquante (null)."
    ))
  }
  
  # F. Validation des types et des bornes (Contrôle métier)
  # (na.rm = TRUE conservé ici uniquement par cohérence défensive :
  # les NA ont déjà été rejetés à l'étape E, ce contrôle ne peut donc
  # plus jamais être court-circuité silencieusement par une valeur manquante.)
  if (any(!is.numeric(df_input$tenure) | df_input$tenure < 0, na.rm = TRUE)) {
    res$status <- 400
    return(list(
      error = "Bad Request",
      message = "Validation échouée : la variable 'tenure' doit être un nombre positif ou nul (>= 0)."
    ))
  }
  
  if (any(!is.numeric(df_input$MonthlyCharges) | df_input$MonthlyCharges < 0, na.rm = TRUE)) {
    res$status <- 400
    return(list(
      error = "Bad Request",
      message = "Validation échouée : la variable 'MonthlyCharges' doit être un nombre positif ou nul (>= 0)."
    ))
  }
  
  # G. Validation stricte des colonnes dummifiées (nouveau en v1.3.0)
  # Toute colonne présente dans le payload ET connue du modèle (features)
  # autre que tenure/MonthlyCharges est censée être un indicateur one-hot
  # (0 ou 1). On rejette désormais toute valeur hors de cet ensemble
  # (ex: 2, -1, "yes", NA) plutôt que de laisser passer une donnée aberrante
  # jusqu'à la matrice d'inférence.
  if (!is.null(features)) {
    dummy_cols_present <- intersect(names(df_input), setdiff(features, required_raw_cols))
    for (col in dummy_cols_present) {
      col_values <- suppressWarnings(as.numeric(df_input[[col]]))
      invalid <- is.na(col_values) | !(col_values %in% c(0, 1))
      if (any(invalid)) {
        res$status <- 400
        return(list(
          error = "Bad Request",
          message = sprintf("Validation échouée : la variable '%s' doit valoir 0 ou 1.", col)
        ))
      }
    }
  }
  
  # H. Gestion des ID clients
  id_col <- names(df_input)[tolower(names(df_input)) %in% c("customerid", "customer_id", "id_client", "id", "client_id")][1]
  client_ids <- if (!is.na(id_col)) as.character(df_input[[id_col]]) else paste0("CLIENT_", seq_len(nrow(df_input)))
  
  # I. Pipeline de prédiction sécurisé
  tryCatch({
    # Application de la recette
    df_transformed <- bake(rec_prep, new_data = df_input)
    
    # Alignement des features
    missing_feats <- setdiff(features, names(df_transformed))
    if (length(missing_feats) > 0) {
      for (col in missing_feats) {
        df_transformed[[col]] <- 0
      }
    }
    
    X_matrix <- as.matrix(df_transformed[, features, drop = FALSE])
    storage.mode(X_matrix) <- "numeric"
    X_matrix[is.na(X_matrix)] <- 0
    
    # Inférence XGBoost
    pred_probs <- predict(xgb_model, X_matrix)
    pred_class <- ifelse(pred_probs >= best_thresh, 1, 0)
    
    res$status <- 200
    return(data.frame(
      id_client = client_ids,
      churn_proba = round(pred_probs, 4),
      churn_class = pred_class,
      decision = ifelse(pred_class == 1, "Churn", "Non Churn"),
      model_version = MODEL_VERSION, # AMÉLIORATION v1.3.0 : traçabilité de la version ayant produit la prédiction
      stringsAsFactors = FALSE
    ))
    
  }, error = function(e) {
    # Log interne pour debug sans exposer les détails techniques au client
    message(sprintf("[ERROR] %s - request_id=%s - Erreur d'inférence : %s",
                    Sys.time(), req$request_id, conditionMessage(e)))
    
    res$status <- 500
    return(list(
      error = "Internal Server Error",
      message = "Une erreur est survenue lors du traitement des données ou de la prédiction."
    ))
  })
}

# ============================================================================== #
# 7. Injection de la documentation Swagger                                      #
# ============================================================================== #

#* @plumber
function(pr) {
  pr$setApiSpec(function(spec) {
    spec$paths$`/predict`$post$requestBody <- list(
      description = "Tableau JSON d'observations clients avec validation des bornes. Authentification requise via l'en-tête 'X-API-Key' si API_KEY est configurée côté serveur.",
      required = TRUE,
      content = list(
        `application/json` = list(
          schema = list(type = "array", items = list(type = "object")),
          example = list(
            list(
              SeniorCitizen = 0,
              Partner = 1,
              Dependents = 0,
              tenure = 1,
              PaperlessBilling = 1,
              MonthlyCharges = 29.85,
              MultipleLines_No = 0,
              MultipleLines_No_phone_service = 1,
              MultipleLines_Yes = 0,
              InternetService_DSL = 1,
              InternetService_Fiber_optic = 0,
              InternetService_No = 0,
              Contract_Month_to_month = 1,
              Contract_One.year = 0,
              Contract_Two.year = 0,
              PaymentMethod_Bank_transfer = 0,
              PaymentMethod_Credit_card = 0,
              PaymentMethod_Electronic_check = 1,
              PaymentMethod_Mailed_check = 0,
              ServiceSup_No = 0,
              ServiceSup_No_internet_service = 0,
              ServiceSup_Yes = 1
            )
          )
        )
      )
    )
    spec
  })
}
