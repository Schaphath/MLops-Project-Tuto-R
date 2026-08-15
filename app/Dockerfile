# ==========================================
# ÉTAPE 1 : Builder (Compilation des packages R)
# ==========================================
FROM rocker/r-ver:4.4 AS builder

# Installation des dépendances système de build
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libsodium-dev \
    make \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Installation des packages R via Posit PPM
RUN R -e "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/noble/latest')); \
    install.packages(c('shiny', 'bslib', 'DT', 'dplyr', 'httr2', 'jsonlite'))"

# ==========================================
# ÉTAPE 2 : Image Finale (Runtime Minimal)
# ==========================================
FROM rocker/r-ver:4.4 AS runtime

# Installation des bibliothèques système de RUNTIME uniquement
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libssl3 \
    libcurl4 \
    libxml2 \
    libsodium23 \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Copie des bibliothèques R pré-installées depuis l'étape builder
COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library

WORKDIR /app

# Copie de shiny.R situé dans le même dossier vers /app/app.R dans le conteneur
COPY shiny.R /app/app.R

# Création et configuration d'un utilisateur non-root dédié (sécurité)
RUN groupadd -r shiny && useradd -r -g shiny -m -d /home/shiny shiny \
    && chown -R shiny:shiny /app /home/shiny

USER shiny

EXPOSE 3838

ENV API_URL="http://127.0.0.1:8080"

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:3838/ || exit 1

# Lancement de l'application Shiny
CMD ["Rscript", "-e", "shiny::runApp('/app', host='0.0.0.0', port=3838)"]