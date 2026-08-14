
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
path.churn <- here("data", "process")
dfNew <- read.csv(file.path(path.churn, "dfNew.csv"))

# Assure que Churn est bien binaire (0 / 1)
dfNew$Churn <- as.numeric(as.character(dfNew$Churn))


#==============#
#  Split data  #
#==============#
set.seed(123)
train_index <- createDataPartition(dfNew$Churn, p = 0.8, list = FALSE)
train_data  <- dfNew[ train_index, ]
test_data   <- dfNew[-train_index, ]


#======================================#
# Preprocessing & One-Hot Encoding      #
#======================================#
rec <- recipe(Churn ~ ., data = train_data) %>%
  step_zv(all_predictors()) %>%
  step_range(all_numeric_predictors())

rec_prep <- prep(rec, training = train_data)


# Application sur Train et Test
x_train_df <- bake(rec_prep, new_data = NULL) %>% select(-Churn)
x_test_df  <- bake(rec_prep, new_data = test_data) %>% select(-Churn)

y_train <- train_data$Churn
y_test  <- test_data$Churn


# Extraction features
features <- colnames(x_train_df)


# Construction des matrices numériques XGBoost
x_train <- as.matrix(x_train_df)
x_test  <- as.matrix(x_test_df)

dtrain <- xgb.DMatrix(data = x_train, label = y_train)
dtest  <- xgb.DMatrix(data = x_test,  label = y_test)


#======================================#
#  Gestion des classes déséquilibrées  #
#======================================#
scale_pos <- sum(y_train == 0) / sum(y_train == 1)


#====================#
#  Cross Validation  #
#====================#
grid <- expand.grid(
  max_depth        = c(3, 5, 7),
  eta              = c(0.01, 0.05, 0.1),
  subsample        = c(0.7, 0.9),
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
    params                = params_i, 
    data                  = dtrain,
    nrounds               = 500, 
    nfold                 = 5,
    early_stopping_rounds = 20,
    verbose               = 0
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
  watchlist     = list(train = dtrain, eval = dtest),
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

