# Auteur : Madiba (Optimisé & Aligné avec l'API XGBoost 21 variables)
library(shiny)
library(bslib)
library(DT)
library(dplyr)
library(httr2)
library(jsonlite)

# Endpoint local de l'API Plumber
API_URL <- Sys.getenv("API_URL", unset = "http://127.0.0.1:8080")

#=================================================#
#                   INTERFACE UI                  #
#=================================================#
ui <- fluidPage(
  title = "Telco Churn App",
  
  tags$head(
    tags$style(HTML("
      @import url('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@600&display=swap');
      
      body {
        background-color: #f8fafc !important;
        font-family: 'Plus Jakarta Sans', sans-serif !important;
        color: #1e293b;
        padding-bottom: 50px;
      }
      
      .app-header {
        background: linear-gradient(135deg, #f97316 0%, #ea580c 100%);
        color: #ffffff;
        padding: 22px 0;
        margin-bottom: 30px;
        box-shadow: 0 4px 15px rgba(234, 88, 12, 0.2);
        border-bottom: 4px solid #16a34a;
      }
      
      .app-title {
        font-size: 22px;
        font-weight: 700;
        margin: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 10px;
      }

      .main-container {
        max-width: 1040px;
        margin: 0 auto;
      }

      .custom-card {
        background: #ffffff;
        border: 1px solid #e2e8f0;
        border-radius: 14px;
        padding: 28px 24px;
        box-shadow: 0 4px 12px rgba(0,0,0,0.03);
        margin-bottom: 20px;
      }

      .card-subtitle {
        font-size: 13px;
        font-weight: 700;
        color: #ea580c;
        text-transform: uppercase;
        letter-spacing: 0.6px;
        margin-bottom: 20px;
        border-bottom: 2px solid #ffedd5;
        padding-bottom: 8px;
        display: flex;
        align-items: center;
        gap: 8px;
      }

      .card-subtitle .step-number {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 20px;
        height: 20px;
        border-radius: 50%;
        background: #ea580c;
        color: #ffffff;
        font-size: 11px;
        font-weight: 700;
      }

      label {
        font-size: 12px !important;
        font-weight: 600 !important;
        color: #475569 !important;
        margin-bottom: 8px !important;
      }
      
      .form-control, .selectize-input {
        font-size: 13px !important;
        border-radius: 8px !important;
        border: 1px solid #cbd5e1 !important;
        height: 40px !important;
        min-height: 40px !important;
        padding: 8px 12px !important;
      }
      
      .form-group {
        margin-bottom: 22px !important;
      }

      .btn-predict {
        background: #f97316 !important;
        color: #ffffff !important;
        font-weight: 600 !important;
        font-size: 14px !important;
        border: none !important;
        border-radius: 8px !important;
        padding: 10px 24px !important;
        transition: all 0.2s ease !important;
        box-shadow: 0 3px 10px rgba(249, 115, 22, 0.3) !important;
      }
      
      .btn-predict:hover {
        background: #ea580c !important;
        transform: translateY(-1px);
      }

      .results-container {
        background: #ffffff;
        border: 2px solid #16a34a;
        border-radius: 12px;
        padding: 22px;
        margin-top: 5px;
        box-shadow: 0 4px 12px rgba(22, 163, 74, 0.08);
      }

      .metric-box {
        text-align: center;
        padding: 16px;
        background: #f0fdf4;
        border-radius: 8px;
        border: 1px solid #dcfce7;
      }

      .metric-label {
        font-size: 11px;
        font-weight: 700;
        color: #15803d;
        text-transform: uppercase;
        letter-spacing: 0.5px;
      }

      .metric-value {
        font-family: 'JetBrains Mono', monospace;
        font-size: 28px;
        font-weight: 700;
        color: #ea580c;
        margin-top: 4px;
      }

      .badge-churn {
        background: #fef2f2;
        color: #dc2626;
        border: 1px solid #fecaca;
        padding: 6px 18px;
        border-radius: 20px;
        font-weight: 700;
        font-size: 13px;
        display: inline-block;
      }
      
      .badge-nochurn {
        background: #f0fdf4;
        color: #16a34a;
        border: 1px solid #bbf7d0;
        padding: 6px 18px;
        border-radius: 20px;
        font-weight: 700;
        font-size: 13px;
        display: inline-block;
      }
    "))
  ),
  
  # Banner En-tête
  div(class = "app-header",
      div(class = "app-title",
          tags$img(src = "https://img.icons8.com/fluency/28/artificial-intelligence.png"),
          "Inférence Churn Client - XGBoost API"
      )
  ),
  
  # Formulaire centré
  div(class = "main-container",
      
      # ============================================================ #
      # Section 1 - Profil client                                    #
      # ============================================================ #
      div(class = "custom-card",
          div(class = "card-subtitle",
              span(class = "step-number", "1"), "Profil Client"
          ),
          fluidRow(
            column(3, selectInput("gender", "Genre",
                                  choices = c("Femme" = 1, "Homme" = 0), selected = 1)),
            column(3, selectInput("SeniorCitizen", "Senior (> 65 ans)",
                                  choices = c("Non" = 0, "Oui" = 1), selected = 0)),
            column(3, selectInput("Partner", "En couple",
                                  choices = c("Oui" = 1, "Non" = 0), selected = 1)),
            column(3, selectInput("Dependents", "A charge",
                                  choices = c("Non" = 0, "Oui" = 1), selected = 0))
          )
      ),
      
      # ============================================================ #
      # Section 2 - Contrat & Facturation                            #
      # ============================================================ #
      div(class = "custom-card",
          div(class = "card-subtitle",
              span(class = "step-number", "2"), "Contrat & Facturation"
          ),
          fluidRow(
            column(4, numericInput("tenure", "Ancienneté (mois)", value = 1, min = 0, max = 100)),
            column(4, numericInput("MonthlyCharges", "Montant Mensuel (€)", value = 29.85, min = 0, step = 0.5)),
            column(4, selectInput("PaperlessBilling", "Facture en ligne",
                                  choices = c("Oui" = 1, "Non" = 0), selected = 1))
          ),
          fluidRow(
            column(6, selectInput("Contract", "Type de Contrat",
                                  choices = c("Mois par mois" = "Month_to_month", "1 An" = "One_year", "2 Ans" = "Two_year"),
                                  selected = "Month_to_month")),
            column(6, selectInput("PaymentMethod", "Mode de Paiement",
                                  choices = c("Chèque électronique" = "Electronic_check", "Virement" = "Bank_transfer",
                                              "Carte bancaire" = "Credit_card", "Chèque postal" = "Mailed_check"),
                                  selected = "Electronic_check"))
          )
      ),
      
      # ============================================================ #
      # Section 3 - Services & Options souscrites                     #
      # ============================================================ #
      div(class = "custom-card",
          div(class = "card-subtitle",
              span(class = "step-number", "3"), "Services & Options"
          ),
          fluidRow(
            column(3, selectInput("PhoneService", "Service Téléphonie",
                                  choices = c("Oui" = 1, "Non" = 0), selected = 1)),
            column(3, selectInput("MultipleLines", "Lignes multiples",
                                  choices = c("Non" = "No", "Oui" = "Yes"),
                                  selected = "No")),
            column(3, selectInput("InternetService", "Fournisseur Internet",
                                  choices = c("DSL" = "DSL", "Fibre optique" = "Fiber_optic", "Aucun" = "No"),
                                  selected = "DSL")),
            column(3, selectInput("ServiceSup", "Support / Services Sup.",
                                  choices = c("Non" = "No", "Oui" = "Yes"),
                                  selected = "Yes"))
          )
      ),
      
      # Bouton soumission centré
      div(style = "text-align: center; margin: 10px 0 5px 0;",
          actionButton("predict_btn", label = "Lancer la prédiction", class = "btn-predict", icon = icon("paper-plane"))
      ),
      
      # Affichage conditionnel des résultats
      uiOutput("results_ui")
  )
)

#=================================================#
#                   LOGIQUE SERVER                #
#=================================================#
server <- function(input, output, session) {
  
  # Construction du dataframe respectant exactement la liste des 21 variables du modèle XGBoost
  formatted_payload <- eventReactive(input$predict_btn, {
    
    # Gestion des cas Aucun Service Internet
    no_internet <- ifelse(input$InternetService == "No", 1, 0)
    
    data.frame(
      gender = as.numeric(input$gender),
      SeniorCitizen = as.numeric(input$SeniorCitizen),
      Partner = as.numeric(input$Partner),
      Dependents = as.numeric(input$Dependents),
      tenure = as.numeric(input$tenure),
      PhoneService = as.numeric(input$PhoneService),
      PaperlessBilling = as.numeric(input$PaperlessBilling),
      MonthlyCharges = as.numeric(input$MonthlyCharges),
      
      MultipleLines_No = ifelse(input$MultipleLines == "No", 1, 0),
      InternetService_DSL = ifelse(input$InternetService == "DSL", 1, 0),
      InternetService_Fiber_optic = ifelse(input$InternetService == "Fiber_optic", 1, 0),
      
      Contract_Month_to_month = ifelse(input$Contract == "Month_to_month", 1, 0),
      Contract_One_year = ifelse(input$Contract == "One_year", 1, 0),
      Contract_Two_year = ifelse(input$Contract == "Two_year", 1, 0),
      
      PaymentMethod_Bank_transfer = ifelse(input$PaymentMethod == "Bank_transfer", 1, 0),
      PaymentMethod_Credit_card = ifelse(input$PaymentMethod == "Credit_card", 1, 0),
      PaymentMethod_Electronic_check = ifelse(input$PaymentMethod == "Electronic_check", 1, 0),
      PaymentMethod_Mailed_check = ifelse(input$PaymentMethod == "Mailed_check", 1, 0),
      
      ServiceSup_No = ifelse(input$ServiceSup == "No" && no_internet == 0, 1, 0),
      ServiceSup_Yes = ifelse(input$ServiceSup == "Yes" && no_internet == 0, 1, 0),
      No_Internet_Service = no_internet,
      
      stringsAsFactors = FALSE
    )
  })
  
  # Requête REST
  api_response <- eventReactive(input$predict_btn, {
    req(formatted_payload())
    
    # Verification du Healthcheck API
    health_url <- paste0(API_URL, "/health")
    api_online <- tryCatch({
      res <- request(health_url) %>% req_timeout(2) %>% req_perform()
      resp_status(res) == 200
    }, error = function(e) FALSE)
    
    if (!api_online) {
      showNotification(
        paste0("Erreur : l'API Plumber n'est pas accessible sur ", API_URL),
        type = "error", duration = 5
      )
      return(NULL)
    }
    
    df <- formatted_payload()
    
    tryCatch({
      req_obj <- request(paste0(API_URL, "/predict")) %>%
        req_headers("Content-Type" = "application/json") %>%
        req_body_json(df) %>%
        req_timeout(5) %>%
        req_perform()
      
      resp_body_string(req_obj) %>% fromJSON()
      
    }, error = function(e) {
      showNotification(paste0("Erreur lors de la prédiction : ", conditionMessage(e)), type = "error", duration = 5)
      return(NULL)
    })
  })
  
  # Rendu des métriques
  output$results_ui <- renderUI({
    res <- api_response()
    
    if (is.null(res)) return(NULL)
    
    # Récupération flexible de la probabilité et de la classe
    proba_val <- if("churn_proba" %in% names(res)) res$churn_proba else res[[1]]
    decision_val <- if("decision" %in% names(res)) res$decision else ifelse(proba_val > 0.5, "Churn", "Fidèle")
    
    proba_pct <- round(as.numeric(proba_val) * 100, 2)
    is_churn <- decision_val %in% c("Churn", "Yes", "1")
    
    div(class = "results-container",
        fluidRow(
          column(6,
                 div(class = "metric-box",
                     div(class = "metric-label", "Probabilité de Churn"),
                     div(class = "metric-value", paste0(proba_pct, " %"))
                 )
          ),
          column(6,
                 div(class = "metric-box",
                     div(class = "metric-label", "Statut Prédictif"),
                     div(style = "margin-top: 8px;",
                         span(class = if(is_churn) "badge-churn" else "badge-nochurn", 
                              if(is_churn) "Risque Churn" else "Client Fidèle")
                     )
                 )
          )
        )
    )
  })
}

shinyApp(ui = ui, server = server)
