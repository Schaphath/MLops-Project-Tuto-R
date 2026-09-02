
# Auteur @Madiba

#=============================================#
# API REST Plumber pour scoring Churn XGBoost #      
#=============================================#                                                       

library(plumber)
library(jsonlite)
library(dplyr)
library(xgboost)
library(caret)
library(here)


# Chargement global des artefacts ML                                         #
xgb_model <- tryCatch(xgb.load(here("models", "xgb-classifier-model.json")), error = function(e) NULL)

features <- tryCatch(readRDS(here("models", "xgb-model-features.rds")), error = function(e) NULL)

caret_prep <- tryCatch(readRDS(here("models", "caret_prep.rds")), error = function(e) NULL)

best_thresh <- if (file.exists(here("models", "optimal_threshold.rds"))) {
  readRDS(here("models", "optimal_threshold.rds"))
  } else {
  0.5
    }

# Identification automatique des variables binaires 
binary_features <- setdiff(features, c("tenure", "MonthlyCharges"))


# Métadonnées API & Documentation Swagger                                    #

#* @apiTitle Churn Prediction API
#* @apiDescription API de scoring client basée sur un modèle XGBoost.
#* @apiVersion 1.2.0

# Middleware / Filtre CORS                                                    #
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



# Endpoint : Health Check                                                     #
#* Vérification de l'état de santé de l'API
#* @get /health
#* @serializer json list(auto_unbox = TRUE)
function(res) {
  
  # Diagnostic individuel de chaque artefact
  # --- XGBoost Model ---
  has_model_var <- exists("xgb_model", inherits = TRUE) && !is.null(xgb_model)
  class_model <- if (has_model_var) class(xgb_model) else NULL
  chk_model <- has_model_var && any(c("xgb.Booster", "xgb.Booster.handle") %in% class_model)
  
  # --- Features ---
  has_feat_var <- exists("features", inherits = TRUE) && !is.null(features)
  chk_features <- has_feat_var && is.character(features) && length(features) > 0
  
  # --- Preprocessing (Caret) ---
  has_prep_var  <- exists("caret_prep", inherits = TRUE) && !is.null(caret_prep)
  class_prep <- if (has_prep_var) class(caret_prep) else NULL
  chk_prep <- has_prep_var && any(c("train", "preProcess", "list") %in% class_prep)
  
  # Identification des échecs
  missing_artifacts <- c()
  if (!chk_model) missing_artifacts <- c(missing_artifacts, "xgb_model")
  if (!chk_features) missing_artifacts <- c(missing_artifacts, "features")
  if (!chk_prep) missing_artifacts <- c(missing_artifacts, "caret_prep")
  
  is_healthy <- length(missing_artifacts) == 0
  
  # Réponse en cas d'échec (HTTP 503 Service Unavailable)
  if (!is_healthy) {
    res$status <- 503
    
    return(list(
      status = "unhealthy",
      timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      error_code = "ARTIFACT_MISSING",
      message = sprintf("Dégradation du service : %d artefact(s) manquant(s) ou invalide(s).", length(missing_artifacts)),
      missing_artifacts = missing_artifacts,
      diagnostics = list(
        xgb_model = list(
          loaded = chk_model,
          status = if (chk_model) "OK" else if (!has_model_var) "MISSING" else "INVALID_CLASS",
          detected_class = if (has_model_var) class_model else "none"
        ),
        features = list(
          loaded = chk_features,
          status = if (chk_features) "OK" else if (!has_feat_var) "MISSING" else "EMPTY_OR_INVALID",
          count = if (has_feat_var) length(features) else 0
        ),
        caret_prep = list(
          loaded = chk_prep,
          status = if (chk_prep) "OK" else if (!has_prep_var) "MISSING" else "INVALID_CLASS",
          detected_class = if (has_prep_var) class_prep else "none"
        )
      )
    ))
  }
  
  # Réponse en de succès (HTTP 200 OK)
  res$status <- 200
  list(
    status = "healthy",
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    details = list(
      model_loaded = TRUE,
      features_count = length(features),
      decision_thresh = if (exists("best_thresh", inherits = TRUE)) best_thresh else NA
    )
  )
}



# Endpoint : Scoring Client avec Validation Stricte                          #
#* Prédiction du Churn client
#* @parser json
#* @post /predict
#* @serializer json
function(req, res) {
  
  # Parsing du body JSON
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
  
  # Validation de la présence des colonnes obligatoires
  missing_cols <- setdiff(features, names(df_input))
  if (length(missing_cols) > 0) {
    res$status <- 400
    return(list(
      error = "Bad Request",
      message = "Colonnes obligatoires manquantes dans le payload.",
      missing_columns = missing_cols
    ))
  }
  
  # Validation des bornes métriques
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
  
  # Extraction des identifiants clients
  id_col <- names(df_input)[tolower(names(df_input)) %in% c("customerid", "customer_id", "id_client", "id", "client_id")][1]
  client_ids <- if (!is.na(id_col)) as.character(df_input[[id_col]]) else paste0("CLIENT_", seq_len(nrow(df_input)))
  
  
  # Pipeline de prétraitement Caret et Inférence XGBoost
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
    
    version_model = "1.2.0"
    return(data.frame(
      id_client = client_ids,
      churn_proba = round(pred_probs, 4),
      churn_class = pred_class,
      decision = ifelse(pred_class == 1, "Churn", "Non Churn"),
      version_model = version_model,
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

# Documentation Swagger                                                      #
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