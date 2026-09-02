# Auteur : @Madiba

#==================================================#
# ÉTAPE 1 : Builder (Installation des packages R)  #
#==================================================#
FROM rocker/r-ver:4.4 AS builder

# Dépendances système requises pour la compilation/installation de packages
RUN apt-get update -qq && \
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

# Installation des packages R via Posit PPM (ciblé sur Ubuntu 24.04 / Noble pour r-ver:4.4)
RUN R -e "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/noble/latest')); \
    install.packages(c('plumber', 'jsonlite', 'dplyr', 'xgboost', 'caret', 'here'))"


#============================#
# ÉTAPE 2 : Image de Runtime #
#============================#
FROM rocker/r-ver:4.4 AS runtime

WORKDIR /app

# Dépendances système minimales d'exécution (libgomp1 pour xgboost/caret)
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libssl3 \
    libcurl4 \
    libxml2 \
    libsodium23 \
    libgomp1 \
    wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Création de l'utilisateur non-root et attribution des droits sur le dossier de travail
RUN groupadd -g 10001 apigroup && \
    useradd -u 10001 -g apigroup -s /sbin/nologin apiuser && \
    chown apiuser:apigroup /app

# Copie de la bibliothèque R compilée depuis le builder
COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library

# Copie de l'application R et des modèles en attribuant les droits à l'utilisateur api
COPY --chown=apiuser:apigroup api.R /app/api.R
COPY --chown=apiuser:apigroup models /app/models

# Bascule sur l'utilisateur non-root
USER 10001

EXPOSE 8080

# Vérification de l'état de santé via l'endpoint Plumber /health
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1

# Lancement du serveur Plumber
CMD ["Rscript", "-e", "pr <- plumber::plumb('/app/api.R'); pr$run(host='0.0.0.0', port=8080)"]