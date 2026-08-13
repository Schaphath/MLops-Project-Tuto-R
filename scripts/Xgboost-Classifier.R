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
#source("scripts/version2/Read-Data.R")

# Importation dataset 
path_df <- here("data", "process")
df <- read.csv(paste(path_df, "df_model1_modif.csv"))

#==============#
#  Split data  #
#==============#
set.seed(123)
train_index <- createDataPartition(df$Churn, p = 0.8, list = FALSE)
train_data  <- df[ train_index, ]
test_data   <- df[-train_index, ]



#============================#
#  Mise en forme de données  #
#============================#
# Extraction des prédicteurs
x_train_df <- train_data[, names(train_data) != "Churn"]
x_test_df  <- test_data[, names(test_data) != "Churn"]


#=============================#
# Standardisation des données #
#=============================#
# Train dataset 
preproc <- preProcess(x_train_df, method = "range")


# Transformation
x_train_df <- predict(preproc, x_train_df)
x_test_df  <- predict(preproc, x_test_df)


# Extraction features
features <- colnames(x_train_df)


# Conversion explicite en matrice numérique
x_train <- as.matrix(sapply(x_train_df, as.numeric))
y_train <- as.numeric(as.character(train_data$Churn))

x_test  <- as.matrix(sapply(x_test_df, as.numeric))
y_test  <- as.numeric(as.character(test_data$Churn))



#======================================#
#  Gestion des classes déséquilibrées  #
#======================================#
scale_pos <- sum(y_train == 0) / sum(y_train == 1)

dtrain <- xgb.DMatrix(data = x_train, label = y_train)
dtest  <- xgb.DMatrix(data = x_test,  label = y_test)


#====================#
#  Cross validation  #
#====================#
grid <- expand.grid(max_depth = c(3, 6, 5, 7, 8),
                    eta = c(0.001, 0.01, 0.05, 0.1),
                    subsample = c(0.7, 0.5, 0.9),
                    colsample_bytree = c(0.7, 0.5, 0.9))



best_auc     <- 0
best_params  <- NULL
best_nrounds <- 100

for (i in seq_len(nrow(grid))) {
  params_i <- list(
    objective = "binary:logistic",
    eval_metric = "auc",
    max_depth = grid$max_depth[i],
    eta = grid$eta[i],
    subsample = grid$subsample[i],
    colsample_bytree = grid$colsample_bytree[i],
    scale_pos_weight = scale_pos,
    seed = 123)
  
  cv <- xgb.cv(params = params_i, data = dtrain,
               nrounds = 500, nfold = 5,
               early_stopping_rounds = 20,
               verbose = 0)
  
  best_idx_i <- which.max(cv$evaluation_log$test_auc_mean)
  auc_i <- cv$evaluation_log$test_auc_mean[best_idx_i]
  
  if (auc_i > best_auc) {
    best_auc <- auc_i
    best_params <- params_i
    best_nrounds <- best_idx_i
  }
}


cat(sprintf("Best CV AUC: %.4f | nrounds: %d\n", best_auc, best_nrounds))



#================#
#  Entrainement  #
#================#
best_params$seed <- NULL

xgb_model <- xgb.train(
  params = best_params,
  data = dtrain,
  nrounds = best_nrounds,
  watchlist = list(train = dtrain, eval = dtest),
  print_every_n = 50,
  verbose = 1
)



#==============#
#  Evaluation  #
#==============#
pred_prob  <- predict(xgb_model, dtest)
pred_class <- factor(as.integer(pred_prob > 0.5), levels = c(0, 1))

#conf_mat_model1 <- confusionMatrix(pred_class, factor(y_test, levels = c(0,  1)), positive = "1")
conf_mat_model2 <- confusionMatrix(pred_class, factor(y_test, levels = c(0,  1)), positive = "1")


roc_obj <- roc(
  response  = y_test,
  predictor = pred_prob,
  levels    = c(0, 1),
  direction = "<",
  quiet     = TRUE
)

cat("AUC:", auc(roc_obj), "\n")
plot(roc_obj, print.auc = TRUE, main = "ROC – Modèle XGBoost ")

#============================#
#  Importance des variables  #
#============================#
importance_matrix <- xgb.importance(feature_names = colnames(x_train), model = xgb_model)
xgb.plot.importance(importance_matrix, main = "Variable Importance – Modèle XGBoost")

#=============#
#  Résultats  #
#=============#
model_results_xgb <- list(
  pred_prob  = pred_prob,
  pred_class = pred_class
)

#=============================#
#  Sauvegarder des artefacts  #
#=============================#
xgb.save(xgb_model, "models/xgb-classifier-model.json")
saveRDS(colnames(x_train), "models/xgb-model-features.rds")
saveRDS(preproc, file = "models/preproc-range.rds")
