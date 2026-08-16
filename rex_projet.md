## Retour sur Expérience (REX) — Projet Telco Churn

- **Projet :** Système de scoring de churn client (API Plumber + Interface Shiny)

- **Auteur :** @Madiba

- **Objectif du document :** Partager les difficultés rencontrées lors de la conteneurisation et du déploiement du projet, ainsi que les solutions apportées, afin de capitaliser sur cette expérience pour les prochains projets.

---

## 1. Contexte

Le projet consistait à mettre à disposition un modèle de prédiction de churn (XGBoost) via une architecture à deux services :

- une **API REST** (Plumber/R) chargée de l'inférence,
- une **interface utilisateur Shiny** permettant à un utilisateur métier de saisir un profil client et de consulter le résultat.

L'objectif final était de faire fonctionner ces deux services de façon fiable en local, en conteneurs Docker, puis de les rendre distribuables publiquement via Docker Hub, avec un pipeline CI/CD automatisé.

Le point de départ : **les deux applications fonctionnaient parfaitement en local**, chacune lancée directement via `Rscript`, sur la même machine. Les difficultés sont apparues au moment de la conteneurisation et de l'orchestration multi-services.

---

## 2. Difficulté n°1 — La communication entre conteneurs

### Le symptôme

Une fois les deux applications conteneurisées séparément (deux `Dockerfile` distincts, un pour l'API, un pour Shiny) et démarrées ensemble, l'interface Shiny affichait systématiquement l'erreur :

> *"Erreur : L'API Plumber n'est pas démarrée sur http://127.0.0.1:8080"*

... alors même que le conteneur de l'API tournait correctement, répondait à `/health`, et qu'un test manuel avec `curl` depuis l'hôte fonctionnait sans problème.

### Le diagnostic

Le code Shiny testait la disponibilité de l'API avec un test de socket réseau avant chaque prédiction :

```r
con <- socketConnection(host = "127.0.0.1", port = 8080, timeout = 1)
```

En local, sur une seule machine, ce test avait toujours fonctionné : les deux processus R (Shiny et Plumber) partageaient le même `127.0.0.1`, donc le même espace réseau.

En revanche, **dans un environnement à deux conteneurs Docker distincts, chaque conteneur possède son propre `127.0.0.1`** — c'est une interface de bouclage locale, isolée par conteneur. Le conteneur Shiny testait donc en réalité s'il y avait une API tournant *sur lui-même*, ce qui n'était bien sûr jamais le cas.

Ce qui rendait le bug particulièrement trompeur : l'appel HTTP réel vers l'API (via `httr2`, utilisant la variable `API_URL`) était, lui, correctement configuré. Seul le test de disponibilité préalable était resté figé sur une valeur codée en dur, alors que le reste du code utilisait déjà la bonne variable d'environnement. Un bug "à moitié corrigé" — le genre le plus difficile à repérer en relecture rapide.

### La résolution

Deux actions complémentaires :

1. **Mise en place d'un réseau Docker interne partagé** (`churn-net`) dans le `docker-compose.yml`, permettant aux conteneurs de se joindre par **nom de service** (`api`, `shiny`) plutôt que par IP ou par `localhost` — mécanisme natif de *service discovery* de Docker Compose.

2. **Correction du code Shiny** pour que le test de disponibilité utilise dynamiquement la variable `API_URL` déjà présente, au lieu d'une valeur codée en dur :

```r
api_host <- sub("^https?://([^:/]+).*$", "\\1", API_URL)
api_port_raw <- sub("^https?://[^:/]+:?([0-9]*).*$", "\\1", API_URL)
api_port <- if (nzchar(api_port_raw)) as.integer(api_port_raw) else 80L

con <- socketConnection(host = api_host, port = api_port, timeout = 1)
```

### Ce qu'on en retient

- **Un code qui fonctionne en local ne garantit rien sur son comportement en conteneurs** : le réseau, en particulier, se comporte différemment dès qu'on sort d'une machine unique.
- Toute référence réseau codée en dur (`127.0.0.1`, `localhost`) est un signal d'alerte à traquer systématiquement avant de conteneuriser une application multi-services. La bonne pratique est de **toujours faire transiter les adresses par des variables d'environnement**, même pour des tests internes qui semblent secondaires.
- Un message d'erreur générique ("l'API n'est pas démarrée") peut masquer une cause radicalement différente de ce qu'il suggère — ici, l'API tournait très bien. Le message a été enrichi pour afficher l'host et le port réellement testés, afin de faciliter le diagnostic pour la suite.

---

## 3. Difficulté n°2 — Concevoir une image Docker à la fois légère et sécurisée

### Le contexte

Les packages R utilisés (`xgboost`, `httr2`, `plumber`...) nécessitent des bibliothèques systèmes de compilation (`libssl-dev`, `libcurl4-openssl-dev`, `gcc`, `g++`...) qui n'ont aucune utilité une fois l'application construite, mais qui alourdissent considérablement l'image finale si elles y restent — et augmentent la surface d'attaque en production.

### La résolution

Adoption d'un **build multi-étapes (`multi-stage build`)** :
- une étape `builder` installant les outils de compilation et les packages R,
- une étape `runtime` finale, ne conservant que les bibliothèques partagées strictement nécessaires à l'exécution (`libssl3`, `libcurl4`...), avec copie sélective du dossier `site-library` déjà compilé depuis l'étape précédente.

En complément, un **utilisateur non-root dédié** a été créé dans chaque image, afin qu'aucun des deux services ne tourne avec les privilèges root en production — bonne pratique standard de durcissement des conteneurs.

### Ce qu'on en retient

- Le multi-stage build est particulièrement pertinent pour les projets R/Python nécessitant de la compilation native : le gain en taille d'image et en surface d'attaque est significatif pour un coût de mise en œuvre faible.
- Ce choix a un effet de bord positif sur la vitesse de déploiement (image plus légère à transférer) et sur la vitesse de démarrage des conteneurs.

---

## 4. Difficulté n°3 — Concevoir un `docker-compose.yml` réellement adapté à la production

### Le contexte

Un premier jet de `docker-compose.yml` aurait pu se contenter de démarrer les deux conteneurs sans plus de précaution. Mais un fichier "qui démarre" n'est pas la même chose qu'un fichier **prêt pour la production**.

### Les points traités

- **Exposition minimale** : seul le service Shiny (interface utilisateur) est publié sur l'hôte (`ports`). L'API reste strictement interne au réseau Docker (`expose`), inaccessible depuis l'extérieur — elle ne dispose pas encore de couche d'authentification, ce qui aurait été un risque si elle avait été exposée publiquement.
- **Ordre de démarrage fiable** : `depends_on` avec `condition: service_healthy`, pour que Shiny ne démarre réellement qu'une fois l'API certifiée saine via son endpoint `/health` — et non pas simplement "lancée".
- **Mise à jour du modèle sans rebuild** : montage des artefacts ML (`models/`) en volume, ce qui permet de déployer une nouvelle version du modèle en remplaçant simplement des fichiers sur l'hôte, sans reconstruire l'image Docker.
- **Maîtrise des ressources et des logs** : limites CPU/mémoire par service, rotation des logs, pour éviter qu'un conteneur ne dégrade la stabilité globale du serveur hôte.

### Ce qu'on en retient

- Un environnement de production impose des exigences (sécurité, résilience, observabilité) qui n'apparaissent pas nécessairement lors des premiers tests en local. Se poser systématiquement la question *"qu'est-ce qui doit être vrai en prod et qui ne l'est pas forcément en local ?"* permet d'anticiper une bonne partie de ces points.

---

## 5. Difficulté n°4 — Automatiser la publication sans complexifier inutilement

### Le contexte

Le besoin initial de CI/CD a évolué en cours de projet : la première intention envisagée était un déploiement automatique sur un serveur de production via SSH. Après clarification du besoin réel — rendre les images **publiquement accessibles à des partenaires externes via Docker Hub**, sans serveur cible imposé — le pipeline a été révisé pour rester centré sur cet objectif, plutôt que de conserver des étapes de déploiement devenues inutiles.

### La résolution

- Parallélisation des deux jobs de build (API et Shiny), auparavant séquentiels dans un seul job, réduisant le temps total d'exécution du pipeline.
- Mise en cache des couches Docker entre les runs (cache GitHub Actions), pour éviter de réinstaller les packages R à chaque exécution alors que le code n'a pas changé.
- Passage d'un tag unique (`latest` + SHA) à une **stratégie de versionnage sémantique** (`1.2.0`, `1.2`, `1`) déclenchée par les tags Git, afin que les utilisateurs externes des images puissent figer une version stable plutôt que de dépendre uniquement de `latest`.

### Ce qu'on en retient

- Clarifier précisément la finalité d'un pipeline CI/CD avant de l'écrire évite d'ajouter de la complexité (accès SSH, secrets serveur, gestion d'environnements) qui n'a pas lieu d'être si l'objectif réel est simplement une publication d'images. Il vaut mieux un pipeline simple et strictement aligné sur le besoin qu'un pipeline complet mais partiellement inutilisé.

