# Auteur : Madiba
# Shiny UI Client -> API Plumber (v1.2 - Formulaire restructuré + Auth API Key)

library(shiny)
library(bslib)
library(DT)
library(dplyr)
library(httr2)
library(jsonlite)

# Endpoint de l'API Plumber (résolution dynamique host/port, cf. bug 127.0.0.1)
API_URL <- Sys.getenv("API_URL", unset = "http://127.0.0.1:8080")

# Clé API (nouveau) : si définie, envoyée en en-tête X-API-Key sur /predict.
# Reste vide et sans effet si l'API cible n'exige pas d'authentification (v1.2.0
# ou v1.3.0 avec API_KEY non configurée côté serveur).
API_KEY <- Sys.getenv("API_KEY", unset = "")

#=================================================#
#                   INTERFACE UI                  #
#=================================================#
ui <- fluidPage(
  title = "Telco Churn AI - Côte d'Ivoire",
  
  tags$head(
    tags$style(HTML("
      @import url('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@600&display=swap');

      body {
        background-color: #f8fafc !important;
        font-family: 'Plus Jakarta Sans', sans-serif !important;
        color: #1e293b;
        padding-bottom: 50px;
      }

      /* En-tête principal Orange CI & Vert subtil */
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

      /* Chaque section du formulaire est désormais sa propre carte,
         empilée verticalement, au lieu de deux colonnes mélangeant
         des thématiques différentes. */
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

      /* Formulaires aérés */
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

      /* Petit bouton Orange ajusté */
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

      /* Alertes & Résultats */
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

      .model-version-tag {
        text-align: center;
        margin-top: 14px;
        font-size: 11px;
        color: #94a3b8;
        font-family: 'JetBrains Mono', monospace;
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
  
  div(class = "main-container",
      
      # ============================================================ #
      # Section 1 - Profil client (données démographiques)            #
      # ============================================================ #
      div(class = "custom-card",
          div(class = "card-subtitle",
              span(class = "step-number", "1"), "Profil Client"
          ),
          fluidRow(
            column(4, selectInput("SeniorCitizen", "Senior (> 65 ans)",
                                  choices = c("Non" = 0, "Oui" = 1), selected = 0)),
            column(4, selectInput("Partner", "En couple",
                                  choices = c("Oui" = 1, "Non" = 0), selected = 1)),
            column(4, selectInput("Dependents", "A charge",
                                  choices = c("Non" = 0, "Oui" = 1), selected = 0))
          )
      ),
      
      # ============================================================ #
      # Section 2 - Contrat & Facturation                              #
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
                                  choices = c("Mois par mois" = "Month_to_month", "1 An" = "One.year", "2 Ans" = "Two.year"),
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
            column(4, selectInput("MultipleLines", "Lignes multiples",
                                  choices = c("Non" = "No", "Sans service tel." = "No_phone_service", "Oui" = "Yes"),
                                  selected = "No_phone_service")),
            column(4, selectInput("InternetService", "Fournisseur Internet",
                                  choices = c("DSL" = "DSL", "Fibre optique" = "Fiber_optic", "Aucun" = "No"),
                                  selected = "DSL")),
            column(4, selectInput("ServiceSup", "Support / Services Sup.",
                                  choices = c("Non" = "No", "Pas d'internet" = "No_internet_service", "Oui" = "Yes"),
                                  selected = "Yes"))
          )
      ),
      
      # Bouton soumission centré
      div(style = "text-align: center; margin: 10px 0 5px 0;",
          actionButton("predict_btn", label = "Lancer la prédiction", class = "btn-predict", icon = icon("paper-plane"))
      ),
      
      # Affichage conditionnel des résultats (masqué si API fermée ou en erreur)
      uiOutput("results_ui")
  )
)

#=================================================#
#                  LOGIQUE SERVER                 #
#=================================================#
server <- function(input, output, session) {
  
  formatted_payload <- eventReactive(input$predict_btn, {
    data.frame(
      customerID = paste0("CLI-", sample(10000:99999, 1)),
      SeniorCitizen = as.numeric(input$SeniorCitizen),
      Partner = as.numeric(input$Partner),
      Dependents = as.numeric(input$Dependents),
      tenure = as.numeric(input$tenure),
      PaperlessBilling = as.numeric(input$PaperlessBilling),
      MonthlyCharges = as.numeric(input$MonthlyCharges),
      
      MultipleLines_No = ifelse(input$MultipleLines == "No", 1, 0),
      MultipleLines_No_phone_service = ifelse(input$MultipleLines == "No_phone_service", 1, 0),
      MultipleLines_Yes = ifelse(input$MultipleLines == "Yes", 1, 0),
      
      InternetService_DSL = ifelse(input$InternetService == "DSL", 1, 0),
      InternetService_Fiber_optic = ifelse(input$InternetService == "Fiber_optic", 1, 0),
      InternetService_No = ifelse(input$InternetService == "No", 1, 0),
      
      Contract_Month_to_month = ifelse(input$Contract == "Month_to_month", 1, 0),
      Contract_One.year = ifelse(input$Contract == "One.year", 1, 0),
      Contract_Two.year = ifelse(input$Contract == "Two.year", 1, 0),
      
      PaymentMethod_Bank_transfer = ifelse(input$PaymentMethod == "Bank_transfer", 1, 0),
      PaymentMethod_Credit_card = ifelse(input$PaymentMethod == "Credit_card", 1, 0),
      PaymentMethod_Electronic_check = ifelse(input$PaymentMethod == "Electronic_check", 1, 0),
      PaymentMethod_Mailed_check = ifelse(input$PaymentMethod == "Mailed_check", 1, 0),
      
      ServiceSup_No = ifelse(input$ServiceSup == "No", 1, 0),
      ServiceSup_No_internet_service = ifelse(input$ServiceSup == "No_internet_service", 1, 0),
      ServiceSup_Yes = ifelse(input$ServiceSup == "Yes", 1, 0),
      stringsAsFactors = FALSE
    )
  })
  
  # Requête REST avec retour NULL explicite si l'API est absente
  api_response <- eventReactive(input$predict_btn, {
    req(formatted_payload())
    
    # 1. Test de disponibilité de l'API, basé dynamiquement sur API_URL
    #    (host + port extraits de la variable d'env, plus de valeur en dur)
    api_host <- sub("^https?://([^:/]+).*$", "\\1", API_URL)
    api_port_raw <- sub("^https?://[^:/]+:?([0-9]*).*$", "\\1", API_URL)
    api_port <- if (nzchar(api_port_raw)) as.integer(api_port_raw) else 80L
    
    api_online <- tryCatch({
      con <- socketConnection(host = api_host, port = api_port, timeout = 1)
      close(con)
      TRUE
    }, error = function(e) {
      FALSE
    })
    
    if (!api_online) {
      showNotification(
        paste0("Erreur : l'API Plumber n'est pas joignable sur ", api_host, ":", api_port),
        type = "error", duration = 5
      )
      return(NULL)
    }
    
    # 2. Exécution de la requête HTTP
    df <- formatted_payload()
    
    tryCatch({
      json_data <- toJSON(df, auto_unbox = TRUE)
      
      req_obj <- request(paste0(API_URL, "/predict")) %>%
        req_headers("Content-Type" = "application/json")
      
      # Ajout conditionnel de la clé API (nouveau, compatibilité API v1.3.0).
      # Sans effet si API_KEY n'est pas définie côté client Shiny.
      if (nzchar(API_KEY)) {
        req_obj <- req_obj %>% req_headers("X-API-Key" = API_KEY)
      }
      
      req_obj <- req_obj %>%
        req_body_raw(json_data, type = "application/json") %>%
        req_timeout(3) %>%
        req_perform()
      
      resp_body_string(req_obj) %>% fromJSON()
      
    }, error = function(e) {
      # httr2 lève une erreur explicite sur les statuts HTTP 4xx/5xx
      # (401 en cas de clé API manquante/invalide, 413 si le payload est
      # trop volumineux, etc.) : conditionMessage(e) en contient le détail.
      showNotification(paste0("Erreur de prédiction : ", conditionMessage(e)), type = "error", duration = 6)
      return(NULL)
    })
  })
  
  # Rendu de l'UI de résultat
  output$results_ui <- renderUI({
    res <- api_response()
    
    if (is.null(res)) {
      return(NULL)
    }
    
    proba_val <- if ("churn_proba" %in% names(res)) res$churn_proba else res[[1]]
    decision_val <- if ("decision" %in% names(res)) res$decision else ifelse(proba_val > 0.5, "Churn", "Fidèle")
    model_version_val <- if ("model_version" %in% names(res)) res$model_version else NA
    
    proba_pct <- round(as.numeric(proba_val) * 100, 2)
    is_churn <- decision_val == "Churn"
    
    tagList(
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
                       div(class = "metric-label", "Décision du Modèle"),
                       div(style = "margin-top: 8px;",
                           span(class = if (is_churn) "badge-churn" else "badge-nochurn", decision_val)
                       )
                   )
            )
          )
      ),
      # Traçabilité : version du modèle ayant produit la prédiction (nouveau, champ renvoyé par l'API v1.3.0)
      if (!is.na(model_version_val)) {
        div(class = "model-version-tag", paste0("Modèle v", model_version_val))
      }
    )
  })
}

shinyApp(ui = ui, server = server)
