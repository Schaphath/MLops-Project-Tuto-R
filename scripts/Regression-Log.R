

# Librairies 
library(caret)
library(pROC)
library(dplyr)



# Read data 
# source("brouillon/Read-data-version2.R")

# Importation dataset 
path_df <- here("data", "process")
df <- read.csv(paste(path_df, "df_model1_modif.csv"))

# Split data 
set.seed(123)
train_index <- createDataPartition(churn$Churn, p = 0.8, list = FALSE)
train_data <- churn[train_index, ]
test_data  <- churn[-train_index, ]


# Train dataset 
preproc <- preProcess(train_data, method = "range")

# Transformation
train_data <- predict(preproc, train_data)
test_data  <- predict(preproc, test_data)

# Extraction features
features <- colnames(train_data)

# target as factor 
#df$Churn <- as.factor(df$Churn)

# Regression logistique 
model_logit <- glm(Churn ~ ., data = train_data, family = "binomial")


summary(model_logit)


pred_prob <- predict(model_logit, test_data, type = "response")
pred_class <- ifelse(pred_prob > 0.5, 1, 0)


confusionMatrix(
  factor(pred_class),
  factor(test_data$Churn),
  positive = "1"
)


roc_obj <- roc(
  response = test_data$Churn,
  predictor = pred_prob,
  levels = c(0,1), 
  direction = "<"
)


auc(roc_obj)
plot(roc_obj, print.auc = TRUE)

exp(coef(model_logit))


model_results_log <- list(
  pred_prob = pred_prob,
  pred_class = pred_class
)
