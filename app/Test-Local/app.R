

# Auteur @Madiba
# Mise à jour : Recette de prétraitement 'recipes' + Seuil de décision optimal réassorti

#=============#
#   Packages  #
#=============#
library(shiny)
library(shinydashboard)
library(DT)
library(dplyr)
library(readr)
library(xgboost)
library(here)
library(recipes)

#=================================================#
#   Chargement du modèle XGBoost & artefacts      #
#=================================================#
xgb_model   <- xgb.load(here("models", "xgb-classifier-model.json"))
features    <- readRDS(here("models", "XGB-Model-Features.rds"))
rec_prep    <- readRDS(here("models", "recipe_prep.rds"))

# Chargement du seuil optimal (Youden) s'il existe, sinon fallback à 0.5
best_thresh <- if (file.exists(here("models", "optimal_threshold.rds"))) {
  readRDS(here("models", "optimal_threshold.rds"))
} else {
  0.5
}


#======#
#  UI  #
#======#
ui <- dashboardPage(
  skin = "black",
  
  dashboardHeader(
    title = tags$span(
      tags$img(src = "https://img.icons8.com/fluency/24/artificial-intelligence.png", style = "margin-right:8px; vertical-align:middle;"),
      "XGBoost Churn Predictor"
    ),
    titleWidth = 280
  ),
  
  dashboardSidebar(
    width = 280,
    tags$div(
      style = "padding: 20px 15px 10px 15px;",
      tags$p("Suivez les étapes ci-dessous :", style = "color:#aaa; font-size:12px; margin-bottom:10px; letter-spacing:1px; text-transform:uppercase;")
    ),
    sidebarMenu(
      id = "tabs",
      menuItem(HTML("&nbsp;&nbsp;① &nbsp;Importation"), tabName = "import", icon = icon("upload")),
      menuItem(HTML("&nbsp;&nbsp;② &nbsp;Transformation"), tabName = "transform", icon = icon("sliders-h")),
      menuItem(HTML("&nbsp;&nbsp;③ &nbsp;Prédiction"), tabName = "predict", icon = icon("brain"))
    ),
    tags$hr(style = "border-color:#444; margin: 10px 15px;"),
    tags$div(
      style = "padding: 10px 20px; color:#666; font-size:11px;",
      tags$p("Modèle : XGBoost v2"),
      tags$p(paste0("Seuil churn : ", round(best_thresh, 4)))
    )
  ),
  
  dashboardBody(
    
    # ---- CSS personnalisé ----
    tags$head(tags$style(HTML("
      @import url('https://fonts.googleapis.com/css2?family=DM+Sans:wght@300;400;500;600&family=JetBrains+Mono:wght@400;600&display=swap');

      body, .content-wrapper, .main-footer { background-color: #0f1117 !important; font-family: 'DM Sans', sans-serif; }
      .skin-black .main-header .logo, .skin-black .main-header .navbar { background-color: #141720 !important; border-bottom: 1px solid #2a2d3a; }
      .skin-black .main-header .logo { color: #e8eaf6 !important; font-weight: 600; letter-spacing: 0.5px; }
      .skin-black .main-sidebar { background-color: #141720 !important; border-right: 1px solid #2a2d3a; }
      .skin-black .sidebar-menu > li > a { color: #8b8fa8 !important; font-size: 13px; transition: all 0.2s; }
      .skin-black .sidebar-menu > li.active > a,
      .skin-black .sidebar-menu > li > a:hover { color: #7c83fd !important; background: rgba(124,131,253,0.08) !important; border-left: 3px solid #7c83fd !important; }
      .skin-black .sidebar-menu > li > a .fa { color: inherit !important; }

      .box { background: #1a1d2e !important; border: 1px solid #2a2d3a !important; border-radius: 12px !important; box-shadow: 0 4px 24px rgba(0,0,0,0.3) !important; margin-bottom: 20px; }
      .box-header { border-bottom: 1px solid #2a2d3a !important; padding: 14px 18px !important; border-radius: 12px 12px 0 0 !important; }
      .box-title { font-size: 13px !important; font-weight: 600 !important; letter-spacing: 1px !important; text-transform: uppercase !important; color: #c5c9e8 !important; }
      .box-body { padding: 18px !important; color: #c5c9e8; }

      .box.box-primary > .box-header { background: linear-gradient(135deg, #1e2340, #252a45) !important; border-left: 3px solid #7c83fd !important; }
      .box.box-info    > .box-header { background: linear-gradient(135deg, #1a2535, #1e2d42) !important; border-left: 3px solid #38bdf8 !important; }
      .box.box-success > .box-header { background: linear-gradient(135deg, #1a2b22, #1e3228) !important; border-left: 3px solid #34d399 !important; }
      .box.box-warning > .box-header { background: linear-gradient(135deg, #2b2415, #332b1a) !important; border-left: 3px solid #fbbf24 !important; }
      .box.box-danger  > .box-header { background: linear-gradient(135deg, #2b1a1f, #33202a) !important; border-left: 3px solid #f87171 !important; }

      .btn-transform {
        background: linear-gradient(135deg, #38bdf8, #0ea5e9) !important;
        color: #0f172a !important; font-weight: 600 !important; font-size: 13px !important;
        border: none !important; border-radius: 8px !important;
        padding: 10px 28px !important; letter-spacing: 0.5px !important;
        transition: all 0.2s !important; box-shadow: 0 4px 14px rgba(56,189,248,0.35) !important;
      }
      .btn-transform:hover { transform: translateY(-1px) !important; box-shadow: 0 6px 20px rgba(56,189,248,0.5) !important; }

      .btn-predict {
        background: linear-gradient(135deg, #7c83fd, #6366f1) !important;
        color: #fff !important; font-weight: 600 !important; font-size: 13px !important;
        border: none !important; border-radius: 8px !important;
        padding: 10px 28px !important; letter-spacing: 0.5px !important;
        transition: all 0.2s !important; box-shadow: 0 4px 14px rgba(124,131,253,0.4) !important;
      }
      .btn-predict:hover { transform: translateY(-1px) !important; box-shadow: 0 6px 20px rgba(124,131,253,0.6) !important; }

      .btn-export {
        background: linear-gradient(135deg, #34d399, #059669) !important;
        color: #0f172a !important; font-weight: 600 !important; font-size: 13px !important;
        border: none !important; border-radius: 8px !important;
        padding: 10px 24px !important; letter-spacing: 0.5px !important;
        transition: all 0.2s !important; box-shadow: 0 4px 14px rgba(52,211,153,0.35) !important;
        display: inline-block; margin-top: 15px;
      }
      .btn-export:hover { transform: translateY(-1px) !important; box-shadow: 0 6px 20px rgba(52,211,153,0.5) !important; color: #0f172a !important; }

      .small-box { border-radius: 10px !important; }
      .small-box.bg-blue   { background: linear-gradient(135deg, #1e3a5f, #1e4976) !important; box-shadow: 0 4px 16px rgba(56,139,248,0.2) !important; }
      .small-box.bg-green  { background: linear-gradient(135deg, #1a3b2e, #1e4a38) !important; box-shadow: 0 4px 16px rgba(52,211,153,0.2) !important; }
      .small-box.bg-yellow { background: linear-gradient(135deg, #3b2e10, #4a3a14) !important; box-shadow: 0 4px 16px rgba(251,191,36,0.2) !important; }
      .small-box h3 { font-family: 'JetBrains Mono', monospace !important; font-weight: 600 !important; font-size: 28px !important; }
      .small-box p { font-size: 12px !important; letter-spacing: 1px !important; text-transform: uppercase; }
      .small-box .icon { opacity: 0.3 !important; }

      .dataTables_wrapper { color: #c5c9e8 !important; }
      table.dataTable thead th {
        background: #1f2235 !important; color: #7c83fd !important;
        font-family: 'JetBrains Mono', monospace !important;
        font-size: 11px !important; letter-spacing: 1.2px !important;
        text-transform: uppercase !important; border-bottom: 1px solid #2a2d3a !important;
        padding: 12px 10px !important;
      }
      table.dataTable tbody tr { background: #1a1d2e !important; border-bottom: 1px solid #22253a; }
      table.dataTable tbody tr:hover { background: #21253d !important; }
      table.dataTable tbody td { color: #b0b4d0 !important; font-size: 12.5px !important; padding: 10px !important; }
      .dataTables_info, .dataTables_length label, .dataTables_filter label { color: #666 !important; font-size: 12px !important; }
      .dataTables_paginate .paginate_button { color: #666 !important; border-radius: 5px !important; }
      .dataTables_paginate .paginate_button.current { background: #7c83fd !important; color: #fff !important; border: none !important; }
      select, input[type='search'] {
        background: #0f1117 !important; color: #c5c9e8 !important;
        border: 1px solid #2a2d3a !important; border-radius: 6px !important; padding: 4px 8px !important;
      }

      pre { background: #0f1117 !important; color: #7c83fd !important; border: 1px solid #2a2d3a !important; border-radius: 8px !important; font-family: 'JetBrains Mono', monospace !important; font-size: 12px !important; padding: 14px !important; }

      .help-block { color: #555 !important; font-size: 12px !important; font-style: italic; }

      .empty-state {
        text-align: center; padding: 60px 20px; color: #3a3d52;
      }
      .empty-state .empty-icon { font-size: 48px; margin-bottom: 14px; }
      .empty-state p { font-size: 13px; letter-spacing: 0.5px; }

      .badge-churn    { background: rgba(248,113,113,0.15); color: #f87171; padding: 3px 10px; border-radius: 20px; font-size: 11px; font-weight: 600; }
      .badge-nochurn  { background: rgba(52,211,153,0.15); color: #34d399; padding: 3px 10px; border-radius: 20px; font-size: 11px; font-weight: 600; }

      .btn-file { background: #1f2235 !important; color: #7c83fd !important; border: 1px solid #2a2d3a !important; border-radius: 8px !important; }
      .form-control { background: #0f1117 !important; color: #c5c9e8 !important; border: 1px solid #2a2d3a !important; border-radius: 8px !important; }

      ::-webkit-scrollbar { width: 6px; height: 6px; }
      ::-webkit-scrollbar-track { background: #0f1117; }
      ::-webkit-scrollbar-thumb { background: #2a2d3a; border-radius: 3px; }
      ::-webkit-scrollbar-thumb:hover { background: #7c83fd; }
      
      .section-title {
        font-size: 11px; color: #555; letter-spacing: 2px;
        text-transform: uppercase; margin-bottom: 20px; padding-bottom: 8px;
        border-bottom: 1px solid #2a2d3a;
      }

      .shiny-output-error {
        color: #f87171 !important;
        font-family: 'DM Sans', sans-serif !important;
        font-size: 13px !important;
        white-space: pre-line;
        padding: 14px;
        background: rgba(248,113,113,0.08);
        border: 1px solid rgba(248,113,113,0.3);
        border-radius: 8px;
        display: block;
      }
      .shiny-output-error:before { content: none !important; }
    "))),
    
    tabItems(
      
      #=========================#
      # Onglet 1 : Importation  #
      #=========================#
      tabItem(tabName = "import",
              fluidRow(
                box(
                  title = "📂 Importer un fichier CSV",
                  status = "primary", solidHeader = TRUE, width = 12,
                  tags$p(class = "section-title", "Étape 1 — Source de données"),
                  fileInput("file1", NULL,
                            accept = c("text/csv", "text/comma-separated-values,text/plain"),
                            buttonLabel = tags$span(icon("folder-open"), " Parcourir"),
                            placeholder = "Aucun fichier sélectionné"),
                  helpText("Format attendu : CSV (séparateur virgule), doit contenir la colonne ID_CLIENT.")
                )
              ),
              fluidRow(
                box(
                  title = "📊 Aperçu — 100 premières lignes",
                  status = "info", solidHeader = TRUE, width = 12,
                  uiOutput("imported_table_ui")
                )
              ),
              fluidRow(
                box(
                  title = "📋 Résumé du dataset",
                  status = "primary", solidHeader = TRUE, width = 12,
                  fluidRow(
                    valueBoxOutput("n_rows", width = 4),
                    valueBoxOutput("n_cols", width = 4),
                    valueBoxOutput("n_extra_cols", width = 4)
                  ),
                  br(),
                  verbatimTextOutput("data_info")
                )
              )
      ),
      
      #======================#
      # Onglet 2 : Transform #
      #======================#
      tabItem(tabName = "transform",
              fluidRow(
                box(
                  title = "⚙️ Transformation & Standardisation du dataset",
                  status = "info", solidHeader = TRUE, width = 12,
                  tags$p(class = "section-title", "Étape 2 — Mise en forme & Normalisation"),
                  tags$p("Cliquez sur le bouton pour appliquer la recette pré-enregistrée (recipe_prep.rds) sur les variables.", style = "color:#8b8fa8; font-size:13px; margin-bottom:16px;"),
                  actionButton("transform_btn", label = tags$span(icon("sliders-h"), "  Transformer"),
                               class = "btn-transform"),
                  helpText("ID_CLIENT est exclu de la transformation puis réintégré tel quel dans le tableau final.")
                )
              ),
              fluidRow(
                box(
                  title = "✅ Dataset transformé — Format XGBoost",
                  status = "success", solidHeader = TRUE, width = 12,
                  uiOutput("transformed_table_ui")
                )
              )
      ),
      
      #===========================#
      #   Onglet 3 : Prediction   #
      #===========================#
      tabItem(tabName = "predict",
              fluidRow(
                box(
                  title = "🧠 Prédiction XGBoost",
                  status = "warning", solidHeader = TRUE, width = 12,
                  tags$p(class = "section-title", "Étape 3 — Scoring client"),
                  tags$p(paste0("Cliquez sur le bouton pour appliquer le modèle avec le seuil optimal (", round(best_thresh, 4), ")."), style = "color:#8b8fa8; font-size:13px; margin-bottom:16px;"),
                  actionButton("predict_btn", label = tags$span(icon("brain"), "  Lancer la prédiction"),
                               class = "btn-predict"),
                  helpText("ID_CLIENT est exclu de l'appel à predict() puis réassocié aux résultats.")
                )
              ),
              fluidRow(
                box(
                  title = "📈 Résultats de prédiction",
                  status = "success", solidHeader = TRUE, width = 12,
                  uiOutput("results_table_ui")
                )
              )
      )
    )
  )
)


#===========#
#   SERVER  #
#===========#

options(shiny.sanitize.errors = FALSE)

server <- function(input, output, session) {
  
  #-----------------------------------------------------------------#
  #  Données brutes : validation + séparation stricte ID / features #
  #-----------------------------------------------------------------#
  raw_data <- reactive({
    req(input$file1)
    
    df <- read_delim(
      input$file1$datapath,
      delim = ",",
      locale = locale(encoding = "UTF-8"),
      na = c("", "NA"),
      trim_ws = TRUE,
      show_col_types = FALSE
    )
    
    # --- Gestion dynamique de ID_CLIENT ---
    id_col <- names(df)[tolower(names(df)) %in% c("customerid", "customer_id", "id_client", "id", "client_id")][1]
    
    if (!is.na(id_col)) {
      client_id <- as.character(df[[id_col]])
    } else {
      # Fallback : génération automatique d'ID si absent
      client_id <- paste0("CLIENT_", seq_len(nrow(df)))
    }
    
    # --- Validation : présence de toutes les features attendues ---
    missing_features <- setdiff(features, names(df))
    validate(
      need(length(missing_features) == 0,
           paste0(
             "Erreur : le fichier importé ne contient pas toutes les variables attendues par le modèle.\n\n",
             "Variable(s) manquante(s) : ", paste(missing_features, collapse = ", ")
           ))
    )
    
    # --- Sélection STRICTE et RÉORDONNÉE ---
    df_features <- df[, features, drop = FALSE]
    
    # --- Colonnes supplémentaires ---
    extra_cols <- setdiff(names(df), c(features, if (!is.na(id_col)) id_col else character(0)))
    
    # --- Conversion numérique sécurisée ---
    for (col in names(df_features)) {
      if (!is.numeric(df_features[[col]])) {
        df_features[[col]] <- suppressWarnings(as.numeric(as.character(df_features[[col]])))
      }
      df_features[[col]][is.na(df_features[[col]])] <- 0
    }
    
    list(
      id         = client_id,
      features   = df_features,
      extra_cols = extra_cols
    )
  })
  
  
  #-----------------#
  #  Onglet Import  #
  #-----------------#
  output$imported_table_ui <- renderUI({
    if (is.null(input$file1)) {
      tags$div(class = "empty-state",
               tags$div(class = "empty-icon", icon("upload")),
               tags$p("Importez un fichier CSV pour visualiser les données.")
      )
    } else {
      DTOutput("imported_table")
    }
  })
  
  output$imported_table <- renderDT({
    req(raw_data())
    res <- raw_data()
    df_display <- cbind(ID_CLIENT = res$id, res$features)
    
    datatable(head(df_display, 100),
              options = list(scrollX = TRUE, pageLength = 10, autoWidth = TRUE, dom = 'lfrtip'),
              caption = "Aperçu : 100 premières lignes"
    )
  }, server = FALSE)
  
  
  #---------------#
  #  Value Boxes  #
  #---------------#
  output$n_rows <- renderValueBox({
    req(raw_data())
    valueBox(value = length(raw_data()$id), subtitle = "Lignes", icon = icon("database"), color = "blue")
  })
  
  output$n_cols <- renderValueBox({
    req(raw_data())
    valueBox(value = paste0(ncol(raw_data()$features), " / ", length(features)),
             subtitle = "Features reconnues", icon = icon("check-circle"), color = "green")
  })
  
  output$n_extra_cols <- renderValueBox({
    req(raw_data())
    n_extra <- length(raw_data()$extra_cols)
    valueBox(value = n_extra, subtitle = "Colonnes ignorées (hors modèle)", icon = icon("filter"), color = "yellow")
  })
  
  
  #------------------#
  #  Info colonnes   #
  #------------------#
  output$data_info <- renderText({
    req(raw_data())
    res <- raw_data()
    df_display <- cbind(ID_CLIENT = res$id, res$features)
    types <- paste0(names(df_display), " [", sapply(df_display, class), "]")
    
    extra_msg <- if (length(res$extra_cols) > 0) {
      paste0("\n\nColonnes présentes dans le fichier mais non utilisées par le modèle :\n",
             paste(res$extra_cols, collapse = ", "))
    } else {
      ""
    }
    
    paste0("Variables utilisées pour le modèle :\n\n", paste(types, collapse = "\n"), extra_msg)
  })
  
  
  #-----------------------#
  #    Onglet Transform    #
  #-----------------------#
  transformed_data <- eventReactive(input$transform_btn, {
    
    showNotification("Transformation en cours...", id = "transform_msg", type = "message", duration = NULL)
    on.exit(removeNotification(id = "transform_msg"), add = TRUE)
    
    res <- raw_data()
    id_vector <- res$id
    X_raw     <- res$features[, features, drop = FALSE]
    
    # Application de la recette 'recipes' entraînée via bake()
    X_scaled <- tryCatch({
      bake(rec_prep, new_data = X_raw)
    }, error = function(e) {
      validate(need(FALSE, paste0(
        "Erreur lors de l'application de la recette de prétraitement (recipes) :\n",
        conditionMessage(e)
      )))
    })
    
    result <- data.frame(ID_CLIENT = id_vector, X_scaled, check.names = FALSE)
    showNotification("Transformation terminée avec succès.", type = "message", duration = 3)
    result
  })  
  
  output$transformed_table_ui <- renderUI({
    if (is.null(input$transform_btn) || input$transform_btn == 0) {
      tags$div(class = "empty-state",
               tags$div(class = "empty-icon", icon("sliders-h")),
               tags$p("Cliquez sur « Transformer » pour afficher le dataset mis en forme et standardisé.")
      )
    } else {
      DTOutput("transformed_table")
    }
  })
  
  output$transformed_table <- renderDT({
    req(transformed_data())
    datatable(transformed_data(),
              options = list(scrollX = TRUE, pageLength = 10, autoWidth = TRUE, dom = 'lfrtip'),
              caption = "Format standardisé prêt pour XGBoost (ID_CLIENT non transformé)"
    )
  }, server = FALSE)
  
  
  #-----------------------#
  #    Onglet Prediction   #
  #-----------------------#
  prediction_results <- eventReactive(input$predict_btn, {
    
    showNotification("Prédiction en cours...", id = "predict_msg", type = "message", duration = NULL)
    on.exit(removeNotification(id = "predict_msg"), add = TRUE)
    
    df_trans  <- transformed_data()
    id_vector <- df_trans$ID_CLIENT
    
    # Extraction stricte des features dans l'ordre exact attendu par le modèle
    X_matrix  <- as.matrix(df_trans[, features, drop = FALSE])
    
    # Prédiction XGBoost
    pred_prob <- tryCatch({
      predict(xgb_model, X_matrix)
    }, error = function(e) {
      validate(need(FALSE, paste0(
        "Erreur lors de l'appel au modèle XGBoost :\n", conditionMessage(e)
      )))
    })
    
    # Utilisation du seuil décisionnel optimal (best_thresh)
    pred_class <- ifelse(pred_prob >= best_thresh, "1", "0")
    comment    <- ifelse(pred_prob >= best_thresh,
                         "Client susceptible de churner",
                         "Client peu susceptible de churner")
    
    result <- data.frame(
      ID_CLIENT   = id_vector,
      Churn_Proba = round(pred_prob, 4),
      Churn_Class = pred_class,
      Commentaire = comment,
      stringsAsFactors = FALSE
    )
    showNotification("Prédiction terminée avec succès.", type = "message", duration = 3)
    result
  }) 
  
  output$results_table_ui <- renderUI({
    if (is.null(input$predict_btn) || input$predict_btn == 0) {
      tags$div(class = "empty-state",
               tags$div(class = "empty-icon", icon("brain")),
               tags$p("Cliquez sur « Lancer la prédiction » pour afficher les résultats.")
      )
    } else {
      tagList(
        DTOutput("results_table"),
        downloadButton("download_results", "Exporter les résultats (CSV)", class = "btn-export")
      )
    }
  })
  
  output$results_table <- renderDT({
    req(prediction_results())
    df <- prediction_results()
    
    df$Churn_Class <- ifelse(
      df$Churn_Class == "1",
      '<span class="badge-churn">Churn</span>',
      '<span class="badge-nochurn">Stable</span>'
    )
    
    datatable(df,
              escape = FALSE,
              rownames = FALSE,
              options = list(
                scrollX = TRUE,
                autoWidth = FALSE,
                pageLength = 10,
                dom = 'lfrtip',
                columnDefs = list(
                  list(className = 'dt-center', targets = 0:3)
                )
              ),
              colnames = c("ID_CLIENT", "Probabilité Churn", "Classe", "Commentaire")
    )
  }, server = FALSE)
  
  output$download_results <- downloadHandler(
    filename = function() {
      paste0("prediction_churn_", Sys.Date(), ".csv")
    },
    content = function(file) {
      write.csv(prediction_results(), file, row.names = FALSE)
    }
  )
  
}

#================#
#   LANCER APP   #
#================#
shinyApp(ui = ui, server = server)
