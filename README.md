Auteur : @Madiba

[![R](https://img.shields.io/badge/R-276DC3?style=for-the-badge&logo=r&logoColor=white)](https://www.r-project.org/)
[![Shiny](https://img.shields.io/badge/shiny-276DC3?style=for-the-badge&logo=r-shiny&logoColor=white)](https://shiny.rstudio.com/)
[![XGBoost](https://img.shields.io/badge/XGBoost-478351?style=for-the-badge&logo=xgboost&logoColor=white)](https://xgboost.readthedocs.io/)




## 📊 Telco Churn Prediction with R
**Prédiction du churn client** d'un opérateur télécom avec **XGBoost** et **Shiny**.
Ce projet illustre une approche complète : de l’analyse exploratoire à l’interprétation du modèle en passant par un test d'application Shiny interactive.

### Aperçu du projet : 
- Langage principal : R
- Algorithme utilisé : XGBoostClassifier
- Type de problème : Classification binaire
- Objectif : Identifier les clients susceptibles de résilier leur contrat afin de proposer des mesures de rétention ciblées.

Grâce à l’exploitation des données clients, l’entreprise peut :
- Anticiper le départ des abonnés,
- Optimiser ses campagnes marketing de fidélisation,
- Réduire la perte de revenus liée au churn.

### Description du jeu de données : 

#### Indicateur de churn :
- Variable cible : Churn (Oui / Non), indiquant si le client a résilié son contrat.

#### Informations sur les services souscrits : 
- Téléphonie (ligne simple ou multiple)
- Internet (DSL, fibre optique)
- Services additionnels : sécurité en ligne, sauvegarde, support technique, protection d’appareil
- Services de streaming : TV, films

#### Informations liées au compte client : 
- Ancienneté du client
- Type de contrat (mensuel, annuel, biannuel)
- Mode de paiement
- Facturation électronique
- Montant mensuel facturé
- Total des dépenses cumulées

#### Données démographiques: 
- Genre (homme, femme)
- Présence d’un partenaire
- Personnes à charge

### Étapes du projet : 
- Importation des données
- Prétraitement des données 
- Analyse exploratoire (EDA)
- Sélection de variables pertinentes
- Entraînement et évaluation du modèle XGBoostClassifier
- Interprétation du modèle
- Application Shiny interactive pour tester les prédictions

### Packages utilisés

| Catégorie                    | Packages                                         | Rôle principal                                                         |
| ---------------------------- | ------------------------------------------------ | ---------------------------------------------------------------------- |
| Manipulation & visualisation | tidyverse, dplyr, ggplot2, purrr                 | Nettoyage, transformation et visualisation des données                 |
| Exploration & diagnostic     | DataExplorer, dlookr, naniar, ggstatsplot        | Analyse exploratoire, détection des valeurs manquantes et corrélations |
| Modélisation                 | xgboost, caret, pROC                             | Entraînement, tuning et évaluation du modèle                           |
| Interprétation du modèle     | SHAPforxgboost                                   | Calcul et visualisation des valeurs SHAP                               |
| Application                  | shiny                                            | Interface utilisateur pour tester le modèle                            |


### Application Shiny : 
Une application Shiny a été développée pour :
- Permettre des tests interactifs avec différents profils clients
- Illustrer de manière intuitive comment les variables influencent la décision du modèle


