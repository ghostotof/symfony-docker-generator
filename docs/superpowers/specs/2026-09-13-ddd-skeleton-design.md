# Squelette DDD optionnel pour les projets générés

Date : 2026-09-13 — Branche : `feature/ddd-skeleton` — Statut : validé, en attente de plan

## 1. Objectif

Permettre à `create-symfony-project.sh` de produire, à la demande, un projet dont
le code applicatif est organisé selon une architecture DDD par contextes bornés,
côté backend (Symfony) et, le cas échéant, côté frontend (Vite + TypeScript).
Le découpage doit être **contraint par l'outillage** (Deptrac, ESLint boundaries),
pas seulement suggéré par des dossiers.

Indépendamment de DDD, PHPStan au niveau maximal devient un outil **systématique**
de tout projet généré.

## 2. Décisions arbitrées

| Sujet | Décision |
|---|---|
| Activation | Option `--ddd`. Sans elle, la sortie est inchangée (hors PHPStan). |
| Découpage | Par contexte borné : `src/Shared/` + `src/<Contexte>/{Domain,Application,Infrastructure,UI}`. |
| Exemple métier | Option séparée `--ddd-example` (implique `--ddd`) : contexte `Catalog` complet avec tests. |
| Garde-fous | Deptrac et mapping Doctrine XML dès `--ddd`. PHPStan niveau max systématique. ESLint boundaries avec `--frontend --ddd`. |
| Production du code | Dossier gabarit `docker/php/skeleton/` écrit par le générateur, monté en lecture seule dans le backend, copié par `init-symfony` après `symfony new`. |
| Frontend | TypeScript uniquement, agnostique du framework. Si le projet Vite est en JavaScript : avertissement, rien n'est appliqué. |

Approches rejetées : tout embarquer dans `init-symfony.sh` (heredocs imbriqués
sur ~30 fichiers) ; écrire dans `backend/` avant le build (les recettes Flex
écraseraient `services.yaml`, `doctrine.yaml`, `messenger.yaml`).

## 3. Interface du script

```
create-symfony-project <nom> [--frontend] [--ddd] [--ddd-example] [--path DIR] [--no-build]
```

- `--ddd` → `WITH_DDD=1`.
- `--ddd-example` → `WITH_DDD_EXAMPLE=1` et force `WITH_DDD=1` (documenté dans `--help`).
- Récapitulatif à l'écran : ligne « Architecture : DDD (+ exemple Catalog) » ou « standard ».
- `.env` : `BACKEND_DDD=0|1`, `BACKEND_DDD_EXAMPLE=0|1`, transmis au service backend
  par `environment:` comme `BACKEND_FLAVOR`.

### Versions résolues (chaîne complète : résolution → variable → récap → `.env` → `versions.lock`)

| Variable | Source | Condition | Repli |
|---|---|---|---|
| `PHPSTAN_VERSION` | Packagist `phpstan/phpstan` | toujours | 2.2.14 |
| `PHPSTAN_SYMFONY_VERSION` | Packagist `phpstan/phpstan-symfony` | toujours | 2.0.20 |
| `PHPSTAN_DOCTRINE_VERSION` | Packagist `phpstan/phpstan-doctrine` | toujours | 2.0.28 |
| `PHPSTAN_STRICT_VERSION` | Packagist `phpstan/phpstan-strict-rules` | toujours | 2.0.12 |
| `DEPTRAC_VERSION` | Packagist `deptrac/deptrac` (ex `qossmic/deptrac`, figé en 2.0) | `--ddd` | 4.7.1 |
| `ESLINT_BOUNDARIES_VERSION` | npm `eslint-plugin-boundaries` | `--frontend --ddd` | 7.2.0 |
| `ESLINT_VERSION` | npm `eslint` | `--frontend --ddd` | 10.10.0 |

Les variables conditionnelles ne sont écrites dans `.env` et `versions.lock` que
lorsqu'elles ont été résolues : une variable vide silencieuse est le bug type de
ce script.

