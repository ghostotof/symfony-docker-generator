# create-symfony-project.sh

Script bash de scaffolding qui génère un projet Symfony entièrement dockerisé, prêt à développer et prêt à déployer.

Une exécution produit une arborescence complète : configuration Docker Compose pour le développement local, Dockerfiles multi-stage pour les environnements déployés, et un Makefile qui sert d'interface unique aux opérations courantes.

```bash
./create-symfony-project.sh mon-projet              # Symfony full-stack
./create-symfony-project.sh mon-projet --frontend   # API Platform + Vite dédié
```

---

## Installation

Pour appeler la commande depuis n'importe où :

```bash
./install.sh              # lien dans ~/.local/bin (sans sudo)
./install.sh --system     # lien dans /usr/local/bin (demande sudo)
./install.sh --uninstall  # retire le lien
```

L'installation crée un **lien symbolique**, pas une copie : le script reste
modifiable dans son dépôt et toute mise à jour est immédiatement effective.
Si le répertoire cible n'est pas dans le `PATH`, le script détecte le shell
utilisé et affiche la ligne exacte à ajouter à sa configuration.

```bash
create-symfony-project mon-projet --frontend
```

---

## Sommaire

- [Prérequis](#prérequis)
- [Utilisation](#utilisation)
- [Les deux modes de génération](#les-deux-modes-de-génération)
- [Gestion des versions](#gestion-des-versions)
- [Gestion des droits d'accès](#gestion-des-droits-daccès)
- [Arborescence générée](#arborescence-générée)
- [Les services](#les-services)
- [Le Dockerfile backend](#le-dockerfile-backend)
- [Le Dockerfile frontend](#le-dockerfile-frontend)
- [Le Makefile](#le-makefile)
- [Déroulé d'une exécution](#déroulé-dune-exécution)
- [Limites connues](#limites-connues)

---

## Prérequis

| Outil | Rôle |
|---|---|
| `bash` 4+ | Le script utilise les tableaux et `[[ ]]` |
| `curl` | Interrogation des APIs de versions |
| `jq` | Parsing des réponses JSON |
| `git` | Initialisation du dépôt |
| `docker` + plugin `compose` v2 | Build et démarrage (sauf en `--no-build`) |

`docker-compose` v1 n'est pas supporté : le script vérifie explicitement la présence de `docker compose` (sous-commande, pas binaire séparé).

Le script est prévu pour un hôte **Linux**. Sur macOS ou WSL2, la gestion des droits par UID/GID fonctionne différemment et demanderait des ajustements.

---

## Utilisation

```
./create-symfony-project.sh <nom-du-projet> [options]
```

Le nom du projet est **obligatoire**. Il sert à la fois de nom de dossier, de préfixe aux conteneurs Docker et de nom de base de données — il est donc validé contre `^[a-z0-9]([a-z0-9_-]*[a-z0-9])?$`, la contrainte imposée par Docker Compose.

| Option | Effet |
|---|---|
| `--frontend` | Ajoute un service `frontend` dédié (Node + Vite) et bascule le backend en mode API |
| `--path <dir>` | Répertoire parent dans lequel créer le projet (défaut : `.`) |
| `--no-build` | Génère les fichiers sans construire ni démarrer les conteneurs |
| `-h`, `--help` | Affiche l'aide |

Le script refuse d'écraser un dossier existant.

---

## Les deux modes de génération

C'est la décision structurante du script : `--frontend` ne se contente pas d'ajouter un service, il change la nature du backend.

**Sans `--frontend`** — le backend est un Symfony complet (`symfony new --webapp`) qui gère lui-même le rendu : Twig, AssetMapper, formulaires, sécurité. Un seul service applicatif, une seule URL.

**Avec `--frontend`** — le backend devient un squelette Symfony minimal auquel on ajoute uniquement API Platform, l'ORM et Messenger. Aucune couche de présentation. Le rendu est délégué au service `frontend`, qui appelle l'API par HTTP.

Ce choix est enregistré dans `.env` sous `BACKEND_FLAVOR` (`full` ou `api`) et consommé aussi bien par le script d'initialisation Symfony que par le stage de build production, qui ne compile les assets qu'en mode `full`.

---

## Gestion des versions

Toutes les versions « stable latest » sont **résolues au moment de l'exécution** puis **figées en dur** dans les fichiers générés.

Le script interroge cinq sources :

| Source | Ce qu'elle fournit |
|---|---|
| Docker Hub | php, nginx, postgres, rabbitmq, node, composer |
| GitHub Releases | symfony-cli |
| Packagist | symfony/skeleton, api-platform/symfony |
| PECL | ext-amqp, ext-xdebug |
| npm registry | create-vite |

Deux filtrages méritent d'être signalés, parce qu'un simple « dernière version » donnerait un résultat faux :

- **nginx** — la branche *stable* correspond aux versions à mineur **pair** (1.28, 1.26…), la branche *mainline* aux mineurs impairs. Le script ne retient que les pairs.
- **Node** — les versions **LTS** sont celles à majeur **pair**. Les majeurs impairs (branche *Current*) sont écartés.

En cas d'échec réseau, chaque résolution retombe sur une valeur de secours codée en dur, avec un avertissement visible. Le script reste donc utilisable hors ligne, mais on sait alors qu'on n'a pas les dernières versions.

Le résultat est écrit à deux endroits : `.env` (consommé par Docker Compose) et `versions.lock` (lisible, destiné à la revue de code et à la CI).

```
php=8.4.11-fpm-alpine3.22
nginx=1.28.0-alpine
postgres=17.5-alpine
rabbitmq=4.1.0-management-alpine
composer=2
composer-resolved=2.8.9
symfony-cli=5.14.0
ext-amqp=2.1.2
ext-xdebug=3.4.1
symfony=7.3.0
api-platform=4.1.0
node=22.14.0-alpine
create-vite=9.1.1
```

### Deux pièges que le script gère explicitement

**opcache n'est plus une extension partagée depuis PHP 8.5.** Il est intégré au
binaire, donc `docker-php-ext-install opcache` configure l'extension, ne compile
rien, puis échoue sur `cp: can't stat 'modules/*'`. Comme le script résout PHP en
« stable latest », il tombe sur 8.5.x dès aujourd'hui. Le Dockerfile teste donc
`php -m` et n'installe opcache que s'il est absent — ce qui le garde valable
aussi bien pour 8.4 que pour 8.5+.

**`symfony/skeleton` ne publie pas de versions classiques.** Chaque branche a un
unique tag placeholder dont le patch vaut toujours 99 (`v7.3.99`, `v8.1.99`…).
« 8.1.99 » n'est donc pas une version de Symfony. Le script ne conserve que
`MAJEUR.MINEUR`, qui est ce qu'attend `symfony new --version=`. Le figeage réel
des dépendances applicatives est assuré par `composer.lock`, généré à
l'initialisation et versionné avec le projet.

### L'exception Composer

Composer est le seul outil épinglé sur sa **branche majeure** (`composer:2`) plutôt que sur une version exacte. C'est un compromis assumé :

- Composer est un outil de *build*, pas une dépendance applicative — les correctifs 2.x sont bienvenus ;
- mais un futur Composer 3, potentiellement cassant, ne doit jamais s'installer sans action explicite.

La version réellement disponible à la génération est tout de même tracée dans `versions.lock` sous `composer-resolved`, pour pouvoir figer complètement si le besoin s'en fait sentir.

---

## Gestion des droits d'accès

L'objectif : pouvoir éditer dans son IDE les fichiers créés par le conteneur, sans jamais « entrer » dedans ni lancer de `chown`.

Le mécanisme repose sur l'alignement des identifiants. Au lancement, le script relève `id -u` et `id -g` et les écrit dans `.env`. Docker Compose les passe ensuite en arguments de build, et le Dockerfile crée un utilisateur `dev` portant exactement ces UID/GID. Le pool php-fpm tourne sous cette identité.

Conséquence : tout ce qu'écrit le conteneur — `vendor/`, `var/cache`, le code généré par le maker-bundle — appartient à l'utilisateur hôte et reste directement éditable.

Le service `frontend` obtient le même résultat sans build, via `user: "${UID}:${GID}"` dans Compose. Comme cet utilisateur n'a pas forcément de home dans l'image Node, `HOME` et le cache npm sont redirigés vers `/tmp` — sans quoi `npm install` échouerait en `EACCES`.

> **Si un autre développeur clone le projet**, il doit ajuster `UID`/`GID` dans `.env` à son poste puis relancer `make build`.

En production, la logique s'inverse : plus de bind mount, donc plus besoin d'alignement. Un UID fixe et arbitraire (10001) est utilisé, ce que `runAsNonRoot` exige côté Kubernetes.

---

## Arborescence générée

```
mon-projet/
├── .dockerignore
├── .env                          # versions figées + UID/GID + ports
├── .gitignore
├── Makefile
├── README.md                     # documentation du projet généré
├── versions.lock                 # récapitulatif lisible des versions
├── docker-compose.yml
├── docker-compose.override.yml   # service frontend        [--frontend]
├── backend/                      # code Symfony
├── frontend/                     # code Vite              [--frontend]
└── docker/
    ├── nginx/
    │   └── default.conf          # reverse proxy dev vers php-fpm
    ├── php/
    │   ├── Dockerfile            # multi-stage
    │   ├── php.dev.ini
    │   ├── php.prod.ini
    │   ├── www.dev.conf
    │   ├── www.prod.conf
    │   ├── xdebug.preprod.ini
    │   ├── healthcheck.sh
    │   └── init-symfony.sh
    └── node/                                              [--frontend]
        ├── Dockerfile            # multi-stage
        └── nginx.conf            # service des fichiers statiques
```

Les entrées marquées `[--frontend]` ne sont créées qu'avec l'option. Sans elle, ni `docker/node/`, ni `docker-compose.override.yml`, ni les cibles Makefile associées n'existent.

---

## Les services

| Service | Image | Rôle | Port hôte |
|---|---|---|---|
| `backend` | construite | PHP-FPM + Symfony | — |
| `web` | `nginx` | Reverse proxy HTTP | 8080 |
| `database` | `postgres` | Base de données | 5432 |
| `rabbitmq` | `rabbitmq` (management) | Broker Messenger | 5672 / 15672 |
| `frontend` | `node` | Serveur de dev Vite | 5173 |

**Un seul service est construit**, même avec `--frontend`. Les autres utilisent leur image officielle telle quelle. Le service `frontend` lance `npm install && npm run dev` au démarrage : il n'y a rien à construire en développement.

`backend` attend que `database` et `rabbitmq` soient réellement prêts (`condition: service_healthy`), et non simplement démarrés — les deux services exposent un healthcheck pour cela.

Le service `web` monte le code en **lecture seule** : nginx n'a besoin que de servir les assets statiques et de connaître le chemin de `public/index.php`.

---

## Le Dockerfile backend

Cinq stages, avec un enchaînement qui n'est pas linéaire :

```
composer_bin ─┐
              ├─► base ─┬─► dev
php:x.y-fpm ──┘         ├─► vendor ─┐
                        └───────────┴─► production ─► preprod
```

| Stage | Rôle |
|---|---|
| `composer_bin` | Récupère le binaire Composer depuis son image officielle |
| `base` | PHP + extensions (intl, pdo_pgsql, zip, opcache, sockets, amqp). Socle commun à toutes les cibles — c'est ce qui garantit que dev et prod partagent le même moteur |
| `dev` | Ajoute symfony-cli, git, bash, l'utilisateur aligné sur l'hôte, opcache en revalidation immédiate |
| `vendor` | `composer install --no-dev` isolé. Ne copie que `composer.json`/`composer.lock`, donc modifier du code n'invalide pas cette couche coûteuse |
| `production` | Code **copié** (plus de montage), autoloader `classmap-authoritative`, opcache verrouillé avec preloading, Composer supprimé, exécution en `app` (UID 10001) |
| `preprod` | Construit **à partir de** `production`, + Xdebug en profilage |

### Pourquoi `preprod` hérite de `production`

C'est le point de conception le plus important du fichier. Si les deux images étaient construites en parallèle depuis `base`, on validerait en préprod un artefact *cousin* de celui déployé, pas le même — ce qui vide la préproduction de son sens.

En écrivant `FROM production AS preprod`, les couches applicatives sont identiques à l'octet près. La préprod est « l'image de production, plus des outils de diagnostic ».

L'ordre de déclaration dans le fichier (`production` avant `preprod`) est une contrainte de Docker, pas un ordre de pipeline. Celui-ci reste **dev → préprod → prod**.

Xdebug y est configuré en mode `profile,trace` — jamais `debug`, qui ouvrirait un port d'attachement sur un environnement partagé. Le déclenchement est manuel via `XDEBUG_TRIGGER` : le surcoût est nul sur le trafic normal, ce qui rend les mesures de performance exploitables. `APP_DEBUG` reste à `0` : seule la verbosité des logs change.

### Contexte de build

Le contexte est la **racine du projet**, pas `docker/php`, car les stages de déploiement doivent copier `./backend`. D'où le `.dockerignore` — sans lui, chaque build enverrait `vendor/`, `var/` et `node_modules` au démon Docker et invaliderait le cache en permanence — et le `target: dev` explicite dans Compose, sans lequel Docker construirait le dernier stage du fichier.

---

## Le Dockerfile frontend

Généré uniquement avec `--frontend`. Quatre stages :

| Stage | Rôle |
|---|---|
| `deps` | `npm ci` isolé, pour le cache de couches |
| `build` | Compilation Vite |
| `production` | nginx servant le bundle compilé, port 8080, utilisateur `nginx` |
| `preprod` | `FROM production` + les source maps |

Le même principe qu'au backend est appliqué : les source maps sont générées **systématiquement**, y compris pour la production, puis déplacées hors du répertoire servi. `production` reçoit le bundle seul, `preprod` n'y rajoute que les `.map`. Les fichiers JS/CSS exécutés sont donc identiques entre les deux images.

> **À retenir** : Vite *inline* les variables `VITE_*` dans le bundle **au moment du build**. `API_URL` est donc un `--build-arg`, pas une variable d'exécution — changer l'URL de l'API impose de reconstruire l'image.

La configuration nginx gère le routage SPA (`try_files ... /index.html`), un cache immuable d'un an sur `/assets/` — les fichiers y sont hashés par Vite, leur contenu ne change jamais pour une URL donnée — et un `no-store` sur `index.html`, qui référence les nouveaux assets après déploiement.

---

## Le Makefile

Interface unique aux opérations courantes. `make help` liste les cibles :

```
  help                 Affiche cette aide
  build                Construit les images
  up                   Démarre la stack en arrière-plan
  down                 Arrête la stack (les volumes sont conservés)
  restart              Redémarre la stack
  logs                 Suit les logs de tous les services
  sh                   Ouvre un shell dans le backend, en tant qu'utilisateur dev
  init                 (Re)joue l'initialisation du projet Symfony
  db-migrate           Applique les migrations Doctrine
  consume              Lance le worker Messenger (transport async)
  build-prod           Construit l'image de production (TAG=... IMAGE=...)
  build-preprod        Construit l'image de préprod (= prod + outils de diagnostic)
  sh-front             Ouvre un shell dans le conteneur frontend
  front-init           Crée le projet Vite en mode INTERACTIF (à lancer une seule fois)
  build-front-prod     Construit l'image frontend de production (API_URL=... TAG=...)
  build-front-preprod  Construit l'image frontend de préprod (= prod + source maps)
```

Les quatre dernières cibles n'apparaissent qu'en mode `--frontend`.

Les cibles `build-*` n'utilisent **pas** Docker Compose : elles produisent un artefact destiné à un registry, pas un conteneur local. Le tag par défaut reprend le SHA court du commit courant, ce qui rend chaque image traçable jusqu'à la révision exacte du code qu'elle contient.

```bash
make build-prod TAG=1.2.3
make build-front-prod API_URL=https://api.exemple.com TAG=1.2.3
```

---

## Déroulé d'une exécution

1. **Parsing et validation** — nom du projet obligatoire et conforme, dossier cible libre
2. **Vérification des prérequis** — présence de `curl`, `jq`, `git`, et de `docker compose` si build
3. **Résolution des versions** — interrogation des cinq APIs, avec fallback en cas d'échec
4. **Récapitulatif à l'écran** — le développeur voit exactement ce qui va être figé
5. **Génération des fichiers** — `.env`, `versions.lock`, Dockerfiles, configs, Compose, Makefile, README, `.gitignore`, `git init`
6. **Build des images** *(sauf `--no-build`)*
7. **Initialisation Symfony** — `symfony new` exécuté en tant que `dev` dans le conteneur, puis installation d'API Platform si mode API, puis génération de `.env.local` avec les DSN pointant vers les services Docker
8. **Initialisation Vite** *(mode `--frontend`)* — `npm create vite` lancé en **interactif** : `docker compose run` alloue un TTY, le développeur répond normalement aux questions
9. **Démarrage de la stack** et affichage des URLs

L'étape 7 est idempotente : si `composer.json` existe déjà, elle ne fait rien. Elle est rejouable via `make init`.

---

## Limites connues

- **Hôte Linux uniquement.** L'alignement UID/GID ne se transpose pas tel quel à macOS (VM intermédiaire) ni à Windows sans WSL2.
- **`.env` n'est pas versionné pour les secrets.** Les identifiants générés (`app`/`app`) sont des valeurs de développement. En déployé, ils doivent venir de l'orchestrateur — les configs php-fpm de production sont écrites pour laisser passer les variables d'environnement sans les figer.
- **Pas de manifests Kubernetes.** Les stages `production` et `preprod` en sont le prérequis ; le healthcheck FastCGI est déjà prévu pour servir de `livenessProbe`. Reste à écrire la base Kustomize.
- **Pas de pipeline CI.** Les cibles `build-*` sont conçues pour y être appelées, mais rien n'est généré.
- **`database` et `rabbitmq` restent des conteneurs de développement.** En déployé, ils ont vocation à être remplacés par des services managés ou des opérateurs (CloudNativePG, RabbitMQ Cluster Operator).
