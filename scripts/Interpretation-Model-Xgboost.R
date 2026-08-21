

# Auteur : @Madiba


#=========================================#
#   Interprétation du modèle XGBoost      #
#=========================================#

#============#
#  Packages  #
#============#
library(xgboost)
library(SHAPforxgboost)
library(ggplot2)
library(caret)
library(dplyr)
library(tidyr)
library(pROC)
library(scales)
library(recipes)
library(here)


#=================#
#  Thème visuel   #
#=================#
COLORS <- list(
  bg = "#0f1117", panel = "#1a1d2e", border = "#2a2d3a",
  text = "#c5c9e8", muted = "#555870",
  violet = "#7c83fd", cyan = "#38bdf8",
  green = "#34d399", red = "#f87171", yellow = "#fbbf24"
)


theme_churn <- function(base_size = 13) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.background = element_rect(fill = COLORS$bg, color = NA),
      panel.background = element_rect(fill = COLORS$panel, color = NA),
      panel.grid.major = element_line(color = COLORS$border, linewidth = 0.4),
      panel.grid.minor = element_blank(),
      panel.border = element_rect(color = COLORS$border, fill = NA, linewidth = 0.6),
      axis.text = element_text(color = COLORS$muted, size = 12),
      axis.title = element_text(color = COLORS$text, size = 12, face = "bold"),
      
      # Utilisation explicite de ggplot2::margin()
      plot.title = element_text(color = COLORS$text,  size = 16, face = "bold", margin = ggplot2::margin(b = 6)),
      plot.subtitle = element_text(color = COLORS$muted, size = 12, margin = ggplot2::margin(b = 14)),
      plot.caption = element_text(color = COLORS$muted, size = 10, hjust = 0, face = "italic"),
      
      legend.background = element_rect(fill = COLORS$panel, color = NA),
      legend.text = element_text(color = COLORS$text,  size = 10),
      legend.title = element_text(color = COLORS$muted, size = 10),
      plot.margin = ggplot2::margin(20, 20, 20, 20)
    )
}


# Création de repetoire pour image
dir.create(here("plots"), recursive = TRUE, showWarnings = FALSE)

# Fonction de sauvegarde
save_plot <- function(name, w = 10, h = 6) {
  file_path <- here("plots", paste0(name, ".png"))
  ggsave(file_path, width = w, height = h, dpi = 180, bg = COLORS$bg)
  message("Sauvegardé : ", file_path)
}


#=========================================#
#  Chargement des données & artefacts     #
#=========================================#
dfNew <- read.csv(paste(here("data", "process"), "churn_correcte.csv", sep = "/"))
dfNew$Churn <- as.numeric(as.character(dfNew$Churn))

# Suppression de la variable Multiplelines_Yes
dfNew <- dfNew |> select(-MultipleLines_Yes)


set.seed(123)
train_index <- createDataPartition(dfNew$Churn, p = 0.8, list = FALSE)
test_data <- dfNew[-train_index, ]

# Chargement du modèle et artefacts
xgb_model <- xgb.load(here("models", "xgb-classifier-model.json"))
rec_prep <- readRDS(here("models", "recipe_prep.rds"))
best_thresh <- if(file.exists(here("models", "optimal_threshold.rds"))) readRDS(here("models", "optimal_threshold.rds")) else 0.5

# Application du prétraitement d'entraînement
x_test_df  <- bake(rec_prep, new_data = test_data) %>% select(-Churn)
x_test_mat <- as.matrix(x_test_df)
y_test <- test_data$Churn

# Prédictions
pred_prob <- predict(xgb_model, x_test_mat)
pred_class <- as.integer(pred_prob >= best_thresh)



#============================================#
#  SORTIE 1 — Métriques clés de performance  #
#============================================#
cm <- confusionMatrix(
  factor(pred_class, levels = c(0, 1)),
  factor(y_test, levels = c(0, 1)), 
  positive = "1"
)

roc_obj <- roc(y_test, pred_prob, quiet = TRUE)
auc_val <- round(as.numeric(auc(roc_obj)), 3)

metrics_df <- data.frame(
  Indicateur = c(
    "AUC (pouvoir discriminant)",
    "Précision globale",
    "Détection des churners (Rappel)",
    "Précision sur les alertes (Précision)",
    "Score équilibré (F1)"
  ),
  Valeur = c(
    auc_val,
    round(cm$overall["Accuracy"], 3),
    round(cm$byClass["Recall"], 3),
    round(cm$byClass["Precision"], 3),
    round(cm$byClass["F1"], 3)
  )
) %>%
  mutate(
    Pct = paste0(round(Valeur * 100, 1), "%"),
    Couleur = case_when(
      Valeur >= 0.80 ~ COLORS$green,
      Valeur >= 0.65 ~ COLORS$yellow,
      TRUE ~ COLORS$red
    )
  )