## 4. Mécanisme d'application : le dossier gabarit

`docker/php/skeleton/` est **toujours** généré (il porte au minimum `phpstan.neon`).
Son contenu dépend des options. Il est monté dans le service backend :

```yaml
volumes:
  - ./backend:/var/www/backend
  - ./docker/php/skeleton:/opt/skeleton:ro
```

`init-symfony.sh` (exécuté une fois, en tant que `dev`) enchaîne :

1. `symfony new` (inchangé), déplacement dans `/var/www/backend`.
2. `composer require` selon le mode (inchangé), plus `symfony/test-pack` en mode
   `api` (le mode `full` l'a déjà via `--webapp`) pour que `make test` fonctionne
   partout.
3. `composer require --dev` PHPStan et ses trois extensions, aux versions figées.
4. Si `BACKEND_DDD=1` : `composer require --dev deptrac/deptrac:${DEPTRAC_VERSION}`
   et `symfony/uid` (identifiants des agrégats).
5. `cp -a /opt/skeleton/. /var/www/backend/` : le gabarit **écrase** les fichiers
   de même nom posés par les recettes (`config/services.yaml`, `config/packages/doctrine.yaml`,
   `config/packages/messenger.yaml`). L'ordre garantit que les recettes ne
   repassent pas derrière.
6. `.env.local` (inchangé).

La cible Makefile `init` et l'étape 6 du générateur n'ont rien à changer :
le montage est déclaré dans Compose.

Idempotence conservée : si `composer.json` existe, rien n'est fait.

## 5. Contenu du gabarit backend

### 5.1 Toujours

- `phpstan.neon` : niveau `max`, `paths: [src, tests]`, includes explicites de
  `vendor/phpstan/phpstan-symfony/extension.neon` + `rules.neon`,
  `vendor/phpstan/phpstan-doctrine/extension.neon` + `rules.neon`,
  `vendor/phpstan/phpstan-strict-rules/rules.neon`, `containerXmlPath` vers
  `var/cache/dev/App_KernelDevDebugContainer.xml`. Pas de `phpstan/extension-installer`
  (évite `allow-plugins`). Exclusions ajustées pour qu'un projet **fraîchement
  généré passe à zéro erreur** dans les deux modes ; le résultat est vérifié, pas
  supposé.

### 5.2 Avec `--ddd` (namespace `App\` conservé, PSR-4 `src/` inchangé)

```
src/Shared/
├── Domain/
│   ├── Aggregate/AggregateRoot.php        enregistre et restitue ses DomainEvent
│   ├── Event/DomainEvent.php              interface : occurredOn(), aggregateId()
│   ├── ValueObject/ValueObject.php        interface : equals()
│   └── Exception/DomainException.php      base abstraite des exceptions métier
├── Application/
│   ├── Command/{Command.php, CommandBus.php, CommandHandler.php}
│   ├── Query/{Query.php, QueryBus.php, QueryHandler.php}
│   └── Event/EventBus.php
└── Infrastructure/Messenger/
    ├── MessengerCommandBus.php            HandleTrait sur command.bus
    ├── MessengerQueryBus.php              HandleTrait sur query.bus
    └── MessengerEventBus.php              dispatch sur event.bus
```

Configuration écrasée :

- `config/packages/messenger.yaml` : `default_bus: command.bus` ; bus `command.bus`
  (middleware `doctrine_transaction`), `query.bus`, `event.bus`
  (`default_middleware: { allow_no_handlers: true }`) ; transport `async` AMQP
  conservé, routage vide par défaut.
- `config/services.yaml` : `App\` sur `../src/` avec exclusions :
  `../src/Kernel.php`, `../src/*/Domain/`, `../src/**/Application/**/*Command.php`,
  `../src/**/Application/**/*Query.php`, `../src/**/Application/**/DTO/`.
  Les interfaces de dépôt sont résolues par l'auto-alias de Symfony (une seule
  implémentation). Les handlers portent `#[AsMessageHandler(bus: '...')]`.
- `config/packages/doctrine.yaml` : réécrit d'après la recette courante (`dbal.url`,
  `orm.auto_generate_proxy_classes`, `naming_strategy underscore_number_aware`,
  blocs `when@test` / `when@prod`), avec `mappings` **XML** par contexte
  (`dir: %kernel.project_dir%/src/<Contexte>/Infrastructure/Doctrine/Mapping`,
  `prefix: App\<Contexte>\Domain`, `is_bundle: false`) et `dbal.types` pour les
  identifiants. **Risque assumé** : ce fichier doit être relu quand la recette
  `doctrine/doctrine-bundle` évolue ; un commentaire en tête le rappelle.
