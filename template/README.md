# Template — Stack Docker Symfony

> ⚠️ Ce dossier est le **template interne** du générateur `symfony-docker-generator`.
> **Ne pas modifier directement.** Pour créer un projet, utiliser le script à la racine :
>
> ```bash
> bash generate-docker-symfony <nom-du-projet> [options]
> ```

## Services inclus dans la stack

| Service      | Image                         | Port par défaut |
|--------------|-------------------------------|-----------------|
| back         | dunglas/frankenphp + PHP 8.4 (Alpine) | :8080    |
| front        | node:22-bookworm-slim         | :3001           |
| db           | postgres:16-alpine            | :5432           |
| pgadmin      | dpage/pgadmin4                | :5052           |
| rabbitmq     | rabbitmq:3.13-management      | :15673 (UI)     |
| prometheus   | prom/prometheus:v2.51         | :9091           |
| loki         | grafana/loki:3.0              | :3101           |
| promtail     | grafana/promtail:3.0          | —               |
| tempo        | grafana/tempo:2.4             | :3201           |
| grafana      | grafana/grafana:10.4          | :4001           |
| mailpit      | axllent/mailpit (dev only)    | :8026 (UI)      |

> Les ports sont attribués automatiquement par le générateur pour chaque projet
> afin d'éviter les conflits entre projets coexistants.

## Architecture

```
  FrankenPHP (Caddy + PHP)    Next.js (optionnel)
         │                          │
         └──────────┬───────────────┘
                    │
       ┌────────────┼────────────┐
       │            │            │
  PostgreSQL   RabbitMQ     Observabilité
   + pgAdmin              Prometheus · Loki
                           Tempo · Grafana
```

## Options du générateur

| Option              | Effet                                              |
|---------------------|----------------------------------------------------|
| `--no-front`        | Supprime Next.js — Symfony sert le HTML via Twig   |
| `--no-obs`          | Supprime Prometheus / Loki / Tempo / Grafana       |
| `--php VERSION`     | Change la version PHP (défaut : 8.4)               |
| `--node VERSION`    | Change la version Node.js (défaut : 22)            |
| `--frankenphp VER`  | Change la version FrankenPHP (défaut : 1, dernier 1.x stable) |
| `--port-base N`     | Fixe le premier port du bloc (défaut : auto)       |
| `--dry-run`         | Affiche ce qui serait fait sans rien créer         |
