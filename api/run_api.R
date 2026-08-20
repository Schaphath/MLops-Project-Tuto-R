
# Auteur @Madiba


library(plumber)
library(here)

pr <- plumber::pr(here("api", "api.R"))

# Lancement du serveur HTTP sur le port 8080
pr |> 
  pr_run(host = "0.0.0.0", port = 8080)

