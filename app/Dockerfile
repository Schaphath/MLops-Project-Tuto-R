# Auteur : @Madiba

#==================================================#
# ÉTAPE 1 : Builder (Installation des packages R)  #
#==================================================#
FROM rocker/r-ver:4.4 AS builder

# Dépendances système requises pour le build
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

# Installation des packages R via Posit PPM (Noble) + Nettoyage de la documentation
RUN R -e "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/noble/latest')); \
    install.packages(c('shiny', 'bslib', 'DT', 'dplyr', 'httr2', 'jsonlite'))" \
    && rm -rf /usr/local/lib/R/site-library/*/doc \
    && rm -rf /usr/local/lib/R/site-library/*/help \
    && rm -rf /usr/local/lib/R/site-library/*/html


#==================================================#
# ÉTAPE 2 : Image de Runtime (Execution sécurisée) #
#==================================================#
FROM rocker/r-ver:4.4 AS runtime

WORKDIR /app

# Installation des bibliothèques système de RUNTIME uniquement
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libssl3 \
    libcurl4 \
    libxml2 \
    libsodium23 \
    wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Création de l'utilisateur non-root dédié avec UID/GID fixe
RUN groupadd -g 10001 shinygroup && \
    useradd -u 10001 -g shinygroup -m -d /home/shiny -s /sbin/nologin shinyuser && \
    chown -R shinyuser:shinygroup /app /home/shiny

# Copie des bibliothèques R pré-installées depuis l'étape builder
COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library

# Copie de shiny.R vers /app avec la bonne propriété utilisateur
COPY --chown=shinyuser:shinygroup shiny.R /app/app.R

USER 10001

EXPOSE 3838

ENV API_URL="http://api:8080"

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:3838/ || exit 1

# Lancement de l'application Shiny
CMD ["Rscript", "-e", "shiny::runApp('/app', host='0.0.0.0', port=3838)"]
