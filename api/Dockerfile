# ==========================================
# ÉTAPE 1 : Builder (Compilation & Setup)
# ==========================================
FROM rocker/r-ver:4.4 AS builder

# Installation des dépendances système de build + compilateurs
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libsodium-dev \
    make \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Installation des packages R via les binaires Posit
RUN R -e "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/noble/latest')); \
    install.packages(c('plumber', 'jsonlite', 'dplyr', 'xgboost', 'recipes'))"


# ÉTAPE 2 : Image Finale 
FROM rocker/r-ver:4.4 AS runtime

# Installation des dépendances système de RUNTIME uniquement 
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libssl3 \
    libcurl4 \
    libxml2 \
    libsodium23 \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Copie des packages R compilés depuis l'étape builder
COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library

WORKDIR /app

# Copie des fichiers applicatifs
COPY plumber.R /app/
COPY models /app/models

# Création et configuration de l'utilisateur non-root
RUN groupadd -r plumber && useradd -r -g plumber plumber \
    && chown -R plumber:plumber /app

USER plumber

EXPOSE 8080

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1

# Lancement
CMD ["Rscript", "-e", "pr <- plumber::plumb('/app/plumber.R'); pr$run(host='0.0.0.0', port=8080)"]
