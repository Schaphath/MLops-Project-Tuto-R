

# Auteur : @Madiba


#==============#
#  Read data   #
#==============#
path.churn <- here::here("data", "process")
df <- read.csv(paste(path.churn, "dfNew.csv", sep = "/"), header = T)
