

# Auteur @Madiba




# ============================================================================== #
# API REST Plumber pour scoring Churn XGBoost (Caret & Production-Ready)        #
# Auteur : Madiba                                                                #
# ============================================================================== #

library(plumber)
library(jsonlite)
library(dplyr)
library(xgboost)
library(caret)
library(here)

# ============================================================================== #
# 1. Chargement global des artefacts ML                                         #
# ============================================================================== #

xgb_model  <- tryCatch(xgb.load(here("models", "xgb-classifier-model.json")), error = function(e) NULL)
features   <- tryCatch(readRDS(here("models", "xgb-model-features.rds")), error = function(e) NULL)
caret_prep <- tryCatch(readRDS(here("models", "caret_prep.rds")), error = function(e) NULL)

best_thresh <- if (file.exists(here("models", "optimal_threshold.rds"))) {
  readRDS(here("models", "optimal_threshold.rds"))
} else {
  0.5
}

# Identification automatique des variables binaires (excluant tenure et MonthlyCharges)
binary_features <- setdiff(features, c("tenure", "MonthlyCharges"))

# ============================================================================== #
# 2. Métadonnées API & Documentation Swagger                                    #
# ============================================================================== #

#* @apiTitle Churn Prediction API
#* @apiDescription API de scoring client basée sur un modèle XGBoost et un prétraitement Caret.
#* @apiVersion 1.3.0

# ============================================================================== #
# 3. Middleware / Filtre CORS                                                    #
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
# 4. Endpoint : Health Check                                                     #
# ============================================================================== #

#* Vérifier l'état de santé du service et la disponibilité des artefacts
#* @get /health
#* @serializer json
function(res) {
  
  chk_model    <- !is.null(xgb_model)
  chk_features <- !is.null(features)
  chk_prep     <- !is.null(caret_prep)
  
  is_healthy <- chk_model && chk_features && chk_prep
  
  if (!is_healthy) {
    res$status <- 503
    return(list(
      status = "unhealthy",
      working_dir = getwd(),
      diagnostic = list(
        model_loaded = chk_model,
        features_loaded = chk_features,
        caret_prep_loaded = chk_prep
      )
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
# 5. Endpoint : Scoring Client avec Validation Stricte                          #
# ============================================================================== #

#* Prédiction du Churn client
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
  
  # B. Validation de la présence des colonnes obligatoires
  missing_cols <- setdiff(features, names(df_input))
  if (length(missing_cols) > 0) {
    res$status <- 400
    return(list(
      error = "Bad Request",
      message = "Colonnes obligatoires manquantes dans le payload.",
      missing_columns = missing_cols
    ))
  }
  
  # C. Validation des bornes métriques
  if ("tenure" %in% names(df_input)) {
    if (any(!is.numeric(df_input$tenure) | df_input$tenure < 0, na.rm = TRUE)) {
      res$status <- 400
      return(list(
        error = "Bad Request",
        message = "Validation invalide : la variable 'tenure' doit être un nombre supérieur ou égal à 0 (>= 0)."
      ))
    }
  }
  
  # Contrôle strict : MonthlyCharges strictement supérieur à 0
  if ("MonthlyCharges" %in% names(df_input)) {
    if (any(!is.numeric(df_input$MonthlyCharges) | df_input$MonthlyCharges <= 0, na.rm = TRUE)) {
      res$status <- 400
      return(list(
        error = "Bad Request",
        message = "Validation invalide : la variable 'MonthlyCharges' doit être un nombre strictement supérieur à 0 (> 0)."
      ))
    }
  }
  
  # Contrôle strict : Variables binaires (uniquement 0 ou 1)
  cols_to_check_binary <- intersect(binary_features, names(df_input))
  invalid_binary_cols <- c()
  
  for (col in cols_to_check_binary) {
    vals <- df_input[[col]]
    if (any(is.na(vals) | !vals %in% c(0, 1))) {
      invalid_binary_cols <- c(invalid_binary_cols, col)
    }
  }
  
  if (length(invalid_binary_cols) > 0) {
    res$status <- 400
    return(list(
      error = "Bad Request",
      message = "Validation invalide : les variables binaires doivent uniquement contenir les valeurs 0 ou 1.",
      invalid_columns = invalid_binary_cols
    ))
  }
  
  # D. Extraction des identifiants clients
  id_col <- names(df_input)[tolower(names(df_input)) %in% c("customerid", "customer_id", "id_client", "id", "client_id")][1]
  client_ids <- if (!is.na(id_col)) as.character(df_input[[id_col]]) else paste0("CLIENT_", seq_len(nrow(df_input)))
  
  # E. Pipeline de prétraitement Caret et Inférence XGBoost
  tryCatch({
    # Application de la transformation Caret (step_range)
    df_scaled <- predict(caret_prep, df_input[, features, drop = FALSE])
    
    # Conversion sécurisée en matrice numérique ordonnée
    X_matrix <- as.matrix(df_scaled[, features, drop = FALSE])
    storage.mode(X_matrix) <- "numeric"
    X_matrix[is.na(X_matrix)] <- 0
    
    # Inférence XGBoost
    pred_probs <- predict(xgb_model, X_matrix)
    pred_class <- ifelse(pred_probs >= best_thresh, 1, 0)
    
    res$status <- 200
    return(data.frame(
      id_client   = client_ids,
      churn_proba = round(pred_probs, 4),
      churn_class = pred_class,
      decision    = ifelse(pred_class == 1, "Churn", "Non Churn"),
      stringsAsFactors = FALSE
    ))
    
  }, error = function(e) {
    message(sprintf("[ERROR] %s - Erreur d'inférence : %s", Sys.time(), conditionMessage(e)))
    
    res$status <- 500
    return(list(
      error = "Internal Server Error",
      message = "Une erreur est survenue lors du traitement des données ou de la prédiction."
    ))
  })
}

# ============================================================================== #
# 6. Documentation Swagger                                                      #
# ============================================================================== #

#* @plumber
function(pr) {
  pr$setApiSpec(function(spec) {
    spec$paths$`/predict`$post$requestBody <- list(
      description = "Tableau JSON d'observations clients.",
      required = TRUE,
      content = list(
        `application/json` = list(
          schema = list(type = "array", items = list(type = "object"))
        )
      )
    )
    spec
  })
}