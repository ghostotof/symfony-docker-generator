# symfony-docker-generator

Générateur de stack Docker clé-en-main pour projets Symfony.

Un seul script crée un projet complet avec **FrankenPHP** (PHP 8.4 · Alpine),
**PostgreSQL**, **RabbitMQ** et **Mailpit** (capture mail dev), le tout configuré
et prêt à démarrer. La stack d'observabilité **Prometheus · Loki · Tempo · Grafana**
est disponible en option.

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
# Projet Symfony fullstack Twig (défaut)
bash generate-docker-symfony monprojet

# Symfony API JSON + Next.js (SPA/SSR)
bash generate-docker-symfony monprojet --spa

# Avec observabilité (Prometheus / Loki / Tempo / Grafana)
bash generate-docker-symfony monprojet --with-obs

# Next.js + observabilité
bash generate-docker-symfony monprojet --spa --with-obs

# Épingler Node.js (uniquement avec --spa)
bash generate-docker-symfony monprojet --spa --node 20

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
| `--node VERSION`      | Version Node.js pour Next.js, défaut : `22` — requiert `--spa`    |
| `--frankenphp VER`    | Version FrankenPHP (défaut : `1`, dernier 1.x stable)             |
| `--env ENV`           | Environnement initial `dev` ou `prod` (défaut : `dev`)            |
| `--spa`               | Ajoute Next.js — Symfony expose une API JSON, Next.js gère le HTML |
| `--with-obs`          | Ajoute Prometheus / Loki / Tempo / Grafana                        |
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
    ├── front/              ← présent uniquement avec --spa
    │   └── app/            ← code Next.js (vide, initialisé par bootstrap)
    ├── db/
    ├── rabbitmq/
    ├── observability/      ← présent uniquement avec --with-obs
    └── scripts/
        └── bootstrap.sh    ← initialise Symfony + Next.js au premier lancement
```

## Modes Symfony

### Mode fullstack Twig *(défaut)*

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

### Mode API + Next.js *(`--spa`)*

Utilise `symfony new` (skeleton minimal) puis installe :

```
api-platform/core · symfony/security-bundle · doctrine
symfony/messenger · symfony/validator · symfony/uid
nelmio/cors-bundle · lexik/jwt-authentication-bundle
opentelemetry
```

Symfony expose uniquement une API JSON. Next.js assure le rendu côté client.

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
courant et alloue automatiquement le prochain bloc de **10 ports** libres à partir
de `:8080`. Deux projets ne se marcheront jamais dessus.

```
PORT_BASE + 0  →  backend HTTPS (FrankenPHP)
PORT_BASE + 1  →  frontend (Next.js) — réservé même sans --spa
PORT_BASE + 2  →  pgAdmin
PORT_BASE + 3  →  RabbitMQ UI
PORT_BASE + 4  →  Prometheus        — réservé même sans --with-obs
PORT_BASE + 5  →  Loki              — réservé même sans --with-obs
PORT_BASE + 6  →  Tempo             — réservé même sans --with-obs
PORT_BASE + 7  →  Grafana           — réservé même sans --with-obs
PORT_BASE + 8  →  Mailpit SMTP
PORT_BASE + 9  →  Mailpit UI
```

## Premier lancement d'un projet

```bash
cd <nom-du-projet>
make init        # initialise Symfony (+ Next.js si --spa), démarre tout
make help        # liste toutes les commandes disponibles
```

## Observabilité

Activée avec `--with-obs`. Grafana est accessible sur le port alloué avec un
dashboard **Overview** préchargé : métriques HTTP FrankenPHP/Caddy, files
RabbitMQ, logs Loki, service map Tempo. Les logs, métriques et traces sont
corrélés entre eux (clic sur un `trace_id` dans les logs → trace Tempo, et
inversement).
