
# Auteur : @Madiba


#==================================#
#       ENTRAINEMENT XGBOOST       #
#==================================#

library(xgboost)
library(caret)
library(pROC)
library(here)
library(dplyr)


#======================#
# Importation dataset  #
#======================#
path.churn <- here("data", "process")
dfNew <- read.csv(file.path(path.churn, "churn_correcte.csv"), header = T)

# Suppression de la variable non pertinente
#> Après un premier résultats d'entrainement du modèle
#> Nous supprimons la variables MultipleLine_Yes.
#> Sa suppremière améliore la précision de modèle. 

dfNew <- dfNew |> select(-MultipleLines_Yes)


#=================#
#  Split dataset  #
#=================#
set.seed(123)
target_var <- "Churn"
train_index <- createDataPartition(dfNew[[target_var]], p = 0.8, list = F)

train_raw <- dfNew[train_index, ]
test_raw <- dfNew[-train_index, ]

# Features brutes entrantes (sans la cible)
raw_features <- setdiff(names(train_raw), target_var)

# Prétraitement avec CARET (mise à l'échelle 0-1)
caret_prep <- preProcess(train_raw[, raw_features], method = c("range"))

# Application de la standardisation sur le trainset et testset
x_train <- predict(caret_prep, train_raw[, raw_features])
x_test <- predict(caret_prep, test_raw[, raw_features])

y_train <- train_raw[[target_var]]
y_test <- test_raw[[target_var]]

# Format exigé pour l'algorithme xgboost 
dtrain <- xgb.DMatrix(data = as.matrix(x_train), label = y_train)
dtest <- xgb.DMatrix(data = as.matrix(x_test),  label = y_test)


#======================================#
#  Gestion des classes déséquilibrées  #
#======================================#
scale_pos <- sum(y_train == 0) / sum(y_train == 1)


#====================#
#  Cross Validation  #
#====================#
grid <- expand.grid(
  max_depth = c(3, 4, 5, 7),
  eta = c(0.01, 0.05, 0.1),
  subsample = c(0.7, 0.8, 0.9),
  colsample_bytree = c(0.7, 0.8,0.9)
)

best_auc <- 0
best_params <- NULL
best_nrounds <- 100

for (i in seq_len(nrow(grid))) {
  params_i <- list(
    objective = "binary:logistic",
    eval_metric = "auc",
    max_depth = grid$max_depth[i],
    eta = grid$eta[i],
    subsample = grid$subsample[i],
    colsample_bytree = grid$colsample_bytree[i],
    scale_pos_weight = scale_pos
  )
  
  set.seed(123)
  cv <- xgb.cv(
    params = params_i, 
    data = dtrain,
    nrounds = 100, 
    nfold = 10,
    early_stopping_rounds = 20,
    verbose = 1
  )
  
  # Extraction du meilleur tour et du meilleur AUC
  best_idx_i <- which.max(cv$evaluation_log$test_auc_mean)
  auc_i <- cv$evaluation_log$test_auc_mean[best_idx_i]
  
  if (auc_i > best_auc) {
    best_auc <- auc_i
    best_params <- params_i
    best_nrounds <- best_idx_i
  }
}

# Imprimer les meilleurs paramètres
cat(sprintf("Best CV AUC: %.4f | nrounds: %d\n", best_auc, best_nrounds))


#================#
#  Entrainement  #
#================#
xgb_model <- xgb.train(
  params = best_params,
  data = dtrain,
  nrounds = best_nrounds,
  evals = list(train = dtrain),
  print_every_n = 50,
  verbose = 1
)

#======================================#
# Evaluation & Seuil Optimal (Youden)  #
#======================================#
pred_prob <- predict(xgb_model, dtest)

roc_obj <- roc(
  response = y_test,
  predictor = pred_prob,
  levels = c(0, 1),
  direction = "<",
  quiet = TRUE
)

cat("AUC sur jeu de test:", auc(roc_obj), "\n")


# Calcul du seuil optimal via la statistique J de Youden
best_threshold <- coords(roc_obj, "best", best.method = "youden", 
                         ret = c("threshold", "sensitivity", "specificity"))

best_thresh <- best_threshold$threshold
cat(sprintf("Seuil de décision optimal : %.4f (Sensibilité: %.2f | Spécificité: %.2f)\n", best_thresh, best_threshold$sensitivity, best_threshold$specificity))


# Classification avec le seuil optimal
pred_class_opt <- factor(as.integer(pred_prob >= best_thresh), 
                         levels = c(0, 1))

# Matrice de confusion 
conf_mat <- confusionMatrix(pred_class_opt, factor(y_test, 
                                                   levels = c(0, 1)), positive = "1")
# Plot de la courbe ROC
plot(roc_obj, print.auc = TRUE, main = "ROC – XGBoost")


#============================#
#  Importance des variables  #
#============================#
importance_matrix <- xgb.importance(feature_names = colnames(x_train), 
                                    model = xgb_model)

xgb.plot.importance(importance_matrix, main = "Feature Importance XGBoost")


#=============================#
#  Sauvegarde des artefacts   #
#=============================#
models_dir <- here("models") # lien vers le dossier models

if (!dir.exists(models_dir)) dir.create(models_dir)

# Le modèle
xgb.save(xgb_model, file.path(models_dir, "xgb-classifier-model.json"))

# Les featues
saveRDS(raw_features, file.path(models_dir, "xgb-model-features.rds"))

# La standardisation
saveRDS(caret_prep, file.path(models_dir, "caret_prep.rds"))

# Seuil optimal
saveRDS(best_thresh, file.path(models_dir, "optimal_threshold.rds"))

# Dataset final 
write.csv(dfNew, paste(here("data", "process"), "churn_final", sep = "/"),                         row.names = F)
