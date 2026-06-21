# symfony-docker-generator

Générateur de stack Docker clé-en-main pour projets Symfony.

Un seul script crée un projet complet avec **FrankenPHP** (PHP 8.4 · Alpine),
**PostgreSQL**, **RabbitMQ** et une suite d'observabilité
**Prometheus · Loki · Tempo · Grafana**, le tout configuré et prêt à démarrer.

## Prérequis

- Docker ≥ 25 avec le plugin Compose
- Bash ≥ 4
- Git (optionnel, pour l'init du dépôt projet)
- `openssl` (pour la génération des secrets)

## Utilisation

```bash
bash generate-docker-symfony <nom-du-projet> [options]
```

Le projet est créé dans le **répertoire courant** au moment du lancement du script.

### Exemples

```bash
# Projet standard : Symfony API + Next.js + observabilité
bash generate-docker-symfony monprojet

# Symfony fullstack Twig (pas de Next.js)
bash generate-docker-symfony monprojet --no-front

# Sans observabilité
bash generate-docker-symfony monprojet --no-obs

# Épingler une version FrankenPHP précise
bash generate-docker-symfony monprojet --frankenphp 1.4

# Forcer un bloc de ports précis (utile si plusieurs projets tournent)
bash generate-docker-symfony monprojet --port-base 9000

# Aperçu sans rien créer
bash generate-docker-symfony monprojet --dry-run
```

## Options

| Option                | Description                                                        |
|-----------------------|--------------------------------------------------------------------|
| `--port-base N`       | Premier port du bloc alloué (défaut : auto-détection)             |
| `--php VERSION`       | Version PHP dans FrankenPHP (défaut : `8.4`)                      |
| `--node VERSION`      | Version Node.js pour Next.js (défaut : `22`)                      |
| `--frankenphp VER`    | Version FrankenPHP (défaut : `1`, dernier 1.x stable)             |
| `--env ENV`           | Environnement initial `dev` ou `prod` (défaut : `dev`)            |
| `--no-front`          | Supprime Next.js — Symfony sert le HTML via Twig                  |
| `--no-obs`            | Supprime Prometheus / Loki / Tempo / Grafana                      |
| `--no-git`            | Ne pas initialiser de dépôt Git dans le projet généré             |
| `--force`             | Écraser le répertoire de destination s'il existe déjà             |
| `--dry-run`           | Affiche le récapitulatif sans rien créer                          |

## Structure générée

```
<répertoire-courant>/
└── <nom-du-projet>/
    ├── .env                ← secrets auto-générés (ne pas commiter)
    ├── .env.example        ← template sans secrets (à commiter)
    ├── .gitignore
    ├── docker-compose.yaml
    ├── docker-compose.override.yml   (dev)
    ├── docker-compose.prod.yml       (prod)
    ├── Makefile            ← ~30 commandes make
    ├── back/
    │   ├── app/            ← code Symfony (vide, initialisé par bootstrap)
    │   ├── Caddyfile
    │   └── Dockerfile      ← multi-stage dev/prod
    ├── front/              ← absent si --no-front
    │   └── app/            ← code Next.js (vide, initialisé par bootstrap)
    ├── db/
    ├── rabbitmq/
    ├── observability/      ← absent si --no-obs
    └── scripts/
        └── bootstrap.sh    ← initialise Symfony + Next.js au premier lancement
```

## Modes Symfony

### Mode API + Next.js *(défaut)*

Utilise `symfony new` (skeleton minimal) puis installe :

```
api-platform/core · symfony/security-bundle · doctrine
symfony/messenger · symfony/validator · symfony/uid
nelmio/cors-bundle · lexik/jwt-authentication-bundle
opentelemetry
```

Symfony expose uniquement une API JSON. Next.js assure le rendu côté client.

### Mode fullstack Twig *(`--no-front`)*

Utilise `symfony new --webapp` (commande officielle Symfony) qui installe
le meta-package `symfony/webapp` incluant : Twig, AssetMapper, security-bundle,
form, validator, http-client, mailer, notifier. Puis s'ajoutent :

```
doctrine · symfony/messenger · symfony/uid · opentelemetry
```

Le Caddyfile est adapté : cache agressif des assets, headers de sécurité
renforcés, pas de CORS inter-domaine.
`symfony/webpack-encore-bundle` est intentionnellement exclu (nécessite Node.js,
absent du container FrankenPHP — utiliser AssetMapper à la place).

## HTTPS et domaine

FrankenPHP/Caddy gère le HTTPS automatiquement via la variable `SERVER_NAME` :

| Environnement | `SERVER_NAME`        | Comportement                                     |
|---------------|----------------------|--------------------------------------------------|
| Dev           | `localhost:8080`     | Certificat local signé par la CA Caddy           |
| Prod          | `monsite.com`        | Certificat Let's Encrypt, port 443 standard      |

En dev, le backend est accessible sur `https://localhost:<BACK_PORT>`.
Après la première visite, le header HSTS pousse le navigateur à toujours
utiliser `https://` automatiquement.

En prod, changer `SERVER_NAME=monsite.com` dans le `.env` suffit — Caddy
obtient et renouvelle le certificat Let's Encrypt sans configuration supplémentaire.

## Gestion des ports

Le générateur lit les `.env` de tous les projets existants dans le répertoire
courant et alloue automatiquement le prochain bloc de 8 ports libres à partir
de `:8080`. Deux projets ne se marcheront jamais dessus.

```
PORT_BASE + 0  →  backend HTTPS (FrankenPHP)
PORT_BASE + 1  →  frontend (Next.js)
PORT_BASE + 2  →  pgAdmin
PORT_BASE + 3  →  RabbitMQ UI
PORT_BASE + 4  →  Prometheus
PORT_BASE + 5  →  Loki
PORT_BASE + 6  →  Tempo
PORT_BASE + 7  →  Grafana
```

## Premier lancement d'un projet

```bash
cd <nom-du-projet>
make bootstrap   # initialise Symfony (+ Next.js si applicable), démarre tout
make help        # liste toutes les commandes disponibles
```

## Observabilité

Grafana est accessible sur le port alloué avec un dashboard **Overview** préchargé :
métriques HTTP FrankenPHP/Caddy, files RabbitMQ, logs Loki, service map Tempo.
Les logs, métriques et traces sont corrélés entre eux (clic sur un `trace_id`
dans les logs → trace Tempo, et inversement).
