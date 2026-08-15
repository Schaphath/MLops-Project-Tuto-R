

# Auteur : @Madiba


##========================================##
##      ENTRAINEMENT MODELE XGBOOST       ##
##========================================##

#=============#
#  Packages   #
#=============#
library(xgboost)
library(caret)
library(recipes)
library(pROC)
library(here)


#=============#
#  Read data  #
#=============#
# Importation dataset 
path.churn <- here::here("data", "process")
dfNew <- read.csv(paste(path.churn, "dfNew.csv", sep = "/"), header = T)



#==============#
#  Split data  #
#==============#

library(recipes)
library(caret)
library(xgboost)

SplitData <- function(data, target_var, prop = 0.8, seed = 123, to_global_env = TRUE) {
  
  set.seed(seed)
  
  if (!target_var %in% names(data)) {
    stop(paste("La colonne target", target_var, "est introuvable."))
  }
  
  train_index <- createDataPartition(data[[target_var]], p = prop, list = FALSE)
  train_data  <- data[train_index, ]
  test_data   <- data[-train_index, ]
  
  rec_formula <- as.formula(paste(target_var, "~ ."))
  
  rec <- recipe(rec_formula, data = train_data) |>
    step_zv(all_predictors()) |> 
    step_range(all_numeric_predictors())
  
  rec_prep <- prep(rec, training = train_data)
  
  train_processed <- bake(rec_prep, new_data = NULL)
  test_processed  <- bake(rec_prep, new_data = test_data)
  
  x_train_df <- train_processed[, setdiff(names(train_processed), target_var)]
  x_test_df  <- test_processed[,  setdiff(names(test_processed),  target_var)]
  
  out_list <- list(
    features = colnames(x_train_df),
    dtrain   = xgb.DMatrix(data = as.matrix(x_train_df), label = train_processed[[target_var]]),
    dtest    = xgb.DMatrix(data = as.matrix(x_test_df),  label = test_processed[[target_var]]),
    rec_prep = rec_prep,
    y_train  = train_processed[[target_var]],
    y_test   = test_processed[[target_var]]
  )
  
  # Export automatique vers l'environnement global si activé
  if (to_global_env) {
    list2env(out_list, envir = .GlobalEnv)
    message("Les objets (features, dtrain, dtest, rec_prep, y_train, y_test) ont été ajoutés à l'environnement global.")
  }
  
  return(invisible(out_list))
}


#======================================#
#  Gestion des classes déséquilibrées  #
#======================================#
scale_pos <- sum(y_train == 0) / sum(y_train == 1)


#====================#
#  Cross Validation  #
#====================#
grid <- expand.grid(
  max_depth = c(3, 5, 7),
  eta = c(0.01, 0.05, 0.1),
  subsample = c(0.7, 0.9),
  colsample_bytree = c(0.7, 0.9)
)

best_auc     <- 0
best_params  <- NULL
best_nrounds <- 100

for (i in seq_len(nrow(grid))) {
  params_i <- list(
    objective        = "binary:logistic",
    eval_metric      = "auc",
    max_depth        = grid$max_depth[i],
    eta              = grid$eta[i],
    subsample        = grid$subsample[i],
    colsample_bytree = grid$colsample_bytree[i],
    scale_pos_weight = scale_pos
  )
  
  set.seed(123)
  cv <- xgb.cv(
    params = params_i, 
    data = dtrain,
    nrounds = 500, 
    nfold = 5,
    early_stopping_rounds = 20,
    verbose = 0
  )
  
  # Extraction robuste du meilleur tour et du meilleur AUC
  best_idx_i <- which.max(cv$evaluation_log$test_auc_mean)
  auc_i      <- cv$evaluation_log$test_auc_mean[best_idx_i]
  
  if (auc_i > best_auc) {
    best_auc     <- auc_i
    best_params  <- params_i
    best_nrounds <- best_idx_i
  }
}

cat(sprintf("Best CV AUC: %.4f | nrounds: %d\n", best_auc, best_nrounds))


#================#
#  Entrainement  #
#================#
xgb_model <- xgb.train(
  params        = best_params,
  data          = dtrain,
  nrounds       = best_nrounds,
  evals        = list(train = dtrain),
  print_every_n = 50,
  verbose       = 1
)

#======================================#
# Evaluation & Seuil Optimal (Youden)  #
#======================================#
pred_prob <- predict(xgb_model, dtest)

roc_obj <- roc(
  response  = y_test,
  predictor = pred_prob,
  levels    = c(0, 1),
  direction = "<",
  quiet     = TRUE
)

cat("AUC sur jeu de test:", auc(roc_obj), "\n")


# Calcul du seuil optimal via la statistique J de Youden
best_threshold_info <- coords(roc_obj, "best", best.method = "youden", 
                              ret = c("threshold", "sensitivity", "specificity"))

best_thresh <- best_threshold_info$threshold

cat(sprintf("Seuil de décision optimal : %.4f (Sensibilité: %.2f | Spécificité: %.2f)\n", 
            best_thresh, best_threshold_info$sensitivity, best_threshold_info$specificity))


# Classification avec le seuil seuil optimal
pred_class_opt <- factor(as.integer(pred_prob >= best_thresh), levels = c(0, 1))


# Matrice de confusion 
conf_mat_opt <- confusionMatrix(pred_class_opt, factor(y_test, levels = c(0, 1)), positive = "1")
print(conf_mat_opt)


# Plot de la courbe ROC
plot(roc_obj, print.auc = TRUE, main = "ROC – XGBoost (Seuil optimal)")


#============================#
#  Importance des variables  #
#============================#
importance_matrix <- xgb.importance(feature_names = colnames(x_train), model = xgb_model)
xgb.plot.importance(importance_matrix[1:15, ], main = "Top 15 - Feature Importance XGBoost")


#=============================#
#  Sauvegarde des artefacts   #
#=============================#
xgb.save(xgb_model, here("models", "xgb-classifier-model.json"))
saveRDS(colnames(x_train), "models/xgb-model-features.rds")
saveRDS(rec_prep, file = here("models", "recipe_prep.rds"))
saveRDS(best_thresh, file = here("models", "optimal_threshold.rds"))

