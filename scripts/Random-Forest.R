
# Packages
library(randomForest)
library(caret)
library(pROC)

# Read data
source("brouillon/Read-data-version2.R")

set.seed(123)

# ── 1. Split ──────────────────────────────────────────────────────────────────
train_index <- createDataPartition(churn$Churn, p = 0.8, list = FALSE)
train_data  <- churn[ train_index, ]
test_data   <- churn[-train_index, ]

train_data$Churn <- factor(train_data$Churn, levels = c(0, 1))
test_data$Churn  <- factor(test_data$Churn,  levels = c(0, 1))

# ── 2. Hyperparameter tuning (mtry via OOB error) ────────────────────────────
p <- ncol(train_data) - 1          # number of predictors

tuning <- tuneRF(
  x          = train_data[, -which(names(train_data) == "Churn")],
  y          = train_data$Churn,
  mtryStart  = floor(sqrt(p)),
  ntreeTry   = 300,
  stepFactor = 1.5,
  improve    = 0.01,
  trace      = FALSE,
  plot       = FALSE
)

best_mtry <- tuning[which.min(tuning[, "OOBError"]), "mtry"]
cat("Best mtry:", best_mtry, "\n")

# ── 3. Final model ────────────────────────────────────────────────────────────
rf_model <- randomForest(
  Churn ~ .,
  data       = train_data,
  ntree      = 500,
  mtry       = best_mtry,
  importance = TRUE,
  classwt    = c("0" = 1, "1" = sum(train_data$Churn == 0) /   # handle imbalance
                   sum(train_data$Churn == 1))
)

print(rf_model)

# ── 4. Evaluate ───────────────────────────────────────────────────────────────
pred_class <- predict(rf_model, test_data)
pred_prob  <- predict(rf_model, test_data, type = "prob")[, "1"]

confusionMatrix(pred_class, test_data$Churn, positive = "1")

roc_obj <- roc(
  response  = as.numeric(as.character(test_data$Churn)),
  predictor = pred_prob,
  levels    = c(0, 1),
  direction = "<",
  quiet     = TRUE
)

cat("AUC:", auc(roc_obj), "\n")
plot(roc_obj, print.auc = TRUE, main = "ROC – Random Forest")

# ── 5. Variable importance ────────────────────────────────────────────────────
varImpPlot(rf_model, main = "Variable Importance")

# ── 6. Output ─────────────────────────────────────────────────────────────────
model_results_forest <- list(
  model      = rf_model,
  pred_prob  = pred_prob
)