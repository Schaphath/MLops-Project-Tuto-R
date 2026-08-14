
#=============#
#  Packages   #
#=============#
library(randomForest)
library(caret)
library(pROC)
library(recipes)
library(here)


#=============#
#  Read data  #
#=============#

# Importation dataset 
path.churn <- here("data", "process")
dfNew <- read.csv(paste(path.churn, "dfNew.csv", sep = "/"))


dfNew$Churn <- factor(dfNew$Churn, levels = c(0, 1))

#==============#
#  Split data  #
#==============#
set.seed(123)
train_index <- createDataPartition(dfNew$Churn, p = 0.8, list = FALSE)
train_data  <- dfNew[ train_index, ]
test_data   <- dfNew[-train_index, ]


#======================================#
# Preprocessing (Dummy variables)      #
#======================================#
rec <- recipe(Churn ~ ., data = train_data) %>%
  step_zv(all_predictors()) %>%
  step_range(all_nominal_predictors())

rec_prep <- prep(rec, training = train_data)

x_train <- bake(rec_prep, new_data = NULL) %>% select(-Churn)
x_test  <- bake(rec_prep, new_data = test_data) %>% select(-Churn)

y_train <- train_data$Churn
y_test  <- test_data$Churn


#======================================#
# Hyperparameter Tuning (mtry)         #
#======================================#
p <- ncol(x_train)

tuning <- tuneRF(
  x          = x_train,
  y          = y_train,
  mtryStart  = floor(sqrt(p)),
  ntreeTry   = 300,
  stepFactor = 1.5,
  improve    = 0.01,
  trace      = FALSE,
  plot       = FALSE
)

best_mtry <- tuning[which.min(tuning[, "OOBError"]), "mtry"]
cat("Best mtry:", best_mtry, "\n")

#======================================#
# Final Model (Stratified Sampling)    #
#======================================#
# Calcul de la taille de la classe minoritaire pour équilibrer chaque arbre
n_min <- min(table(y_train))

rf_model <- randomForest(
  x          = x_train,
  y          = y_train,
  ntree      = 500,
  mtry       = best_mtry,
  importance = TRUE,
  sampsize   = c("0" = n_min, "1" = n_min) # Balanced Random Forest
)

print(rf_model)

#======================================#
# Evaluation & Seuil Optimal (Youden)  #
#======================================#
pred_prob <- predict(rf_model, newdata = x_test, type = "prob")[, "1"]

roc_obj <- roc(
  response  = y_test,
  predictor = pred_prob,
  levels    = c(0, 1),
  direction = "<",
  quiet     = TRUE
)

cat("AUC Random Forest:", auc(roc_obj), "\n")

# Seuil optimal
best_threshold_info <- coords(roc_obj, "best", best.method = "youden", ret = c("threshold", "sensitivity", "specificity"))
best_thresh <- best_threshold_info$threshold

cat(sprintf("Seuil optimal : %.4f (Sensibilité: %.2f | Spécificité: %.2f)\n", 
            best_thresh, best_threshold_info$sensitivity, best_threshold_info$specificity))

# Classification basée sur le nouveau seuil
pred_class_opt <- factor(ifelse(pred_prob >= best_thresh, "1", "0"), levels = c("0", "1"))

conf_mat_opt <- confusionMatrix(pred_class_opt, y_test, positive = "1")
print(conf_mat_opt)

# Graphiques
plot(roc_obj, print.auc = TRUE, main = "ROC – Random Forest (Seuil Optimal)")
varImpPlot(rf_model, main = "Variable Importance – Random Forest")

#======================================#
# Sauvegarde des artefacts             #
#======================================#
saveRDS(rf_model,    here("models", "rf_churn_model.rds"))
saveRDS(rec_prep,    here("models", "recipe_rf_prep.rds"))
saveRDS(best_thresh, here("models", "rf_optimal_threshold.rds"))

