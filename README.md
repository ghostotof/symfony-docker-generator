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
symfony-docker-generator/
├── generate-docker-symfony     ← script générateur
├── template/                   ← stack Docker (ne pas modifier)
└── projects/
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

Symfony installe uniquement les composants API :

```
api-platform/core · doctrine · symfony/messenger
symfony/validator · nelmio/cors-bundle
lexik/jwt-authentication-bundle · opentelemetry
```

### Mode fullstack Twig *(`--no-front`)*

Symfony installe les bundles web en plus :

```
symfony/twig-bundle · twig/extra-bundle
symfony/asset-mapper · symfony/webpack-encore-bundle
doctrine · symfony/messenger · symfony/validator
lexik/jwt-authentication-bundle · opentelemetry
```

Le Caddyfile est adapté : cache agressif des assets, headers de sécurité
renforcés, pas de CORS inter-domaine.

## Gestion des ports

Le générateur lit les `.env` de tous les projets existants dans `projects/`
et alloue automatiquement le prochain bloc de 10 ports libres à partir de `:8080`.
Deux projets ne se marcheront jamais dessus.

```
PORT_BASE + 0  →  backend (FrankenPHP)
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
cd projects/<nom-du-projet>
make bootstrap   # initialise Symfony, Next.js, démarre tout
make help        # liste toutes les commandes disponibles
```

## Observabilité

Grafana est accessible sur le port alloué avec un dashboard **Overview** préchargé :
métriques HTTP FrankenPHP/Caddy, files RabbitMQ, logs Loki, service map Tempo.
Les logs, métriques et traces sont corrélés entre eux (clic sur un `trace_id`
dans les logs → trace Tempo, et inversement).
