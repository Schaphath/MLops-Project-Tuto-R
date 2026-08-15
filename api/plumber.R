# Auteur @Madiba

# API REST Plumber pour scoring Churn XGBoost

library(plumber)
library(jsonlite)
library(dplyr)
library(xgboost)
library(recipes)

# =================================================#
# 1. Chargement global des artefacts (Warm-up)     #
# =================================================#
# On utilise getwd() (défini par WORKDIR /app dans le Dockerfile) plutôt que
# here::here(), car here() repose sur des heuristiques (.Rproj, .git,
# DESCRIPTION...) absentes d'une image Docker minimale et peut se montrer
# imprévisible.
app_root <- getwd()
models_dir <- file.path(app_root, "models")

xgb_model <- xgb.load(file.path(models_dir, "xgb-classifier-model.json"))
features  <- readRDS(file.path(models_dir, "xgb-model-features.rds"))
rec_prep  <- readRDS(file.path(models_dir, "recipe_prep.rds"))

best_thresh <- if (file.exists(file.path(models_dir, "optimal_threshold.rds"))) {
  readRDS(file.path(models_dir, "optimal_threshold.rds"))
} else {
  0.5
}

# Colonnes brutes minimales attendues en entrée (avant bake()).
# A adapter précisément à votre recette si besoin.
required_raw_cols <- c("tenure", "MonthlyCharges")

#* @apiTitle XGBoost Churn Prediction API
#* @apiDescription API d'inférence avec normalisation automatique de tenure et MonthlyCharges.
#* @apiVersion 1.0.0

# ================================================= #
# Filtre CORS (nécessaire si appel depuis un navigateur / frontend web)
# ================================================= #
#* @filter cors
function(req, res) {
  res$setHeader("Access-Control-Allow-Origin", "*")
  if (req$REQUEST_METHOD == "OPTIONS") {
    res$setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
    res$setHeader("Access-Control-Allow-Headers", "Content-Type")
    res$status <- 200
    return(list())
  } else {
    plumber::forward()
  }
}

# ================================================= #
# Endpoint : Health Check                           #
# ================================================= #
#* @get /health
#* @serializer json
function(res) {
  list(
    status = "healthy",
    timestamp = Sys.time(),
    model_loaded = !is.null(xgb_model),
    features_count = length(features),
    decision_thresh = best_thresh
  )
}

# ================================================= #
# Endpoint : Scoring Client                         #
# ================================================= #
#* Prédiction de Churn pour un ou plusieurs clients
#* @parser json
#* @post /predict
#* @serializer json
#* @param req:object Payload JSON contenant les variables brutes et dummifiées.
function(req, res) {
  
  # 1. Parsing sécurisé du body JSON.
  # IMPORTANT: le handler d'erreur renvoie NULL (et non une liste "error=..."),
  # afin que le test `is.null(body_data)` ci-dessous puisse réellement
  # intercepter le cas d'échec et stopper le traitement avec un 400 propre.
  body_data <- tryCatch({
    if (is.character(req$postBody)) {
      fromJSON(req$postBody)
    } else {
      req$args$body
    }
  }, error = function(e) {
    NULL
  })
  
  if (is.null(body_data) || length(body_data) == 0) {
    res$status <- 400
    return(list(error = "JSON invalide ou corps de requête vide."))
  }
  
  df_input <- tryCatch({
    as.data.frame(body_data)
  }, error = function(e) {
    NULL
  })
  
  if (is.null(df_input) || nrow(df_input) == 0) {
    res$status <- 400
    return(list(error = "Impossible d'interpréter le payload comme un tableau d'observations."))
  }
  
  # 2. Validation des colonnes brutes minimales attendues avant bake()
  missing_raw <- setdiff(required_raw_cols, names(df_input))
  if (length(missing_raw) > 0) {
    res$status <- 400
    return(list(
      error = "Colonnes obligatoires manquantes dans le payload.",
      missing_columns = missing_raw
    ))
  }
  
  # 3. Identification / Génération de ID_CLIENT
  id_col <- names(df_input)[tolower(names(df_input)) %in% c("customerid", "customer_id", "id_client", "id", "client_id")][1]
  
  if (!is.na(id_col)) {
    client_ids <- as.character(df_input[[id_col]])
  } else {
    client_ids <- paste0("CLIENT_", seq_len(nrow(df_input)))
  }
  
  tryCatch({
    # 4. Application de la recette (Scaling sur tenure & MonthlyCharges)
    # bake() applique la transformation enregistrée dans recipe_prep.rds
    df_transformed <- bake(rec_prep, new_data = df_input)
    
    # 5. Complétion automatique si une colonne manque
    missing_feats <- setdiff(features, names(df_transformed))
    if (length(missing_feats) > 0) {
      for (col in missing_feats) {
        df_transformed[[col]] <- 0
      }
    }
    
    # 6. Extraction de la matrice numérique alignée sur les features attendues
    X_matrix <- as.matrix(df_transformed[, features, drop = FALSE])
    storage.mode(X_matrix) <- "numeric"
    X_matrix[is.na(X_matrix)] <- 0
    
    # 7. Inférence XGBoost
    pred_probs <- predict(xgb_model, X_matrix)
    pred_class <- ifelse(pred_probs >= best_thresh, 1, 0)
    
    # 8. Résultat
    results <- data.frame(
      id_client = client_ids,
      churn_proba = round(pred_probs, 4),
      churn_class = pred_class,
      decision = ifelse(pred_class == 1, "Churn", "Non Churn"),
      stringsAsFactors = FALSE
    )
    
    res$status <- 200
    return(results)
    
  }, error = function(e) {
    res$status <- 500
    return(list(
      error = "Erreur lors du traitement des données ou de la prédiction.",
      details = conditionMessage(e)
    ))
  })
}

# ================================================= #
# 3. Injection des données exactes dans Swagger UI #
# ================================================= #
#* @plumber
function(pr) {
  pr$setApiSpec(function(spec) {
    spec$paths$`/predict`$post$requestBody <- list(
      description = "Saisissez les données clients (tenure et MonthlyCharges non transformées).",
      required = TRUE,
      content = list(
        `application/json` = list(
          schema = list(type = "array", items = list(type = "object")),
          example = list(
            list(
              SeniorCitizen = 0,
              Partner = 1,
              Dependents = 0,
              tenure = 12,
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
            ),
            list(
              SeniorCitizen = 0,
              Partner = 1,
              Dependents = 0,
              tenure = 36,
              PaperlessBilling = 1,
              MonthlyCharges = 80.99,
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