
# Auteur : @Madiba


## Librairies 
library(here)
library(fastDummies)


## Importation dataset 
path.churn <- here("data", "process")
df <- read.csv(paste(path.churn, "churn_modif.csv", sep = "/"))


## Recode la variable Churn 
df <- df |> 
  mutate(Churn = ifelse(Churn == "Yes", 1, 0))

## Suppression de quelques variables 
df <- df |> dplyr::select(-c(gender, PhoneService, TotalCharges))


## Foncttion RecodeYesNo
RecodeYesNo <- function(data) {
  data |> 
    dplyr::mutate(
      dplyr::across(
        dplyr::where(~ is.character(.x) || is.factor(.x)), 
        ~ {
          # Conversion explicite en caractère si c'est un factor
          vec_char <- as.character(.x)
          valeurs_uniques <- na.omit(unique(vec_char))
          
          # Vérifie la présence des valeurs "Yes" et "No"
          if (length(valeurs_uniques) > 0 && 
              all(valeurs_uniques %in% c("Yes", "No"))) {
            dplyr::if_else(vec_char == "Yes", 1, 0, missing = NA_real_)
          } else {
            .x
          }
        }
      )
    )
}


## Applique le recodage 
df <- RecodeYesNo(data=df)


## Fonction CreateDummies
CreateDummies <- function(data, variables) {
  colonnes_initiales <- colnames(data)
  data_dummies <- fastDummies::dummy_cols(
    data, select_columns = variables,
    remove_first_dummy = FALSE,
    remove_selected_columns = TRUE
  )
  
  return(data_dummies)
}


## Création des variables indicatrices 
ColName <- c("MultipleLines", "InternetService", "Contract", 
             "PaymentMethod", "ServiceSup")

## Nouveau Dataset 
dfNew <- CreateDummies(data=df, variables = ColName)


## Rename variables
dfNew <- dfNew |> rename(
  "MultipleLines_No_phone_service" = "MultipleLines_No phone service",
  "ServiceSup_No_internet_service" = "ServiceSup_No internet service",
  "PaymentMethod_Bank_transfer" = "PaymentMethod_Bank transfer (automatic)",
  "PaymentMethod_Credit_card" = "PaymentMethod_Credit card (automatic)",
  "PaymentMethod_Electronic_check" = "PaymentMethod_Electronic check",
  "PaymentMethod_Mailed_check" = "PaymentMethod_Mailed check",
  "InternetService_Fiber_optic" = "InternetService_Fiber optic", 
  "Contract_Month_to_month" = "Contract_Month-to-month", 
)

## Enregistrer dfNew
write.csv(dfNew, paste(path_df, "dfNew.csv", sep = "/"), row.names = FALSE)

