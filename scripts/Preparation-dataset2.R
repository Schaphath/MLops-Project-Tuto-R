

library(here)
library(fastDummies)

# Importation dataset 
path_df <- here("data", "process")
df_model2 <- read.csv(paste(path_df, "df_model2.csv"))



#============================================================================#
#  Cette fonction recode les variables binaires du type (yes, no) en (1, 0)  #
#============================================================================#
RecodeYesNo <- function(data) {
  data |> 
    dplyr::mutate(
      dplyr::across(
        dplyr::where(~ is.character(.x) || is.factor(.x)), 
        ~ {
          # Conversion explicite en caractère si c'est un factor
          vec_char <- as.character(.x)
          valeurs_uniques <- na.omit(unique(vec_char))
          
          # Vérifie si la colonne contient uniquement des valeurs parmi "Yes" et "No"
          if (length(valeurs_uniques) > 0 && all(valeurs_uniques %in% c("Yes", "No"))) {
            dplyr::if_else(vec_char == "Yes", 1, 0, missing = NA_real_)
          } else {
            .x
          }
        }
      )
    )
}


# Applique le recodage 
df_model2 <- RecodeYesNo(data=df_model2)



#================================================#
# Fonction pour la création de variables dummies #
#================================================#
CreateDummies <- function(data, variables) {
  colonnes_initiales <- colnames(data)
  
  data_dummies <- fastDummies::dummy_cols(
    data, select_columns = variables,
    remove_first_dummy = FALSE,
    remove_selected_columns = TRUE
  )
  
  return(data_dummies)
}


# Appliquer la création de dummies 
col_name <- c("MultipleLines", "PaymentMethod", "InternetService")
df_model2 <- CreateDummies(data=df_model2, variables = col_name)


# save dataset modifié
write.csv(df_model1, paste(path_df, "df_model2_modif.csv"), row.names = FALSE)




