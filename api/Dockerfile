
# Auteur : @Madiba

# ÉTAPE 1 : Builder (Installation & Compilation)
FROM rocker/r-ver:4.4 AS builder

# Dépendances système pour le build
RUN apt-get update -qq && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        libssl-dev \
        libcurl4-openssl-dev \
        libxml2-dev \
        libsodium-dev \
        make \
        gcc \
        g++ \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
    
    
# Installation des packages R 
RUN R -e "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/noble/latest')); \
    install.packages(c('plumber', 'jsonlite', 'dplyr', 'xgboost', 'caret', 'here'))"



# ÉTAPE 2 : Image de Runtime
FROM rocker/r-ver:4.4 AS runtime

# Dépendances système d'exécution
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libssl3 \
    libcurl4 \
    libxml2 \
    libsodium23 \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Copie de la bibliothèque R compilée
COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library

WORKDIR /app

# Copie du fichier api.R et du dossier models
COPY api.R /app/api.R
COPY models /app/models

# Utilisateur système non-root dédié 
RUN groupadd -r api && useradd -r -g api api \
    && chown -R api:api /app

USER api

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1

# Lancement de l'API 
CMD ["Rscript", "-e", "pr <- plumber::plumb('/app/api.R'); pr$run(host='0.0.0.0', port=8080)"]
