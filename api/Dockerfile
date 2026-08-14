FROM rstudio/plumber:latest

# Installation des dépendances système nécessaires
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# Installation des packages R requis
RUN R -e "install.packages(c('jsonlite', 'dplyr', 'readr', 'xgboost', 'recipes', 'here'), repos='https://cloud.r-project.org/')"

# Copie du code et des artefacts
COPY . /app
WORKDIR /app

# Exposition du port Plumber
EXPOSE 8080

# Lancement de l'API via l'entrypoint
CMD ["Rscript", "entrypoint.R"]