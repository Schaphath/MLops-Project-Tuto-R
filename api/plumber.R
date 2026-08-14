
# plumber.R
# API REST Plumber pour scoring Churn XGBoost

library(plumber)
library(jsonlite)
library(dplyr)
library(readr)
library(xgboost)
library(recipes)
library(here)

# ================================================= #
# 1. Chargement global des artefacts (Warm-up)     #
# ================================================= #
xgb_model   <- xgb.load(here("models", "xgb-classifier-model.json"))
features    <- readRDS(here("models", "XGB-Model-Features.rds"))
rec_prep    <- readRDS(here("models", "recipe_prep.rds"))

best_thresh <- if (file.exists(here("models", "optimal_threshold.rds"))) {
  readRDS(here("models", "optimal_threshold.rds"))
} else {
  0.5
}

#* @apiTitle XGBoost Churn Prediction API
#* @apiDescription API d'inférence avec normalisation automatique de tenure et MonthlyCharges.
#* @apiVersion 1.0.0


# ================================================= #
# Endpoint : Health Check                           #
# ================================================= #
#* @get /health
#* @serializer json
function(res) {
  list(
    status          = "healthy",
    timestamp       = Sys.time(),
    model_loaded    = !is.null(xgb_model),
    features_count  = length(features),
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
  
  # 1. Parsing sécurisé du body JSON
  body_data <- tryCatch({
    if (is.character(req$postBody)) {
      fromJSON(req$postBody)
    } else {
      req$args$body
    }
  }, error = function(e) {
    res$status <- 400
    return(list(error = "JSON invalide dans le corps de la requête."))
  })
  
  if (is.null(body_data)) {
    res$status <- 400
    return(list(error = "Le corps de la requête est vide."))
  }
  
  df_input <- as.data.frame(body_data)
  
  # 2. Identification / Génération de ID_CLIENT
  id_col <- names(df_input)[tolower(names(df_input)) %in% c("customerid", "customer_id", "id_client", "id", "client_id")][1]
  
  if (!is.na(id_col)) {
    client_ids <- as.character(df_input[[id_col]])
  } else {
    client_ids <- paste0("CLIENT_", seq_len(nrow(df_input)))
  }
  
  tryCatch({
    # 3. Application de la recette (Scaling sur tenure & MonthlyCharges)
    # bake() applique la transformation enregistrée dans recipe_prep.rds
    df_transformed <- bake(rec_prep, new_data = df_input)
    
    # 4. Complétion automatique si une colonne manque
    missing_feats <- setdiff(features, names(df_transformed))
    if (length(missing_feats) > 0) {
      for (col in missing_feats) {
        df_transformed[[col]] <- 0
      }
    }
    
    # 5. Extraction de la matrice numérique alignée sur les 22 features
    X_matrix <- as.matrix(df_transformed[, features, drop = FALSE])
    storage.mode(X_matrix) <- "numeric"
    X_matrix[is.na(X_matrix)] <- 0
    
    # 6. Inférence XGBoost
    pred_probs <- predict(xgb_model, X_matrix)
    pred_class <- ifelse(pred_probs >= best_thresh, 1, 0)
    
    # 7. Résultat
    results <- data.frame(
      id_client     = client_ids,
      churn_proba   = round(pred_probs, 4),
      churn_class   = pred_class,
      decision      = ifelse(pred_class == 1, "Churn", "Non Churn"),
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
              customerID                     = "CLIENT_1",
              SeniorCitizen                  = 0,
              Partner                        = 1,
              Dependents                     = 0,
              tenure                         = 1,
              PaperlessBilling               = 1,
              MonthlyCharges                 = 29.85,
              MultipleLines_No               = 0,
              MultipleLines_No_phone_service = 1,
              MultipleLines_Yes              = 0,
              InternetService_DSL            = 1,
              InternetService_Fiber_optic    = 0,
              InternetService_No             = 0,
              Contract_Month_to_month        = 1,
              Contract_One.year              = 0,
              Contract_Two.year              = 0,
              PaymentMethod_Bank_transfer    = 0,
              PaymentMethod_Credit_card      = 0,
              PaymentMethod_Electronic_check = 1,
              PaymentMethod_Mailed_check     = 0,
              ServiceSup_No                  = 0,
              ServiceSup_No_internet_service = 0,
              ServiceSup_Yes                 = 1
            ),
            list(
              customerID                     = "CLIENT_5",
              SeniorCitizen                  = 0,
              Partner                        = 0,
              Dependents                     = 0,
              tenure                         = 2,
              PaperlessBilling               = 1,
              MonthlyCharges                 = 70.70,
              MultipleLines_No               = 1,
              MultipleLines_No_phone_service = 0,
              MultipleLines_Yes              = 0,
              InternetService_DSL            = 0,
              InternetService_Fiber_optic    = 1,
              InternetService_No             = 0,
              Contract_Month_to_month        = 1,
              Contract_One.year              = 0,
              Contract_Two.year              = 0,
              PaymentMethod_Bank_transfer    = 0,
              PaymentMethod_Credit_card      = 0,
              PaymentMethod_Electronic_check = 1,
              PaymentMethod_Mailed_check     = 0,
              ServiceSup_No                  = 1,
              ServiceSup_No_internet_service = 0,
              ServiceSup_Yes                 = 0
            )
          )
        )
      )
    )
    spec
  })
}

