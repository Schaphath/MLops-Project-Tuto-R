

# @Madiba

# ====================================================================#
# Génération d'un jeu de prédiction out-of-sample (1 000 clients)    #
# Sans la variable cible Churn - Conforme au modèle XGBoost / Shiny   #
# ====================================================================#

library(dplyr)
library(here)

# Fixer la graine pour la reproductibilité
set.seed(2026)

# Nombre d'observations souhaité
n <- 1000 

# Charger le dataset
path_churn <- here("data", "process")
df_new <- read.csv(file.path(path_churn, "dfNew.csv"))

# Tirage aléatoire sans remise et suppression de la variable cible "Churn"
df_sample <- df_new %>%
  slice_sample(n = min(n, nrow(.))) %>%
  select(-matches("^Churn$", ignore.case = TRUE))


#Sauvegarde en fichier CSV
write.csv(df_sample, file = "app/test_sample.csv",row.names = F)