- `deptrac.yaml` : couches `Domain`, `Application`, `Infrastructure`, `UI` par
  regex de namespace (`App\\.*\\Domain\\.*`, etc.). Règles : Domain → rien ;
  Application → Domain ; Infrastructure → Domain, Application ; UI → Domain,
  Application. Les classes vendor ne sont pas collectées, donc Messenger/Doctrine
  restent autorisés dans Infrastructure et interdits dans Domain uniquement par
  construction (aucun `use` vendor n'y est généré). L'isolation entre contextes
  n'est pas imposée dans cette version (mentionné dans le README généré).
- `tests/Shared/Domain/AggregateRootTest.php` : enregistrement et vidage des événements.

### 5.3 Avec `--ddd-example` : contexte `Catalog`, agrégat `Product`

```
src/Catalog/
├── Domain/
│   ├── Model/Product.php                  agrégat : id, name, price, createdAt
│   ├── Model/ProductId.php                VO, Uuid v7 (symfony/uid), fromString(), generate()
│   ├── Model/ProductName.php              VO, 1..120 caractères, trim, sinon InvalidProductName
│   ├── Model/Price.php                    VO, amount int ≥ 0 en centimes + currency ISO 3 lettres
│   ├── Event/ProductCreated.php
│   ├── Exception/{ProductNotFound, InvalidProductName, InvalidPrice}.php
│   └── Repository/ProductRepository.php   interface : save(), get(ProductId), nextIdentity()
├── Application/
│   ├── Command/CreateProductCommand.php   (id string|null, name, amount, currency)
│   ├── Command/CreateProductHandler.php   crée, sauve, publie les événements
│   ├── Query/GetProductQuery.php
│   ├── Query/GetProductHandler.php        → ProductView
│   └── DTO/ProductView.php                readonly : id, name, amount, currency, createdAt
├── Infrastructure/
│   ├── Doctrine/Mapping/Product.orm.xml   Price en embeddable, id via type product_id
│   ├── Doctrine/Type/ProductIdType.php    StringType 36 → ProductId
│   ├── Doctrine/DoctrineProductRepository.php
│   └── InMemory/InMemoryProductRepository.php   utilisé par les tests
└── UI/Http/
    ├── mode full : ProductController.php  POST /api/products (201 + Location), GET /api/products/{id} (200 | 404)
    └── mode api  : Resource/ProductResource.php (#[ApiResource] sur DTO), State/ProductProvider.php, State/ProductProcessor.php
```

Tests PHPUnit (`tests/Catalog/`) : `ProductTest` (création, événement enregistré),
`ProductNameTest` et `PriceTest` (nominal, limites, exceptions), `CreateProductHandlerTest`
et `GetProductHandlerTest` avec le dépôt en mémoire (nominal, `ProductNotFound`).
Aucun test ne requiert la base de données.

Une migration n'est pas générée : `make db-migrate` existe déjà et le README
généré indique `make sh` puis `bin/console make:migration`.

## 6. Gabarit frontend (`--frontend --ddd`)

Appliqué **sur l'hôte** après `npm create vite`, depuis `docker/node/skeleton/`,
par le script `docker/node/apply-skeleton.sh` que l'étape 6 du générateur et la
cible `front-init` appellent tous deux (une seule implémentation) :

- Condition : `frontend/tsconfig.json` existe. Sinon `warn` et sortie sans rien
  copier, avec la commande à relancer une fois le projet passé en TypeScript.
- `src/domain/README.md`, `src/application/README.md`, `src/infrastructure/README.md`,
  `src/ui/README.md` : rôle de chaque couche et règle de dépendance.
- `eslint.boundaries.config.js` (flat config, séparée de celle du gabarit Vite pour
  ne pas la modifier) : éléments `domain`, `application`, `infrastructure`, `ui`
  par dossier ; règles `boundaries/element-types` identiques au backend.
- `package.json` : script `lint:arch` = `eslint -c eslint.boundaries.config.js src`.
  Ajout par `npm pkg set` (pas d'édition manuelle du JSON).
- `npm install -D eslint@X eslint-plugin-boundaries@Y` aux versions figées.
- Avec `--ddd-example` : `src/domain/product/{Product.ts, ProductId.ts, Price.ts, ProductRepository.ts}`,
  `src/application/product/{createProduct.ts, getProduct.ts}`,
  `src/infrastructure/http/HttpProductRepository.ts` (fetch sur `import.meta.env.VITE_API_URL`,
  routes du backend), sans aucun fichier dans `src/ui/` (le framework est inconnu).

## 7. Makefile généré

| Cible | Condition | Commande |
|---|---|---|
| `phpstan` | toujours | `$(DC) exec backend vendor/bin/phpstan analyse` |
| `test` | toujours | `$(DC) exec backend vendor/bin/phpunit` |
| `deptrac` | `--ddd` | `$(DC) exec backend vendor/bin/deptrac analyse` |
| `front-arch` | `--frontend --ddd` | `$(DC) exec frontend npm run lint:arch` |

Toutes < 20 caractères : le gabarit `%-20s` de `make help` reste valable.

## 8. Documentation

- `README.md` du générateur : section « Architecture DDD (`--ddd`) » et ligne
  sur PHPStan systématique ; tableau des options mis à jour.
- README généré : section « Architecture » décrivant les couches, les bus, la
  commande pour ajouter un contexte (copier `Catalog`, ajouter le mapping dans
  `doctrine.yaml`), et les cibles `phpstan`/`deptrac`/`test`/`front-arch`.
- `.claude/CLAUDE.md` : trois invariants — le gabarit est appliqué à l'init dans
  le conteneur, jamais avant le build ; le front DDD est TypeScript uniquement ;
  PHPStan est systématique, DDD ne l'est pas.

## 9. Vérification

1. `bash -n`, puis génération `--no-build` dans quatre combinaisons :
   défaut, `--ddd`, `--ddd-example`, `--frontend --ddd-example`. Contrôles :
   `make help` aligné ; sans `--ddd`, `docker/php/skeleton/` ne contient que
   `phpstan.neon`, aucune cible `deptrac`/`front-arch`, aucun `docker/node/skeleton/`.
2. Build réel sur cette machine, dans `~/dev` (ext4) :
   - `--ddd-example` mode full : `make init`, `make phpstan`, `make deptrac`,
     `make test` à zéro erreur ; `make db-migrate` après `make:migration` ;
     `curl` POST puis GET sur `/api/products`.
   - `--frontend --ddd-example` mode api : idem côté backend avec API Platform
     (`GET /api/products/{id}` via Provider, `POST` via Processor) ; côté front,
     `npm create vite -- --template vanilla-ts` en non-interactif puis `make front-arch`.
   - Mode défaut (sans `--ddd`) : `make phpstan` passe sur le squelette Symfony nu.
3. Deptrac doit **échouer** sur une violation introduite volontairement
   (un `use Doctrine\...` dans `Domain`) : preuve que le garde-fou mord.

## 10. Hors périmètre

- Isolation entre contextes bornés dans Deptrac.
- Génération de migrations, fixtures, ou d'un `objectManagerLoader` pour phpstan-doctrine.
- Squelette `src/ui/` côté front (dépend du framework choisi en interactif).
- Fourniture d'un squelette utilisateur externe (`--skeleton-back`), écartée à ce stade.
