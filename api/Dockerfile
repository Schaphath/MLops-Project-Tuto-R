# Image de base : rocker/r-ver fournit R préinstallé sur une base Ubuntu figée.
# ATTENTION : vous m'avez indiqué développer en R 4.6. Si l'image
# rocker/r-ver:4.6.x existe déjà sur Docker Hub, remplacez le tag ci-dessous.
# A défaut, restez cohérent avec R 4.4 en local pour éviter les écarts de comportement.
FROM rocker/r-ver:4.4

# 1. Installation des dépendances système requises
#    - libssl-dev, libcurl4-openssl-dev, libxml2-dev : compilation de plumber/xgboost/httr
#    - libsodium-dev : dépendance de plumber (jwt/encryption)
#    - make, gcc, g++ : compilation des packages sans binaire disponible
#    - wget : utilisé pour le HEALTHCHECK ci-dessous
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libsodium-dev \
    make \
    gcc \
    g++ \
    wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 2. Installation des packages R via les binaires précompilés (Ubuntu Noble 24.04)
#    Note : 'here' et 'readr' retirés car non utilisés par plumber.R (voir version corrigée).
#    'workflows' retiré également : non chargé dans plumber.R (à réintégrer si vous
#    utilisez un objet workflow ailleurs).
RUN R -e "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/noble/latest')); \
    install.packages(c('plumber', 'jsonlite', 'dplyr', 'xgboost', 'recipes'))"

# 3. Copie des fichiers applicatifs
COPY plumber.R /app/
COPY models /app/models

# 4. Utilisateur non-root pour l'exécution (bonne pratique sécurité)
RUN groupadd -r plumber && useradd -r -g plumber plumber \
    && chown -R plumber:plumber /app

USER plumber

EXPOSE 8080

# 5. Healthcheck basé sur l'endpoint /health exposé par l'API
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1

# 6. Lancement explicite du serveur Plumber sur le port 8080
CMD ["Rscript", "-e", "pr <- plumber::plumb('/app/plumber.R'); pr$run(host='0.0.0.0', port=8080)"]