p_metrics <- ggplot(metrics_df, aes(x = reorder(Indicateur, Valeur), y = Valeur, fill = Couleur)) +
  geom_col(width = 0.55, show.legend = FALSE) +
  geom_text(aes(label = Pct, color = Couleur),
            hjust = -0.15, size = 4.5, fontface = "bold", show.legend = FALSE) +
  scale_fill_identity() + scale_color_identity() +
  scale_y_continuous(limits = c(0, 1.12), labels = percent) +
  coord_flip() +
  labs(title = "Le modèle est-il fiable ?",
       subtitle = paste0("Performance sur jeu de test (Seuil de décision : ", round(best_thresh, 3), ")"),
       x = NULL, y = "Score",
       caption = "Vert ≥ 80 % · Jaune ≥ 65 % · Rouge < 65 %") +
  theme_churn()

print(p_metrics)
save_plot("01_performance_cles")



#===========================#
#  SORTIE 2 — Courbe ROC    #
#===========================#
roc_df <- data.frame(FPR = 1 - roc_obj$specificities, TPR = roc_obj$sensitivities)

p_roc <- ggplot(roc_df, aes(x = FPR, y = TPR)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed",
              color = COLORS$muted, linewidth = 0.9) +
  geom_area(aes(ymin = 0), fill = COLORS$violet, alpha = 0.15) +
  geom_line(color = COLORS$violet, linewidth = 1.8) +
  annotate("text", x = 0.02, y = 0.99, hjust = 0,
           label = "Modèle parfait", color = COLORS$muted, size = 3.5, fontface = "italic") +
  annotate("text", x = 0.60, y = 0.52, hjust = 0,
           label = "Hasard (50/50)", color = COLORS$muted, size = 3.5, fontface = "italic") +
  annotate("label", x = 0.62, y = 0.22,
           label = paste0("AUC = ", auc_val, "\n\"Bon modèle\""),
           color = COLORS$cyan, fill = COLORS$panel,
           label.border = unit(0.4, "lines"),
           size = 4.2, fontface = "bold") +
  scale_x_continuous(labels = percent, name = "Faux positifs déclenchés (clients stables alertés)") +
  scale_y_continuous(labels = percent, name = "Vrais churners détectés") +
  labs(title = "Capacité du modèle à distinguer churners et clients stables",
       subtitle = "Plus la courbe est haute et à gauche, meilleur est le pouvoir discriminant",
       caption  = "AUC > 0.80 = bon modèle · AUC > 0.90 = excellent modèle") +
  theme_churn()


print(p_roc)
save_plot("02_courbe_roc")



#======================================#
#  SORTIE 3 : Importance des features  #
#======================================#
importance_matrix <- xgb.importance(feature_names = colnames(x_test_mat), model = xgb_model)

imp_top10 <- importance_matrix %>%
  arrange(desc(Gain)) %>%
  slice_head(n = 10) %>%
  mutate(Feature = factor(Feature, levels = rev(Feature)),
         Pct = paste0(round(Gain * 100, 1), "%"))

p_importance <- ggplot(imp_top10, aes(x = Feature, y = Gain, fill = Gain)) +
  geom_col(width = 0.6, show.legend = FALSE) +
  geom_text(aes(label = Pct),
            hjust = -0.15, color = COLORS$text, size = 3.8, fontface = "bold") +
  scale_fill_gradient(low = COLORS$violet, high = COLORS$cyan) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.2)), labels = percent) +
  coord_flip() +
  labs(title = "Quelles informations client influencent le plus le modèle ?",
       subtitle = "Top 10 des variables contributrices au gain d'information",
       x = NULL, y = "Importance (%)",
       caption = "Métrique : Gain d'information moyen lors des décisions du modèle") +
  theme_churn()

print(p_importance)
save_plot("03_importance_features")



#====================================================================#
#  SORTIE 4 : Impact SHAP des variables sur la probabilité de churn  #
#====================================================================#
shap_long <- shap.prep(xgb_model = xgb_model, X_train = x_test_mat, top_n = 10)

p_shap <- shap.plot.summary(shap_long) +
  scale_color_gradient(
    low = COLORS$cyan,
    high = COLORS$red,
    name = "Valeur\n(faible → élevée)") + 
  labs(title = "Quel est l'impact de chaque variable sur le risque de churn ?",
       subtitle = "Point = 1 client | Rouge = valeur élevée | Droite = pousse vers le churn",
       caption = "Méthode SHAP : décomposition locale des décisions") +
  theme_churn() +
  theme(legend.position = "right")


print(p_shap)
save_plot("04_shap_impact_variables", w = 12, h = 8)

