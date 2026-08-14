
FROM rocker/shiny:latest

# Installation des packages R requis pour Shiny et les requêtes HTTP
RUN R -e "install.packages(c('shiny', 'bslib', 'httr2', 'jsonlite', 'dplyr'), repos='https://cloud.r-project.org/')"

# Nettoyage des applications par défaut et copie de ton application
RUN rm -rf /srv/shiny-server/*
COPY app.R /srv/shiny-server/app.R

# Exposition du port Shiny
EXPOSE 3838

CMD ["/usr/bin/shiny-server"]