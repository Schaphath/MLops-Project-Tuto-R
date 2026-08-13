

# @Madiba

# ====================================================================#
# Génération d'un jeu de prédiction out-of-sample (1 000 clients)    #
# Sans la variable cible Churn - Conforme au modèle XGBoost / Shiny   #
# ====================================================================#

set.seed(2026) # Seed pour la reproductibilité

n <- 1000 # Taille de l'échantillon

# 1. Identifiant Client
CustomerID <- sprintf("NEW-%04d", 1:n)

# 2. Variables Démographiques & Générales
SeniorCitizen    <- rbinom(n, size = 1, prob = 0.16)
Partner          <- rbinom(n, size = 1, prob = 0.48)
Dependents       <- rbinom(n, size = 1, prob = 0.30)
tenure           <- round(runif(n, min = 1, max = 72)) 
PaperlessBilling <- rbinom(n, size = 1, prob = 0.59)
MonthlyCharges   <- round(runif(n, min = 18.25, max = 118.75), 2)
Contrat_par_mois <- rbinom(n, size = 1, prob = 0.55)

# 3. Catégorielle : MultipleLines (One-Hot Exclusif)
mult_prob <- sample(1:3, size = n, replace = TRUE, prob = c(0.48, 0.10, 0.42))
MultipleLines_No                <- as.numeric(mult_prob == 1)
MultipleLines_No_phone_service  <- as.numeric(mult_prob == 2)
MultipleLines_Yes               <- as.numeric(mult_prob == 3)

# 4. Catégorielle : ServiceSup (One-Hot Exclusif)
sup_prob <- sample(1:3, size = n, replace = TRUE, prob = c(0.40, 0.22, 0.38))
ServiceSup_No                 <- as.numeric(sup_prob == 1)
ServiceSup_No_internet_service<- as.numeric(sup_prob == 2)
ServiceSup_Yes                <- as.numeric(sup_prob == 3)

# 5. Catégorielle : InternetService (One-Hot Exclusif)
net_prob <- sample(1:3, size = n, replace = TRUE, prob = c(0.34, 0.44, 0.22))
InternetService_DSL         <- as.numeric(net_prob == 1)
InternetService_Fiber_optic  <- as.numeric(net_prob == 2)
InternetService_No          <- as.numeric(net_prob == 3)

# 6. Catégorielle : PaymentMethod (One-Hot Exclusif)
pay_prob <- sample(1:4, size = n, replace = TRUE, prob = c(0.22, 0.22, 0.34, 0.22))
PaymentMethod_Bank_transfer   <- as.numeric(pay_prob == 1)
PaymentMethod_Credit_card     <- as.numeric(pay_prob == 2)
PaymentMethod_Electronic_check<- as.numeric(pay_prob == 3)
PaymentMethod_Mailed_check    <- as.numeric(pay_prob == 4)

# 7. Assemblage du DataFrame (Features uniquement)
new_predict_dataset <- data.frame(
  CustomerID = CustomerID,
  SeniorCitizen = SeniorCitizen,
  Partner = Partner,
  Dependents = Dependents,
  tenure = tenure,
  PaperlessBilling = PaperlessBilling,
  MonthlyCharges = MonthlyCharges,
  Contrat_par_mois = Contrat_par_mois,
  MultipleLines_No = MultipleLines_No,
  MultipleLines_No_phone_service = MultipleLines_No_phone_service,
  MultipleLines_Yes = MultipleLines_Yes,
  ServiceSup_No = ServiceSup_No,
  ServiceSup_No_internet_service = ServiceSup_No_internet_service,
  ServiceSup_Yes = ServiceSup_Yes,
  PaymentMethod_Bank_transfer = PaymentMethod_Bank_transfer,
  PaymentMethod_Credit_card = PaymentMethod_Credit_card,
  PaymentMethod_Electronic_check = PaymentMethod_Electronic_check,
  PaymentMethod_Mailed_check = PaymentMethod_Mailed_check,
  InternetService_DSL = InternetService_DSL,
  InternetService_Fiber_optic = InternetService_Fiber_optic,
  InternetService_No = InternetService_No
)

#Sauvegarde en fichier CSV
write.csv(new_predict_dataset, file = "app_R/data_test.csv",row.names = F)