---

## 6. Synthèse des enseignements généraux

| Enseignement | Application concrète dans ce projet |
|---|---|
| Le comportement réseau change entre local et conteneurs | Bannir les adresses codées en dur, tout faire passer par des variables d'environnement |
| Un message d'erreur peut être trompeur | Toujours vérifier l'hypothèse la plus simple avant d'investiguer plus loin (ici : le test de disponibilité, pas l'API elle-même) |
| La sécurité d'image se construit dès le Dockerfile | Multi-stage build, utilisateur non-root, dépendances minimales en runtime |
| "Ça démarre" ≠ "C'est prêt pour la prod" | Healthchecks, exposition réseau maîtrisée, gestion des ressources et des logs |
| Un pipeline CI/CD doit servir un objectif précis | Adapter le pipeline au besoin réel plutôt que d'anticiper des fonctionnalités non demandées |

---

## 7. Prochaines pistes d'amélioration identifiées

- Ajouter une authentification légère sur l'API (clé API) si elle venait à être exposée au-delà du réseau interne.
- Faire évoluer l'interface Shiny pour supporter le scoring par lot (batch), l'API le permettant déjà côté backend.
- Ajouter des tests automatisés (unitaires sur la validation des entrées API, tests d'intégration bout en bout) dans le pipeline CI, en amont du build des images.
- Restreindre la politique CORS de l'API (`Access-Control-Allow-Origin`) si un usage plus large que le client Shiny actuel est envisagé.
