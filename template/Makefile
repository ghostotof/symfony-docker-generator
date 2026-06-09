.DEFAULT_GOAL := help
COMPOSE      = docker compose
COMPOSE_PROD = docker compose -f docker-compose.yaml -f docker-compose.prod.yml

##@ 🐳 Docker
.PHONY: up down restart build logs ps clean

up: ## Démarrer la stack (dev)
	$(COMPOSE) up -d

down: ## Arrêter les containers
	$(COMPOSE) down

restart: ## Redémarrer tous les services
	$(COMPOSE) restart

build: ## Reconstruire les images
	$(COMPOSE) build --no-cache

logs: ## Logs temps réel (tous services)
	$(COMPOSE) logs -f

ps: ## Statut des containers
	$(COMPOSE) ps

clean: ## Supprimer containers, volumes et images
	$(COMPOSE) down -v --rmi local

##@ 🚀 Bootstrap
.PHONY: bootstrap

bootstrap: ## Premier lancement complet du projet
	@bash scripts/bootstrap.sh

##@ 🔧 Backend (FrankenPHP + Symfony)
.PHONY: back-sh back-cc back-migrate back-diff back-fixtures back-test back-composer back-consumer back-jwt

back-sh: ## Shell dans le container back
	$(COMPOSE) exec back bash

back-cc: ## Vider le cache Symfony
	$(COMPOSE) exec back php bin/console cache:clear

back-migrate: ## Lancer les migrations Doctrine
	$(COMPOSE) exec back php bin/console doctrine:migrations:migrate --no-interaction

back-diff: ## Générer une migration depuis les entités
	$(COMPOSE) exec back php bin/console doctrine:migrations:diff

back-fixtures: ## Charger les fixtures
	$(COMPOSE) exec back php bin/console doctrine:fixtures:load --no-interaction

back-test: ## Lancer PHPUnit
	$(COMPOSE) exec back php bin/phpunit

back-composer: ## composer install
	$(COMPOSE) exec back composer install

back-consumer: ## Démarrer le consumer Messenger
	$(COMPOSE) exec back php bin/console messenger:consume async --time-limit=3600 -vv

back-jwt: ## (Re)générer les clés JWT
	$(COMPOSE) exec back php bin/console lexik:jwt:generate-keypair --skip-if-exists

##@ 🎨 Frontend (Next.js)
.PHONY: front-sh front-install front-build front-lint front-types

front-sh: ## Shell dans le container front
	$(COMPOSE) exec front sh

front-install: ## npm install
	$(COMPOSE) exec front npm install

front-build: ## Build Next.js
	$(COMPOSE) exec front npm run build

front-lint: ## ESLint
	$(COMPOSE) exec front npm run lint

front-types: ## Vérification TypeScript
	$(COMPOSE) exec front npx tsc --noEmit

##@ 🗄️  Base de données
.PHONY: db-sh db-dump db-restore db-reset

db-sh: ## Shell psql
	$(COMPOSE) exec db psql -U $${POSTGRES_USER} -d $${POSTGRES_DB}

db-dump: ## Dump BDD → ./backups/
	@mkdir -p backups
	$(COMPOSE) exec db pg_dump -U $${POSTGRES_USER} $${POSTGRES_DB} \
		> backups/backup_$$(date +%Y%m%d_%H%M%S).sql

db-restore: ## Restaurer (make db-restore FILE=backups/x.sql)
	$(COMPOSE) exec -T db psql -U $${POSTGRES_USER} -d $${POSTGRES_DB} < $(FILE)

db-reset: ## ⚠️  Reset BDD (dev uniquement)
	$(COMPOSE) exec back php bin/console doctrine:database:drop --force --if-exists
	$(COMPOSE) exec back php bin/console doctrine:database:create
	$(COMPOSE) exec back php bin/console doctrine:migrations:migrate --no-interaction

##@ 🐇 RabbitMQ
.PHONY: rabbit-sh rabbit-purge

rabbit-sh: ## Shell RabbitMQ
	$(COMPOSE) exec rabbitmq bash

rabbit-purge: ## Purger la file (dev uniquement)
	$(COMPOSE) exec rabbitmq rabbitmqctl purge_queue myapp_queue

##@ 📊 Observabilité
.PHONY: obs-up obs-down grafana prometheus loki tempo

obs-up: ## Démarrer uniquement la stack d'observabilité
	$(COMPOSE) up -d prometheus loki promtail tempo grafana

obs-down: ## Arrêter la stack d'observabilité
	$(COMPOSE) stop prometheus loki promtail tempo grafana

grafana: ## Ouvrir Grafana dans le navigateur
	@echo "Grafana → http://localhost:$${GRAFANA_PORT:-4000}"
	@command -v xdg-open >/dev/null && xdg-open "http://localhost:$${GRAFANA_PORT:-4000}" || true
	@command -v open >/dev/null && open "http://localhost:$${GRAFANA_PORT:-4000}" || true

prometheus: ## Ouvrir Prometheus dans le navigateur
	@command -v xdg-open >/dev/null && xdg-open "http://localhost:$${PROMETHEUS_PORT:-9090}" || true
	@command -v open >/dev/null && open "http://localhost:$${PROMETHEUS_PORT:-9090}" || true

##@ 🚀 Production
.PHONY: prod-up prod-down prod-build prod-logs

prod-up: ## Démarrer en production
	$(COMPOSE_PROD) up -d

prod-down: ## Arrêter la prod
	$(COMPOSE_PROD) down

prod-build: ## Build production
	$(COMPOSE_PROD) build --no-cache

prod-logs: ## Logs prod
	$(COMPOSE_PROD) logs -f

##@ ℹ️  Aide
help:
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
