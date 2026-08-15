# ============================================================================== #
# API REST Plumber pour scoring Churn XGBoost (Propre & Validée - Sans Clé API)  #
# Auteur : Madiba                                                                #
# ============================================================================== #

library(plumber)
library(jsonlite)
library(dplyr)
library(xgboost)
library(recipes)

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
#* @apiDescription API de scoring avec validation rigoureuse des données d'entrée.
#* @apiVersion 1.2.0

# ============================================================================== #
# 2. Filtre CORS                                                                #
# ============================================================================== #

#* @filter cors
function(req, res) {
  res$setHeader("Access-Control-Allow-Origin", "*")
  if (req$REQUEST_METHOD == "OPTIONS") {
    res$setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    res$setHeader("Access-Control-Allow-Headers", "Content-Type")
    res$status <- 200
    return(list())
  } else {
    plumber::forward()
  }
}

# ============================================================================== #
# 3. Endpoint : Health Check (Robuste pour Docker / K8s)                        #
# ============================================================================== #

#* Vérifier l'état de santé du service et la disponibilité des modèles
#* @get /health
#* @serializer json
function(res) {
  is_healthy <- !is.null(xgb_model) && !is.null(rec_prep) && !is.null(features)
  
  if (!is_healthy) {
    res$status <- 503 # Service Unavailable
    return(list(
      status = "unhealthy",
      timestamp = Sys.time(),
      error = "Artefacts ML non chargés ou corrompus."
    ))
  }
  
  res$status <- 200
  list(
    status = "healthy",
    timestamp = Sys.time(),
    model_loaded = TRUE,
    features_count = length(features),
    decision_thresh = best_thresh
  )
}

# ============================================================================== #
# 4. Endpoint : Scoring Client avec Validation & Bornes                         #
# ============================================================================== #

#* Prédiction du Churn avec contrôle strict des données d'entrée
#* @parser json
#* @post /predict
#* @serializer json
function(req, res) {
  
  # A. Parsing du body JSON
  body_data <- tryCatch({
    if (is.character(req$postBody)) {
      fromJSON(req$postBody)
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
  
  # B. Validation de la présence des colonnes obligatoires minimales
  missing_raw <- setdiff(required_raw_cols, names(df_input))
  if (length(missing_raw) > 0) {
    res$status <- 400
    return(list(
      error = "Bad Request",
      message = "Colonnes obligatoires manquantes dans le payload.",
      missing_columns = missing_raw
    ))
  }
  
  # C. Validation des types et des bornes (Contrôle métier)
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
  
  # D. Gestion des ID clients
  id_col <- names(df_input)[tolower(names(df_input)) %in% c("customerid", "customer_id", "id_client", "id", "client_id")][1]
  client_ids <- if (!is.na(id_col)) as.character(df_input[[id_col]]) else paste0("CLIENT_", seq_len(nrow(df_input)))
  
  # E. Pipeline de prédiction sécurisé
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
      stringsAsFactors = FALSE
    ))
    
  }, error = function(e) {
    # Log interne pour debug sans exposer les détails techniques au client
    message(sprintf("[ERROR] %s - Erreur d'inférence : %s", Sys.time(), conditionMessage(e)))
    
    res$status <- 500
    return(list(
      error = "Internal Server Error",
      message = "Une erreur est survenue lors du traitement des données ou de la prédiction."
    ))
  })
}

# ============================================================================== #
# 5. Injection de la documentation Swagger                                      #
# ============================================================================== #

#* @plumber
function(pr) {
  pr$setApiSpec(function(spec) {
    spec$paths$`/predict`$post$requestBody <- list(
      description = "Tableau JSON d'observations clients avec validation des bornes.",
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
