
# Auteur : @Schaphath-Madiba


#==============#
#  Read data   #
#==============#
path.churn <- here::here("data", "process")
df <- read.csv(paste(path.churn, "churn_cleaned2.csv", sep = "/"), header = T)
