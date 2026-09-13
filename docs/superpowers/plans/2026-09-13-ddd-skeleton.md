# Squelette DDD optionnel — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter à `create-symfony-project.sh` les options `--ddd` et `--ddd-example` qui produisent un projet Symfony (et Vite) organisé en contextes bornés, contraint par Deptrac et ESLint boundaries, et rendre PHPStan niveau max systématique.

**Architecture:** Le générateur écrit un dossier gabarit `docker/php/skeleton/` (toujours présent, contenu variable selon les options), monté en lecture seule dans le conteneur backend. `init-symfony` le copie sur le projet après `symfony new` et les `composer require`, pour que ses fichiers aient le dernier mot sur les recettes Flex. Côté front, un script hôte `docker/node/apply-skeleton.sh` copie `docker/node/skeleton/` après `npm create vite`.

**Tech Stack:** bash (heredocs), Symfony 7.x, Messenger (3 bus), Doctrine ORM 3 (mapping XML), API Platform 4 (mode api), PHPStan 2 + strict-rules, Deptrac 4, PHPUnit, Vite + TypeScript, ESLint 10 flat config + eslint-plugin-boundaries.

**Spec:** `docs/superpowers/specs/2026-09-13-ddd-skeleton-design.md`

## Global Constraints

- Un seul fichier de logique : tout le code généré vit dans `create-symfony-project.sh` sous forme de heredocs.
- Heredoc **quoté** (`<<'EOF'`) pour tout fichier contenant `$` destiné à PHP, Docker, Compose, make ou JS. Heredoc **non quoté** uniquement pour `.env`, `versions.lock` et le README généré.
- Recettes du Makefile généré indentées par des **tabulations**. Aucune cible > 20 caractères (`%-20s`).
- Le script est en `set -Eeuo pipefail` : tout `grep` en pipeline est protégé par `{ grep ... || true; }`.
- Chaîne de versions complète pour chaque dépendance : résolution → variable → récapitulatif → `.env` → `versions.lock` (→ `environment:` Compose si consommée par `init-symfony`).
- Sans `--ddd`, la sortie est identique à aujourd'hui **sauf** : `docker/php/skeleton/phpstan.neon`, le montage `/opt/skeleton`, les variables `PHPSTAN_*` et `BACKEND_DDD*`, les cibles `phpstan` et `test`, et `symfony/test-pack` en mode api.
- Commentaires et messages en français ; les commentaires disent le *pourquoi*.
- Fallbacks des versions (au 2026-09-13) : phpstan 2.2.14, phpstan-symfony 2.0.20, phpstan-doctrine 2.0.28, phpstan-strict-rules 2.0.12, deptrac/deptrac 4.7.1, eslint 10.10.0, eslint-plugin-boundaries 7.2.0, @typescript-eslint/parser 8.70.0.
- Tests réels dans `~/dev` (ext4), jamais sous `~/projects` (NTFS). Un seul projet démarré à la fois (ports 8080/5432/5672/15672/5173). Toujours finir par `docker compose down -v`.
- Commits sur `feature/ddd-skeleton`, message en français, attribution `Co-Authored-By` + `Claude-Session` comme les commits précédents.

---

## Structure des fichiers

Un seul fichier modifié : `create-symfony-project.sh`. Les numéros de ligne sont ceux de `HEAD` (`0eb4803`) ; ils glissent au fil des tâches, repérer par le contenu cité.

| Zone du script | Rôle | Tâches |
|---|---|---|
| En-tête `# Options :` (l. 33-43) | aide `--help` | 1 |
| Parsing (l. 73-92) | `WITH_DDD`, `WITH_DDD_EXAMPLE` | 1 |
| Résolution (l. 252-258) + récapitulatif (l. 260-277) | versions PHPStan/Deptrac/ESLint | 1 |
| `.env` (l. 296-348) + `versions.lock` (l. 351-372) | figeage | 1 |
| `mkdir -p` (l. 282-283) | dossiers gabarit | 2, 6 |
| 5.5 `init-symfony.sh` (l. 835-906) | test-pack, PHPStan, Deptrac, copie du gabarit | 2 |
| **nouvelle** 5.5b `docker/php/skeleton/` | phpstan.neon (toujours), Shared, config, Catalog | 2, 3, 4, 5 |
| 5.7 Compose backend (l. 988-1000) | `environment:` + montage `/opt/skeleton` | 2 |
| **nouvelle** 5.8d `docker/node/skeleton/` + `apply-skeleton.sh` | front DDD | 6 |
| 5.9 Makefile (l. 1310-1414) | `phpstan`, `test`, `deptrac`, `front-arch`, `front-init` | 2, 3, 6 |
| 5.10 README généré (l. 1438-1527) | section Architecture | 7 |
| Étape 6 build (l. 1536-1552) | appel `apply-skeleton.sh` | 6 |
| `README.md`, `.claude/CLAUDE.md` | doc du générateur, invariants | 7 |

Arborescence du gabarit backend (`docker/php/skeleton/`), reflétant `backend/` :

```
phpstan.neon                                   (toujours)
deptrac.yaml                                   (--ddd)
config/services.yaml                           (--ddd, ÉCRASE la recette)
config/packages/messenger_ddd.yaml             (--ddd, FUSIONNÉ avec la recette)
config/packages/doctrine_ddd.yaml              (--ddd, fusionné : options ORM communes)
config/packages/doctrine_catalog.yaml          (--ddd-example, fusionné : mapping + type)
config/routes/catalog.yaml                     (--ddd-example, mode full)
config/packages/api_platform_ddd.yaml          (--ddd-example, mode api)
src/Shared/...                                 (--ddd)
src/Catalog/...                                (--ddd-example)
tests/Shared/..., tests/Catalog/...            (--ddd / --ddd-example)
```

---

### Task 0 : Aligner le spec sur les choix de conception affinés

Pendant la rédaction du plan, quatre choix du spec ont été améliorés. On les grave dans le spec **avant** de coder, pour que spec et plan racontent la même histoire.

**Files:**
- Modify: `docs/superpowers/specs/2026-09-13-ddd-skeleton-design.md`

- [ ] **Step 1 : Remplacer la réécriture de `doctrine.yaml` et `messenger.yaml` par des fichiers additionnels**

Dans la section 5.2, remplacer le point `config/packages/messenger.yaml : ...` par :

```
- `config/packages/messenger_ddd.yaml` (fichier **additionnel**, fusionné par le
  composant Config avec la recette) : `default_bus: command.bus` ; bus `command.bus`
  (middleware `doctrine_transaction`), `query.bus`, `event.bus`
  (`default_middleware: { allow_no_handlers: true }`). Les transports et le routage
  de la recette sont conservés tels quels.
```

Remplacer le point `config/packages/doctrine.yaml : réécrit ...` par :

```
- `config/packages/doctrine_ddd.yaml` (additionnel, fusionné) : `validate_xml_mapping: true`.
  Chaque contexte apporte son propre fichier `doctrine_<contexte>.yaml` avec son
  mapping XML (`type: xml`, `dir`, `prefix`, `is_bundle: false`) et ses `dbal.types`.
  Le `doctrine.yaml` de la recette n'est **pas** touché : le risque de divergence
  avec la recette disparaît.
```

Dans la section 4, étape 5, remplacer la parenthèse des fichiers écrasés par `(config/services.yaml)`.

- [ ] **Step 2 : Enregistrer les handlers sans attribut vendor**

Dans la section 5.2, point `config/services.yaml`, remplacer la dernière phrase « Les handlers portent `#[AsMessageHandler(bus: '...')]`. » par :

```
  Les handlers n'importent rien de Messenger : ils implémentent les interfaces
  marqueurs `CommandHandler` / `QueryHandler` de `Shared\Application`, et
  `services.yaml` les tague via `_instanceof` (`messenger.message_handler`, option
  `bus`). Le type de message est déduit du paramètre de `__invoke`. La couche
  Application reste ainsi sans dépendance vendor, ce que Deptrac vérifie.
```

- [ ] **Step 3 : Ajouter la couche `Vendor` à Deptrac**

Dans la section 5.2, point `deptrac.yaml`, remplacer tout le point par :

```
- `deptrac.yaml` : couches `Domain`, `Application`, `Infrastructure`, `UI` par
  regex de namespace (`#^App\\[^\\]+\\Domain\\#`, etc.) plus une couche `Vendor`
  (`#^(Doctrine|Symfony|ApiPlatform|Psr)\\#`). Règles : Domain → rien ;
  Application → Domain ; Infrastructure → Domain, Application, Vendor ;
  UI → Domain, Application, Vendor. Un `use Doctrine\...` dans le domaine est donc
  une violation détectée, pas seulement une convention. L'isolation entre
  contextes n'est pas imposée dans cette version.
```

- [ ] **Step 4 : Identité générée par l'UI, exceptions complètes, parser TypeScript**

Section 5.3 : dans `Repository/ProductRepository.php`, remplacer `save(), get(ProductId), nextIdentity()` par `save(Product), get(ProductId)`. Ajouter `InvalidProductId` à la liste des exceptions. Dans `CreateProductCommand.php`, remplacer `(id string|null, ...)` par `(id string, name, amount, currency) — l'UI génère l'UUID v7 (symfony/uid) pour pouvoir renvoyer Location`. Ajouter au bloc `Domain/Model/Product.php` : `changePrice(Price)`.

Section 3, tableau des versions : ajouter la ligne `| TS_ESLINT_PARSER_VERSION | npm @typescript-eslint/parser | --frontend --ddd | 8.70.0 |` et remplacer la phrase sur les variables conditionnelles par :

```
Les variables conditionnelles sont toujours écrites dans `.env` et `versions.lock`
(vides si la condition est fausse), exactement comme `API_PLATFORM_VERSION` sans
`--frontend` : Compose n'avertit ainsi jamais sur une variable absente.
```

Section 6 : ajouter `@typescript-eslint/parser` à la ligne `npm install -D`. Section 9.3 : remplacer « un `use Doctrine\...` dans `Domain` » par « une propriété typée `Doctrine\ORM\EntityManagerInterface` ajoutée dans `AggregateRoot` ».

- [ ] **Step 5 : Commit**

```bash
git add docs/superpowers/specs/2026-09-13-ddd-skeleton-design.md
git commit -m "docs(spec): fichiers Doctrine/Messenger additionnels, handlers sans attribut, couche Vendor Deptrac"
```

---

### Task 1 : Options `--ddd` / `--ddd-example` et chaîne de versions

**Files:**
- Modify: `create-symfony-project.sh` (en-tête l. 33-43, parsing l. 73-92, résolution l. 252-258, récapitulatif l. 260-277, `.env` l. 296-348, `versions.lock` l. 351-372)

**Interfaces:**
- Produces : variables bash `WITH_DDD` (0|1), `WITH_DDD_EXAMPLE` (0|1), `PHPSTAN_VERSION`, `PHPSTAN_SYMFONY_VERSION`, `PHPSTAN_DOCTRINE_VERSION`, `PHPSTAN_STRICT_VERSION`, `DEPTRAC_VERSION`, `ESLINT_VERSION`, `ESLINT_BOUNDARIES_VERSION`, `TS_ESLINT_PARSER_VERSION` ; clés `.env` de même nom plus `BACKEND_DDD`, `BACKEND_DDD_EXAMPLE`.

- [ ] **Step 1 : Aide en en-tête**

Après le bloc `--frontend` (l. 34-38), insérer :

```bash
#    --ddd             Organise le code backend (et frontend avec --frontend) en
#                      architecture DDD par contextes bornés : src/Shared/, bus
#                      Messenger command/query/event, mapping Doctrine XML,
#                      Deptrac. Sans cette option : squelette Symfony standard.
#    --ddd-example     Ajoute un contexte borné d'exemple complet (Catalog,
#                      agrégat Product, tests). Implique --ddd.
```

- [ ] **Step 2 : Variables et parsing**

Après `DO_BUILD=1 ...` (l. 76), ajouter :

```bash
WITH_DDD=0           # 1 = squelette DDD (Shared, bus, mapping XML, Deptrac)
WITH_DDD_EXAMPLE=0   # 1 = contexte d'exemple Catalog (implique WITH_DDD)
```

Dans le `case` (l. 81-84), après la ligne `--frontend)`, ajouter :

```bash
    --ddd)         WITH_DDD=1; shift ;;
    --ddd-example) WITH_DDD_EXAMPLE=1; WITH_DDD=1; shift ;;
```

Mettre à jour le message d'usage (l. 95) : `Usage : $(basename "$0") <nom-du-projet> [--frontend] [--ddd] [--ddd-example]`.

- [ ] **Step 3 : Résolution des versions**

Après le bloc `if (( WITH_FRONTEND )); then ... CREATE_VITE_VERSION ... fi` (l. 255-258), insérer :

```bash
# --- Qualité : PHPStan est SYSTÉMATIQUE (avec ou sans --ddd) -----------------
# Pas de phpstan/extension-installer : les extensions sont incluses explicitement
# dans phpstan.neon, ce qui évite d'autoriser un plugin Composer à l'init.
PHPSTAN_VERSION="$(resolve_packagist "phpstan" "phpstan/phpstan" "2.2.14")"
PHPSTAN_SYMFONY_VERSION="$(resolve_packagist "phpstan-symfony" "phpstan/phpstan-symfony" "2.0.20")"
PHPSTAN_DOCTRINE_VERSION="$(resolve_packagist "phpstan-doctrine" "phpstan/phpstan-doctrine" "2.0.28")"
PHPSTAN_STRICT_VERSION="$(resolve_packagist "phpstan-strict-rules" "phpstan/phpstan-strict-rules" "2.0.12")"

# --- Architecture DDD (uniquement avec --ddd) --------------------------------
# Deptrac a changé de paquet : qossmic/deptrac est figé en 2.0, la lignée active
# est deptrac/deptrac (4.x). Ne pas « corriger » vers qossmic.
DEPTRAC_VERSION=""
ESLINT_VERSION=""
ESLINT_BOUNDARIES_VERSION=""
TS_ESLINT_PARSER_VERSION=""
if (( WITH_DDD )); then
  DEPTRAC_VERSION="$(resolve_packagist "deptrac" "deptrac/deptrac" "4.7.1")"
  if (( WITH_FRONTEND )); then
    # ESLint est installé par nous (le gabarit vanilla-ts de Vite n'en a pas) ;
    # le parser TypeScript est indispensable pour analyser des .ts.
    ESLINT_VERSION="$(resolve_npm "eslint" "eslint" "10.10.0")"
    ESLINT_BOUNDARIES_VERSION="$(resolve_npm "eslint-plugin-boundaries" "eslint-plugin-boundaries" "7.2.0")"
    TS_ESLINT_PARSER_VERSION="$(resolve_npm "@typescript-eslint/parser" "@typescript-eslint/parser" "8.70.0")"
  fi
fi
```

- [ ] **Step 4 : Récapitulatif à l'écran**

Après le bloc `(( WITH_FRONTEND )) && { ... }` (l. 272-276) et avant `printf '\n'`, insérer :

```bash
printf '  phpstan        : %s  %s(symfony %s, doctrine %s, strict-rules %s)%s\n' \
       "$PHPSTAN_VERSION" "$C_DIM" "$PHPSTAN_SYMFONY_VERSION" "$PHPSTAN_DOCTRINE_VERSION" \
       "$PHPSTAN_STRICT_VERSION" "$C_RESET"
(( WITH_DDD )) && printf '  deptrac        : %s\n' "$DEPTRAC_VERSION"
(( WITH_DDD && WITH_FRONTEND )) && {
printf '  eslint         : %s  %s(boundaries %s, ts-parser %s)%s\n' \
       "$ESLINT_VERSION" "$C_DIM" "$ESLINT_BOUNDARIES_VERSION" "$TS_ESLINT_PARSER_VERSION" "$C_RESET"
}
printf '  architecture   : %s\n' \
       "$( if (( WITH_DDD )); then printf 'DDD'; (( WITH_DDD_EXAMPLE )) && printf ' + exemple Catalog'; else printf 'standard'; fi )"
```

- [ ] **Step 5 : `.env`**

Après la ligne `CREATE_VITE_VERSION=${CREATE_VITE_VERSION}` (l. 326), insérer :

```bash

# --- Qualité et architecture (figées) ----------------------------------------
# PHPStan est installé dans TOUT projet généré (niveau max + strict-rules).
PHPSTAN_VERSION=${PHPSTAN_VERSION}
PHPSTAN_SYMFONY_VERSION=${PHPSTAN_SYMFONY_VERSION}
PHPSTAN_DOCTRINE_VERSION=${PHPSTAN_DOCTRINE_VERSION}
PHPSTAN_STRICT_VERSION=${PHPSTAN_STRICT_VERSION}
# Vides sans --ddd (même logique qu'API_PLATFORM_VERSION sans --frontend).
DEPTRAC_VERSION=${DEPTRAC_VERSION}
ESLINT_VERSION=${ESLINT_VERSION}
ESLINT_BOUNDARIES_VERSION=${ESLINT_BOUNDARIES_VERSION}
TS_ESLINT_PARSER_VERSION=${TS_ESLINT_PARSER_VERSION}
```

Après la ligne `BACKEND_FLAVOR=$( ... )` (l. 331), insérer :

```bash

# --- Architecture du backend -------------------------------------------------
# 1 = squelette DDD (src/Shared, bus Messenger, mapping XML, Deptrac) appliqué
#     par init-symfony ; 0 = squelette Symfony standard.
BACKEND_DDD=${WITH_DDD}
# 1 = contexte borné d'exemple Catalog (implique BACKEND_DDD=1).
BACKEND_DDD_EXAMPLE=${WITH_DDD_EXAMPLE}
```

- [ ] **Step 6 : `versions.lock`**

Après `create-vite=${CREATE_VITE_VERSION}` (l. 371), insérer :

```bash
phpstan=${PHPSTAN_VERSION}
phpstan-symfony=${PHPSTAN_SYMFONY_VERSION}
phpstan-doctrine=${PHPSTAN_DOCTRINE_VERSION}
phpstan-strict-rules=${PHPSTAN_STRICT_VERSION}
# Vides sans --ddd.
deptrac=${DEPTRAC_VERSION}
eslint=${ESLINT_VERSION}
eslint-plugin-boundaries=${ESLINT_BOUNDARIES_VERSION}
typescript-eslint-parser=${TS_ESLINT_PARSER_VERSION}
```

- [ ] **Step 7 : Vérifier**

```bash
bash -n create-symfony-project.sh
S=/tmp/claude-1000/-media-shared-data-projects-symfony-docker-generator/516574fe-7cc9-42f9-a675-89900343752b/scratchpad
rm -rf "$S/t1" && mkdir -p "$S/t1" && cd "$S/t1"
G=/media/shared_data/projects/symfony-docker-generator/create-symfony-project.sh
bash "$G" --help | grep -c -- '--ddd'                      # attendu : 2
bash "$G" p --no-build >/dev/null
grep -E '^(PHPSTAN_VERSION|BACKEND_DDD|BACKEND_DDD_EXAMPLE|DEPTRAC_VERSION)=' p/.env
#   attendu : PHPSTAN_VERSION=2.x.y ; BACKEND_DDD=0 ; BACKEND_DDD_EXAMPLE=0 ; DEPTRAC_VERSION= (vide)
bash "$G" q --ddd-example --no-build | grep -E 'architecture|deptrac'
#   attendu : "architecture   : DDD + exemple Catalog" et une ligne deptrac
grep -E '^(BACKEND_DDD|BACKEND_DDD_EXAMPLE|DEPTRAC_VERSION)=' q/.env  # 1, 1, 4.x.y
bash "$G" r --ddd --frontend --no-build | grep -E 'eslint'          # une ligne eslint
grep -c '^eslint' r/versions.lock                                    # attendu : 2
```

Toutes les générations doivent se terminer par « Projet ... prêt ».

- [ ] **Step 8 : Commit**

```bash
git add create-symfony-project.sh
git commit -m "feat: options --ddd et --ddd-example, versions PHPStan/Deptrac/ESLint figées"
```

---

### Task 2 : Gabarit toujours monté, PHPStan systématique, cibles `phpstan` et `test`

À la fin de cette tâche, un projet généré **sans** `--ddd` possède PHPStan niveau max qui passe à zéro erreur, et `make test` fonctionne dans les deux modes.

**Files:**
- Modify: `create-symfony-project.sh` — `mkdir -p` (l. 282), section 5.5 `init-symfony.sh` (l. 839-906), section 5.7 service backend (l. 988-1000), section 5.9 Makefile (l. 1315, 1339-1346)
- Create (dans le script) : nouvelle section `5.5b docker/php/skeleton` juste après la section 5.5

**Interfaces:**
- Consumes : `WITH_DDD`, variables `PHPSTAN_*`, `DEPTRAC_VERSION` (Task 1).
- Produces : dossier `docker/php/skeleton/` (racine du gabarit, monté sur `/opt/skeleton`) ; variables d'environnement `BACKEND_DDD`, `BACKEND_DDD_EXAMPLE`, `PHPSTAN_*`, `DEPTRAC_VERSION` disponibles dans `init-symfony` ; cibles `phpstan`, `test`.

- [ ] **Step 1 : Créer le dossier gabarit**

Ligne 282, remplacer :

```bash
mkdir -p "$PROJECT_DIR"/{backend,docker/php,docker/nginx}
```

par :

```bash
# docker/php/skeleton : gabarit appliqué par init-symfony APRÈS `symfony new`.
# Toujours présent (il porte phpstan.neon) ; --ddd et --ddd-example l'enrichissent.
mkdir -p "$PROJECT_DIR"/{backend,docker/php/skeleton,docker/nginx}
```

- [ ] **Step 2 : Service backend Compose — variables et montage**

Dans le bloc `environment:` du service `backend` (l. 988-997), après `BACKEND_FLAVOR: ${BACKEND_FLAVOR}`, ajouter :

```yaml
      BACKEND_DDD: ${BACKEND_DDD}
      BACKEND_DDD_EXAMPLE: ${BACKEND_DDD_EXAMPLE}
      PHPSTAN_VERSION: ${PHPSTAN_VERSION}
      PHPSTAN_SYMFONY_VERSION: ${PHPSTAN_SYMFONY_VERSION}
      PHPSTAN_DOCTRINE_VERSION: ${PHPSTAN_DOCTRINE_VERSION}
      PHPSTAN_STRICT_VERSION: ${PHPSTAN_STRICT_VERSION}
      DEPTRAC_VERSION: ${DEPTRAC_VERSION}
```

Dans `volumes:` (l. 998-1000), après `- ./backend:/var/www/backend`, ajouter :

```yaml
      # Gabarit de code appliqué une fois par init-symfony (voir docker/php/skeleton).
      # Lecture seule : le conteneur n'a aucune raison d'y écrire.
      - ./docker/php/skeleton:/opt/skeleton:ro
```

- [ ] **Step 3 : `init-symfony.sh` — test-pack, PHPStan, Deptrac, copie du gabarit**

Après `: "${BACKEND_FLAVOR:=full}"` (l. 856), ajouter :

```bash
: "${BACKEND_DDD:=0}"
: "${PHPSTAN_VERSION:?PHPSTAN_VERSION doit être défini}"
: "${PHPSTAN_SYMFONY_VERSION:?}"
: "${PHPSTAN_DOCTRINE_VERSION:?}"
: "${PHPSTAN_STRICT_VERSION:?}"
```

Dans la branche `if [[ "$BACKEND_FLAVOR" == "api" ]]; then` (l. 879-890), après `composer require --no-interaction --dev symfony/maker-bundle`, ajouter :

```bash
  # Le mode full l'obtient via --webapp ; sans lui, `make test` n'aurait rien à lancer.
  composer require --no-interaction --dev symfony/test-pack
```

Après le `fi` de ce bloc (l. 894) et avant le commentaire « Configuration locale », insérer :

```bash
echo "→ Installation de PHPStan ${PHPSTAN_VERSION} (niveau max, strict-rules, extensions Symfony et Doctrine)"
# Versions exactes : la reproductibilité du projet ne doit pas dépendre du jour
# où l'on lance `make init`.
composer require --no-interaction --dev \
  "phpstan/phpstan:${PHPSTAN_VERSION}" \
  "phpstan/phpstan-symfony:${PHPSTAN_SYMFONY_VERSION}" \
  "phpstan/phpstan-doctrine:${PHPSTAN_DOCTRINE_VERSION}" \
  "phpstan/phpstan-strict-rules:${PHPSTAN_STRICT_VERSION}"

if [[ "$BACKEND_DDD" == "1" ]]; then
  : "${DEPTRAC_VERSION:?DEPTRAC_VERSION doit être défini quand BACKEND_DDD=1}"
  echo "→ Architecture DDD : Deptrac ${DEPTRAC_VERSION} + symfony/uid"
  composer require --no-interaction --dev "deptrac/deptrac:${DEPTRAC_VERSION}"
  # Identifiants UUID v7 des agrégats, générés côté UI et Infrastructure.
  composer require --no-interaction symfony/uid
fi

# Application du gabarit. Copié APRÈS toutes les recettes Flex : ses fichiers
# (services.yaml, phpstan.neon, deptrac.yaml…) doivent avoir le dernier mot.
# `cp -R` et non `-a` : l'utilisateur dev ne peut pas préserver un propriétaire.
if [[ -d /opt/skeleton ]]; then
  echo "→ Application du gabarit de code (/opt/skeleton)"
  cp -R /opt/skeleton/. "$APP_DIR"/
  # Le conteneur XML du kernel est requis par phpstan-symfony : on le régénère
  # maintenant que la configuration finale est en place.
  php bin/console cache:clear --no-warmup
  php bin/console cache:warmup
fi
```

- [ ] **Step 4 : Nouvelle section 5.5b — `phpstan.neon`**

Après le `EOF` fermant `init-symfony.sh` (l. 906) et avant `# 5.6 docker/nginx/default.conf`, insérer :

```bash
# -----------------------------------------------------------------------------
# 5.5b docker/php/skeleton — gabarit de code appliqué par init-symfony
# -----------------------------------------------------------------------------
# Ce dossier reflète la racine de backend/. init-symfony le copie APRÈS les
# recettes Flex : tout fichier présent ici écrase son homonyme du projet.
# Toujours présent (phpstan.neon) ; --ddd et --ddd-example l'enrichissent (5.5c, 5.5d).

# PHPStan : niveau max + strict-rules, extensions incluses explicitement (pas de
# phpstan/extension-installer, qui exigerait un allow-plugins à l'init).
cat > docker/php/skeleton/phpstan.neon <<'EOF'
# Analyse statique — niveau maximal, règles strictes.
# Lancer : make phpstan
includes:
    - vendor/phpstan/phpstan-strict-rules/rules.neon
    - vendor/phpstan/phpstan-symfony/extension.neon
    - vendor/phpstan/phpstan-symfony/rules.neon
    - vendor/phpstan/phpstan-doctrine/extension.neon
    - vendor/phpstan/phpstan-doctrine/rules.neon

parameters:
    level: max
    paths:
        - src
        - tests
    excludePaths:
        # Fichier de la recette symfony/phpunit-bridge : hors de notre contrôle.
        - tests/bootstrap.php
    tmpDir: var/cache/phpstan
    symfony:
        # Produit par cache:warmup en dev ; donne à PHPStan les types réels des services.
        containerXmlPath: var/cache/dev/App_KernelDevDebugContainer.xml
EOF
```

- [ ] **Step 5 : Makefile — cibles `phpstan` et `test`**

Ligne 1315, remplacer la ligne `.PHONY:` par :

```make
.PHONY: help build up down restart logs sh sh-front init db-migrate consume phpstan test deptrac front-arch build-prod build-preprod front-init build-front-prod build-front-preprod
```

Après la cible `consume:` (l. 1345-1346), ajouter :

```make

# --- Qualité -------------------------------------------------------------------
phpstan: ## Analyse statique PHPStan (niveau max, strict)
	$(DC) exec --user dev backend vendor/bin/phpstan analyse --memory-limit=1G

test: ## Lance les tests PHPUnit du backend
	$(DC) exec --user dev backend vendor/bin/phpunit
```

(Recettes indentées par une **tabulation**.)

- [ ] **Step 6 : Vérifier la génération**

```bash
bash -n create-symfony-project.sh
S=/tmp/claude-1000/-media-shared-data-projects-symfony-docker-generator/516574fe-7cc9-42f9-a675-89900343752b/scratchpad
rm -rf "$S/t2" && mkdir -p "$S/t2" && cd "$S/t2"
G=/media/shared_data/projects/symfony-docker-generator/create-symfony-project.sh
bash "$G" p --no-build >/dev/null && ls p/docker/php/skeleton        # attendu : phpstan.neon seul
grep -n 'opt/skeleton' p/docker-compose.yml                          # 1 ligne de montage
grep -c 'phpstan' p/docker/php/init-symfony.sh                       # ≥ 3
(cd p && make help | grep -E 'phpstan|test')                          # 2 cibles alignées
grep -P '^\t' p/Makefile | grep -c 'phpstan\|phpunit'                 # 2 recettes tabulées
```

- [ ] **Step 7 : Vérifier par un build réel (mode défaut)**

```bash
cd ~/dev && rm -rf ddd-t2 && bash "$G" ddd-t2 --no-build >/dev/null && cd ddd-t2
make build 2>&1 | tail -3
make up
make init 2>&1 | tail -15          # attendu : "→ Installation de PHPStan", "→ Application du gabarit", "✔ Projet Symfony initialisé."
ls backend/phpstan.neon            # présent
make phpstan 2>&1 | tail -5        # attendu : "[OK] No errors"
make test 2>&1 | tail -5           # attendu : PHPUnit démarre ; "No tests executed!" est acceptable en mode défaut (aucun test généré)
docker compose down -v
```

Si PHPStan signale des erreurs dans des fichiers produits par les recettes (hors `src/Kernel.php`), les ajouter à `excludePaths` de `phpstan.neon` **avec un commentaire disant pourquoi**, et relancer jusqu'à zéro erreur. Le projet nu doit passer : c'est la promesse faite à l'utilisateur.

Répéter ensuite en mode api (`--frontend --no-build`, sans `make front-init`) : `make build && make up && make init && make phpstan && make test && docker compose down -v`. Attendu identique, plus `symfony/test-pack` dans `backend/composer.json`.

- [ ] **Step 8 : Commit**

```bash
git add create-symfony-project.sh
git commit -m "feat: gabarit docker/php/skeleton monté à l'init, PHPStan niveau max systématique, cibles phpstan et test"
```

---

### Task 3 : Fondations DDD (`--ddd`) — `Shared`, bus Messenger, `services.yaml`, Deptrac

À la fin de cette tâche, `--ddd` produit un projet avec `src/Shared/`, trois bus, un `services.yaml` DDD, Deptrac configuré, un test, et `make phpstan deptrac test` passe.

**Files:**
- Modify: `create-symfony-project.sh` — nouvelle section `5.5c` après 5.5b ; Makefile (cible `deptrac`)

**Interfaces:**
- Produces (namespaces PHP, utilisés par Task 4 et 5) :
  - `App\Shared\Domain\Aggregate\AggregateRoot` : `protected function record(DomainEvent $event): void`, `public function pullDomainEvents(): array` (`list<DomainEvent>`)
  - `App\Shared\Domain\Event\DomainEvent` : `aggregateId(): string`, `occurredOn(): \DateTimeImmutable`
  - `App\Shared\Domain\ValueObject\ValueObject` : `equals(ValueObject $other): bool`
  - `App\Shared\Domain\Exception\DomainException` (abstraite, étend `\DomainException`)
  - `App\Shared\Application\Command\{Command, CommandHandler}` (marqueurs), `CommandBus::dispatch(Command $command): void`
  - `App\Shared\Application\Query\{Query, QueryHandler}` (marqueurs), `QueryBus::ask(Query $query): mixed`
  - `App\Shared\Application\Event\EventBus::publish(DomainEvent ...$events): void`
  - Bus Messenger nommés `command.bus`, `query.bus`, `event.bus` ; tags via `_instanceof` sur `CommandHandler` / `QueryHandler`.

- [ ] **Step 1 : Ouvrir la section 5.5c et écrire `Shared\Domain`**

Après le `EOF` de `phpstan.neon` (fin de 5.5b), insérer :

```bash
# -----------------------------------------------------------------------------
# 5.5c docker/php/skeleton — fondations DDD (uniquement avec --ddd)
# -----------------------------------------------------------------------------
# Découpage par contexte borné : src/Shared/ + src/<Contexte>/{Domain,Application,
# Infrastructure,UI}. Domain et Application ne dépendent d'aucun paquet vendor :
# Deptrac le vérifie (couche Vendor). Les handlers sont tagués par _instanceof
# dans services.yaml, ce qui évite l'attribut #[AsMessageHandler] dans Application.
if (( WITH_DDD )); then
SK=docker/php/skeleton
mkdir -p "$SK"/config/packages \
         "$SK"/src/Shared/Domain/{Aggregate,Event,ValueObject,Exception} \
         "$SK"/src/Shared/Application/{Command,Query,Event} \
         "$SK"/src/Shared/Infrastructure/Messenger \
         "$SK"/tests/Shared/Domain

cat > "$SK"/src/Shared/Domain/Event/DomainEvent.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Shared\Domain\Event;

/**
 * Fait métier survenu dans un agrégat. Immuable, nommé au passé (ProductCreated…).
 */
interface DomainEvent
{
    public function aggregateId(): string;

    public function occurredOn(): \DateTimeImmutable;
}
EOF

cat > "$SK"/src/Shared/Domain/Aggregate/AggregateRoot.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Shared\Domain\Aggregate;

use App\Shared\Domain\Event\DomainEvent;

/**
 * Racine d'agrégat : enregistre les événements métier produits par ses méthodes.
 * C'est au handler applicatif de les publier après la persistance (pullDomainEvents),
 * jamais à l'agrégat lui-même : le domaine ignore l'existence d'un bus.
 */
abstract class AggregateRoot
{
    /** @var list<DomainEvent> */
    private array $domainEvents = [];

    protected function record(DomainEvent $event): void
    {
        $this->domainEvents[] = $event;
    }

    /**
     * Restitue les événements enregistrés et vide la liste : chaque événement
     * n'est publié qu'une fois.
     *
     * @return list<DomainEvent>
     */
    public function pullDomainEvents(): array
    {
        $events = $this->domainEvents;
        $this->domainEvents = [];

        return $events;
    }
}
EOF

cat > "$SK"/src/Shared/Domain/ValueObject/ValueObject.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Shared\Domain\ValueObject;

/**
 * Objet-valeur : défini par ses attributs, sans identité, immuable, auto-validé.
 */
interface ValueObject
{
    public function equals(ValueObject $other): bool;
}
EOF

cat > "$SK"/src/Shared/Domain/Exception/DomainException.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Shared\Domain\Exception;

/**
 * Base de toutes les exceptions métier. L'UI s'appuie sur ce type pour traduire
 * une règle violée en réponse HTTP (422, 404…) sans connaître chaque cas.
 */
abstract class DomainException extends \DomainException
{
}
EOF
```

- [ ] **Step 2 : `Shared\Application` — messages et bus**

Continuer la section 5.5c :

```bash
cat > "$SK"/src/Shared/Application/Command/Command.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Shared\Application\Command;

/**
 * Intention de modification. Marqueur : permet à CommandBus de n'accepter que des commandes.
 */
interface Command
{
}
EOF

cat > "$SK"/src/Shared/Application/Command/CommandHandler.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Shared\Application\Command;

/**
 * Marqueur des handlers de commande. services.yaml les tague pour Messenger
 * (bus command.bus) via _instanceof : aucune dépendance vendor ici.
 * Le message traité est déduit du type du paramètre de __invoke().
 */
interface CommandHandler
{
}
EOF

cat > "$SK"/src/Shared/Application/Command/CommandBus.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Shared\Application\Command;

interface CommandBus
{
    public function dispatch(Command $command): void;
}
EOF

cat > "$SK"/src/Shared/Application/Query/Query.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Shared\Application\Query;

/**
 * Demande de lecture. Ne modifie jamais l'état ; renvoie un DTO de lecture.
 */
interface Query
{
}
EOF

cat > "$SK"/src/Shared/Application/Query/QueryHandler.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Shared\Application\Query;

/**
 * Marqueur des handlers de requête, tagués pour le bus query.bus via _instanceof.
 */
interface QueryHandler
{
}
EOF

cat > "$SK"/src/Shared/Application/Query/QueryBus.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Shared\Application\Query;

interface QueryBus
{
    /**
     * Le type de retour dépend de la requête : l'appelant vérifie le DTO reçu.
     */
    public function ask(Query $query): mixed;
}
EOF

cat > "$SK"/src/Shared/Application/Event/EventBus.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Shared\Application\Event;

use App\Shared\Domain\Event\DomainEvent;

interface EventBus
{
    public function publish(DomainEvent ...$events): void;
}
EOF
```

- [ ] **Step 3 : `Shared\Infrastructure\Messenger` — implémentations**

```bash
cat > "$SK"/src/Shared/Infrastructure/Messenger/MessengerCommandBus.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Shared\Infrastructure\Messenger;

use App\Shared\Application\Command\Command;
use App\Shared\Application\Command\CommandBus;
use Symfony\Component\Messenger\Exception\HandlerFailedException;
use Symfony\Component\Messenger\MessageBusInterface;

final class MessengerCommandBus implements CommandBus
{
    /**
     * `$commandBus` : Messenger crée un alias d'autowiring par bus, nommé d'après
     * le bus (command.bus → $commandBus). Le nom du paramètre est donc significatif.
     */
    public function __construct(private readonly MessageBusInterface $commandBus)
    {
    }

    public function dispatch(Command $command): void
    {
        try {
            $this->commandBus->dispatch($command);
        } catch (HandlerFailedException $e) {
            // Messenger enveloppe l'exception du handler : on rétablit l'exception
            // métier d'origine pour que l'UI puisse la traduire (422, 404…).
            throw $e->getPrevious() ?? $e;
        }
    }
}
EOF

cat > "$SK"/src/Shared/Infrastructure/Messenger/MessengerQueryBus.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Shared\Infrastructure\Messenger;

use App\Shared\Application\Query\Query;
use App\Shared\Application\Query\QueryBus;
use Symfony\Component\Messenger\Exception\HandlerFailedException;
use Symfony\Component\Messenger\HandleTrait;
use Symfony\Component\Messenger\MessageBusInterface;

final class MessengerQueryBus implements QueryBus
{
    // HandleTrait : dispatch synchrone qui renvoie le résultat de l'unique handler.
    use HandleTrait;

    public function __construct(MessageBusInterface $queryBus)
    {
        $this->messageBus = $queryBus;
    }

    public function ask(Query $query): mixed
    {
        try {
            return $this->handle($query);
        } catch (HandlerFailedException $e) {
            throw $e->getPrevious() ?? $e;
        }
    }
}
EOF

cat > "$SK"/src/Shared/Infrastructure/Messenger/MessengerEventBus.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Shared\Infrastructure\Messenger;

use App\Shared\Application\Event\EventBus;
use App\Shared\Domain\Event\DomainEvent;
use Symfony\Component\Messenger\MessageBusInterface;

final class MessengerEventBus implements EventBus
{
    public function __construct(private readonly MessageBusInterface $eventBus)
    {
    }

    public function publish(DomainEvent ...$events): void
    {
        foreach ($events as $event) {
            $this->eventBus->dispatch($event);
        }
    }
}
EOF
```

- [ ] **Step 4 : Configuration — `services.yaml`, `messenger_ddd.yaml`, `doctrine_ddd.yaml`, `deptrac.yaml`**

```bash
# ÉCRASE la recette : c'est le seul fichier de configuration remplacé, parce que
# services.yaml est importé en dernier par le Kernel et ne peut être complété
# depuis config/packages/.
cat > "$SK"/config/services.yaml <<'EOF'
# Configuration des services — architecture DDD par contextes bornés.
# Généré par create-symfony-project.sh (--ddd). Remplace la recette Flex.
parameters:

services:
    _defaults:
        autowire: true
        autoconfigure: true

    # Les handlers sont reconnus par leur interface marqueur, sans attribut
    # Messenger dans la couche Application (vérifié par Deptrac). Le message
    # traité est déduit du type du paramètre de __invoke().
    _instanceof:
        App\Shared\Application\Command\CommandHandler:
            tags:
                - { name: messenger.message_handler, bus: command.bus }
        App\Shared\Application\Query\QueryHandler:
            tags:
                - { name: messenger.message_handler, bus: query.bus }

    App\:
        resource: '../src/'
        exclude:
            - '../src/Kernel.php'
            # Le domaine n'est pas un ensemble de services : entités, objets-valeur,
            # événements et exceptions sont instanciés par le code, pas par le conteneur.
            - '../src/*/Domain/'
            # DTO de lecture : de simples structures.
            - '../src/*/Application/*/DTO/'
            - '../src/*/Application/DTO/'
            # Doubles de test : jamais dans le conteneur, sinon deux implémentations
            # pour un même port et l'auto-alias disparaît.
            - '../src/*/Infrastructure/InMemory/'
    # Les interfaces de dépôt (Domain) sont résolues par l'auto-alias de Symfony :
    # une interface, une implémentation (Infrastructure) → aucun binding manuel.
EOF

# FUSIONNÉ avec la recette symfony/messenger par le composant Config : on ajoute
# les bus sans toucher aux transports ni au routage existants.
cat > "$SK"/config/packages/messenger_ddd.yaml <<'EOF'
# Trois bus, un par nature de message. Fusionné avec messenger.yaml (recette).
framework:
    messenger:
        default_bus: command.bus
        buses:
            command.bus:
                middleware:
                    # Une commande = une transaction : rollback si le handler échoue.
                    - doctrine_transaction
            query.bus: ~
            event.bus:
                default_middleware:
                    # Un événement sans abonné n'est pas une erreur.
                    allow_no_handlers: true
EOF

# FUSIONNÉ avec doctrine.yaml (recette). Chaque contexte apporte son propre
# fichier doctrine_<contexte>.yaml (mapping XML + types DBAL).
cat > "$SK"/config/packages/doctrine_ddd.yaml <<'EOF'
# Options ORM communes à tous les contextes. Fusionné avec doctrine.yaml (recette).
# Le mapping de chaque contexte vit dans config/packages/doctrine_<contexte>.yaml.
doctrine:
    orm:
        # Le mapping est en XML (le domaine reste sans attribut Doctrine) :
        # on le valide au chargement pour détecter une faute de frappe tôt.
        validate_xml_mapping: true
EOF

cat > "$SK"/deptrac.yaml <<'EOF'
# Règles de dépendance entre couches — lancer : make deptrac
# Une violation = build rouge. C'est ce qui rend le découpage réellement contraignant.
deptrac:
  paths:
    - ./src
  layers:
    - name: Domain
      collectors:
        - type: classNameRegex
          value: '#^App\\[^\\]+\\Domain\\#'
    - name: Application
      collectors:
        - type: classNameRegex
          value: '#^App\\[^\\]+\\Application\\#'
    - name: Infrastructure
      collectors:
        - type: classNameRegex
          value: '#^App\\[^\\]+\\Infrastructure\\#'
    - name: UI
      collectors:
        - type: classNameRegex
          value: '#^App\\[^\\]+\\UI\\#'
    # Paquets tiers : autorisés seulement en Infrastructure et UI.
    # PSR (Psr\) est volontairement hors de cette couche : ce sont des interfaces
    # normalisées (horloge, logger), acceptables en Application.
    - name: Vendor
      collectors:
        - type: classNameRegex
          value: '#^(Doctrine|Symfony|ApiPlatform)\\#'
  ruleset:
    Domain: ~
    Application: [Domain]
    Infrastructure: [Domain, Application, Vendor]
    UI: [Domain, Application, Vendor]
EOF
```

- [ ] **Step 5 : Test de `AggregateRoot` et fermeture du bloc**

```bash
cat > "$SK"/tests/Shared/Domain/AggregateRootTest.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Tests\Shared\Domain;

use App\Shared\Domain\Aggregate\AggregateRoot;
use App\Shared\Domain\Event\DomainEvent;
use PHPUnit\Framework\TestCase;

final class AggregateRootTest extends TestCase
{
    public function testPullReturnsRecordedEventsInOrderThenEmptiesTheList(): void
    {
        $aggregate = new class extends AggregateRoot {
            public function doSomething(string $id): void
            {
                $this->record(self::event($id));
            }

            private static function event(string $id): DomainEvent
            {
                return new class($id) implements DomainEvent {
                    public function __construct(private readonly string $id)
                    {
                    }

                    public function aggregateId(): string
                    {
                        return $this->id;
                    }

                    public function occurredOn(): \DateTimeImmutable
                    {
                        return new \DateTimeImmutable('2026-01-01T00:00:00+00:00');
                    }
                };
            }
        };

        $aggregate->doSomething('a');
        $aggregate->doSomething('b');

        $events = $aggregate->pullDomainEvents();

        self::assertCount(2, $events);
        self::assertSame('a', $events[0]->aggregateId());
        self::assertSame('b', $events[1]->aggregateId());
        self::assertSame([], $aggregate->pullDomainEvents(), 'Les événements ne sont publiés qu\'une fois.');
    }

    public function testFreshAggregateHasNoEvents(): void
    {
        $aggregate = new class extends AggregateRoot {
        };

        self::assertSame([], $aggregate->pullDomainEvents());
    }
}
EOF
fi  # WITH_DDD — la section 5.5d (exemple Catalog) ouvre son propre bloc.
```

- [ ] **Step 6 : Makefile — cible `deptrac`**

Dans la section 5.9, après la cible `test:` ajoutée en Task 2, la cible `deptrac` ne doit apparaître qu'avec `--ddd`. Le Makefile est produit par `{ cat <<'EOF' ... EOF; if ...; fi; } > Makefile` : fermer le premier heredoc juste après `test:`, puis insérer :

```bash
if (( WITH_DDD )); then
cat <<'EOF'

deptrac: ## Vérifie les dépendances entre couches DDD (Domain → rien, etc.)
	$(DC) exec --user dev backend vendor/bin/deptrac analyse --config-file=deptrac.yaml
EOF
fi
cat <<'EOF'
```

et rouvrir le heredoc principal pour la suite (`# --- Images déployables ...`). Vérifier qu'aucune ligne vide parasite n'apparaît entre les cibles dans `make help`.

- [ ] **Step 7 : Vérifier la génération**

```bash
bash -n create-symfony-project.sh
S=/tmp/claude-1000/-media-shared-data-projects-symfony-docker-generator/516574fe-7cc9-42f9-a675-89900343752b/scratchpad
rm -rf "$S/t3" && mkdir -p "$S/t3" && cd "$S/t3"
G=/media/shared_data/projects/symfony-docker-generator/create-symfony-project.sh
bash "$G" p --no-build >/dev/null && ls p/docker/php/skeleton                       # phpstan.neon seul
(cd p && make help | grep -c deptrac)                                                  # 0
bash "$G" q --ddd --no-build >/dev/null && find q/docker/php/skeleton -type f | sort   # 15 fichiers : phpstan.neon, deptrac.yaml, 3 yaml config, 9 PHP Shared, 1 test
(cd q && make help | grep -E 'deptrac|phpstan|test')                                   # 3 cibles alignées
for f in $(find q/docker/php/skeleton -name '*.php'); do php -l "$f" >/dev/null || echo "KO $f"; done   # aucun KO (PHP 8.4 local)
```

- [ ] **Step 8 : Vérifier par un build réel (`--ddd`, mode full)**

```bash
cd ~/dev && rm -rf ddd-t3 && bash "$G" ddd-t3 --ddd --no-build >/dev/null && cd ddd-t3
make build 2>&1 | tail -2 && make up
make init 2>&1 | tail -12          # attendu : Deptrac installé, gabarit appliqué, cache:warmup OK
make phpstan 2>&1 | tail -4        # [OK] No errors
make deptrac 2>&1 | tail -8        # "Violations 0", "Allowed dependencies" > 0
make test 2>&1 | tail -4           # OK (2 tests, 5 assertions)
docker compose exec --user dev backend php bin/console debug:messenger 2>&1 | head -20
#   attendu : trois bus listés (command.bus, query.bus, event.bus)
```

**Preuve que le garde-fou mord** : ajouter volontairement une violation puis la retirer.

```bash
sed -i 's|^abstract class AggregateRoot|use Doctrine\\ORM\\EntityManagerInterface;\n\nabstract class AggregateRoot|' backend/src/Shared/Domain/Aggregate/AggregateRoot.php
sed -i 's|    private array \$domainEvents = \[\];|    private array $domainEvents = [];\n    private ?EntityManagerInterface $leak = null;|' backend/src/Shared/Domain/Aggregate/AggregateRoot.php
make deptrac 2>&1 | tail -6        # attendu : "Violations 1", Domain must not depend on Vendor, exit code 1
git -C . checkout -- backend/src/Shared/Domain/Aggregate/AggregateRoot.php 2>/dev/null || cp docker/php/skeleton/src/Shared/Domain/Aggregate/AggregateRoot.php backend/src/Shared/Domain/Aggregate/AggregateRoot.php
make deptrac 2>&1 | tail -3        # Violations 0
docker compose down -v
```

Si `services.yaml` provoque une erreur de compilation du conteneur (motif `exclude` non reconnu), corriger le motif dans le gabarit du script, régénérer et rejouer `make init` sur un projet neuf. Ne pas corriger à la main dans `backend/`.

- [ ] **Step 9 : Commit**

```bash
git add create-symfony-project.sh
git commit -m "feat(ddd): fondations Shared, trois bus Messenger, services.yaml DDD, Deptrac avec couche Vendor"
```

---

### Task 4 : Contexte d'exemple `Catalog` (`--ddd-example`) — Domain, Application, Infrastructure, tests

**Files:**
- Modify: `create-symfony-project.sh` — nouvelle section `5.5d` après 5.5c

**Interfaces:**
- Consumes : tout Task 3.
- Produces (pour Task 5) :
  - `App\Catalog\Domain\Model\ProductId::fromString(string): self`, `->value` (string), `__toString()`
  - `App\Catalog\Domain\Exception\{ProductNotFound, InvalidProductId, InvalidProductName, InvalidPrice}` (étendent `DomainException`)
  - `App\Catalog\Application\Command\CreateProductCommand(string $id, string $name, int $amount, string $currency)`
  - `App\Catalog\Application\Query\GetProductQuery(string $id)` → `App\Catalog\Application\DTO\ProductView` (`id, name, amount, currency, createdAt` publics readonly, `createdAt` au format ATOM)

- [ ] **Step 1 : Ouvrir 5.5d, dossiers, exceptions et objets-valeur**

Après le `fi  # WITH_DDD` de 5.5c, insérer :

```bash
# -----------------------------------------------------------------------------
# 5.5d docker/php/skeleton — contexte borné d'exemple Catalog (--ddd-example)
# -----------------------------------------------------------------------------
# Un agrégat (Product), ses objets-valeur, un dépôt (interface + Doctrine + mémoire),
# une commande, une requête, une UI. Sert de modèle à copier pour un vrai contexte,
# puis se supprime d'un `rm -r src/Catalog tests/Catalog config/packages/doctrine_catalog.yaml`.
if (( WITH_DDD_EXAMPLE )); then
SK=docker/php/skeleton
mkdir -p "$SK"/src/Catalog/Domain/{Model,Event,Exception,Repository} \
         "$SK"/src/Catalog/Application/{Command,Query,DTO} \
         "$SK"/src/Catalog/Infrastructure/Doctrine/{Mapping,Type} \
         "$SK"/src/Catalog/Infrastructure/InMemory \
         "$SK"/src/Catalog/UI/Http \
         "$SK"/tests/Catalog/{Domain,Application}


cat > "$SK"/src/Catalog/Domain/Exception/ProductNotFound.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Domain\Exception;

use App\Catalog\Domain\Model\ProductId;
use App\Shared\Domain\Exception\DomainException;

final class ProductNotFound extends DomainException
{
    public function __construct(ProductId $id)
    {
        parent::__construct(sprintf('Produit "%s" introuvable.', $id->value));
    }
}
EOF

cat > "$SK"/src/Catalog/Domain/Exception/InvalidProductId.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Domain\Exception;

use App\Shared\Domain\Exception\DomainException;

final class InvalidProductId extends DomainException
{
    public function __construct(string $value)
    {
        parent::__construct(sprintf('"%s" n\'est pas un identifiant de produit valide (UUID attendu).', $value));
    }
}
EOF

cat > "$SK"/src/Catalog/Domain/Exception/InvalidProductName.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Domain\Exception;

use App\Shared\Domain\Exception\DomainException;

final class InvalidProductName extends DomainException
{
    public function __construct(string $reason)
    {
        parent::__construct(sprintf('Nom de produit invalide : %s.', $reason));
    }
}
EOF

cat > "$SK"/src/Catalog/Domain/Exception/InvalidPrice.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Domain\Exception;

use App\Shared\Domain\Exception\DomainException;

final class InvalidPrice extends DomainException
{
    public function __construct(string $reason)
    {
        parent::__construct(sprintf('Prix invalide : %s.', $reason));
    }
}
EOF

cat > "$SK"/src/Catalog/Domain/Model/ProductId.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Domain\Model;

use App\Catalog\Domain\Exception\InvalidProductId;
use App\Shared\Domain\ValueObject\ValueObject;

/**
 * Identifiant du produit : un UUID, généré HORS du domaine (UI ou Infrastructure)
 * pour que le domaine ne dépende d'aucune bibliothèque.
 */
final class ProductId implements ValueObject, \Stringable
{
    private const string PATTERN = '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/';

    private function __construct(public readonly string $value)
    {
    }

    public static function fromString(string $value): self
    {
        $normalized = strtolower(trim($value));
        if (preg_match(self::PATTERN, $normalized) !== 1) {
            throw new InvalidProductId($value);
        }

        return new self($normalized);
    }

    public function equals(ValueObject $other): bool
    {
        return $other instanceof self && $other->value === $this->value;
    }

    public function __toString(): string
    {
        return $this->value;
    }
}
EOF

cat > "$SK"/src/Catalog/Domain/Model/ProductName.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Domain\Model;

use App\Catalog\Domain\Exception\InvalidProductName;
use App\Shared\Domain\ValueObject\ValueObject;

/**
 * Nom commercial : 1 à 120 caractères après suppression des espaces aux extrémités.
 * Persisté en embeddable Doctrine (voir Infrastructure/Doctrine/Mapping/ProductName.orm.xml).
 */
final class ProductName implements ValueObject, \Stringable
{
    public const int MAX_LENGTH = 120;

    private function __construct(public readonly string $value)
    {
    }

    public static function fromString(string $value): self
    {
        $trimmed = trim($value);
        if ($trimmed === '') {
            throw new InvalidProductName('le nom est vide');
        }
        if (mb_strlen($trimmed) > self::MAX_LENGTH) {
            throw new InvalidProductName(sprintf('%d caractères maximum', self::MAX_LENGTH));
        }

        return new self($trimmed);
    }

    public function equals(ValueObject $other): bool
    {
        return $other instanceof self && $other->value === $this->value;
    }

    public function __toString(): string
    {
        return $this->value;
    }
}
EOF

cat > "$SK"/src/Catalog/Domain/Model/Price.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Domain\Model;

use App\Catalog\Domain\Exception\InvalidPrice;
use App\Shared\Domain\ValueObject\ValueObject;

/**
 * Montant en unité mineure (centimes) + devise ISO 4217 : jamais de flottant pour
 * de l'argent. Persisté en embeddable (colonnes price_amount, price_currency).
 */
final class Price implements ValueObject
{
    public readonly string $currency;

    public function __construct(public readonly int $amount, string $currency)
    {
        if ($amount < 0) {
            throw new InvalidPrice('le montant ne peut pas être négatif');
        }
        $upper = strtoupper($currency);
        if (preg_match('/^[A-Z]{3}$/', $upper) !== 1) {
            throw new InvalidPrice(sprintf('"%s" n\'est pas un code devise ISO 4217', $currency));
        }
        $this->currency = $upper;
    }

    public function equals(ValueObject $other): bool
    {
        return $other instanceof self
            && $other->amount === $this->amount
            && $other->currency === $this->currency;
    }
}
EOF
```

- [ ] **Step 2 : Événement, agrégat, dépôt**

```bash
cat > "$SK"/src/Catalog/Domain/Event/ProductCreated.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Domain\Event;

use App\Catalog\Domain\Model\ProductId;
use App\Shared\Domain\Event\DomainEvent;

final class ProductCreated implements DomainEvent
{
    public function __construct(
        private readonly ProductId $productId,
        private readonly \DateTimeImmutable $occurredOn,
    ) {
    }

    public function aggregateId(): string
    {
        return $this->productId->value;
    }

    public function occurredOn(): \DateTimeImmutable
    {
        return $this->occurredOn;
    }
}
EOF

cat > "$SK"/src/Catalog/Domain/Model/Product.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Domain\Model;

use App\Catalog\Domain\Event\ProductCreated;
use App\Shared\Domain\Aggregate\AggregateRoot;

/**
 * Agrégat Produit. Constructeur privé : on passe par la fabrique `create`, seul
 * point où l'événement ProductCreated est enregistré. Aucun attribut Doctrine :
 * le mapping est en XML dans Infrastructure/Doctrine/Mapping/Product.orm.xml.
 */
final class Product extends AggregateRoot
{
    private function __construct(
        private readonly ProductId $id,
        private ProductName $name,
        private Price $price,
        private readonly \DateTimeImmutable $createdAt,
    ) {
    }

    public static function create(ProductId $id, ProductName $name, Price $price, \DateTimeImmutable $now): self
    {
        $product = new self($id, $name, $price, $now);
        $product->record(new ProductCreated($id, $now));

        return $product;
    }

    public function changePrice(Price $price): void
    {
        $this->price = $price;
    }

    public function rename(ProductName $name): void
    {
        $this->name = $name;
    }

    public function id(): ProductId
    {
        return $this->id;
    }

    public function name(): ProductName
    {
        return $this->name;
    }

    public function price(): Price
    {
        return $this->price;
    }

    public function createdAt(): \DateTimeImmutable
    {
        return $this->createdAt;
    }
}
EOF

cat > "$SK"/src/Catalog/Domain/Repository/ProductRepository.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Domain\Repository;

use App\Catalog\Domain\Exception\ProductNotFound;
use App\Catalog\Domain\Model\Product;
use App\Catalog\Domain\Model\ProductId;

/**
 * Port de persistance, exprimé dans le vocabulaire du domaine. L'implémentation
 * Doctrine vit en Infrastructure ; Symfony la relie par auto-alias (une seule
 * implémentation de service).
 */
interface ProductRepository
{
    public function save(Product $product): void;

    /** @throws ProductNotFound */
    public function get(ProductId $id): Product;
}
EOF
```

- [ ] **Step 3 : Application — commande, requête, DTO, handlers**

```bash
cat > "$SK"/src/Catalog/Application/Command/CreateProductCommand.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Application\Command;

use App\Shared\Application\Command\Command;

/**
 * L'identifiant est fourni par l'appelant (UUID généré côté UI) : la réponse HTTP
 * peut ainsi renvoyer l'URL de la ressource sans attendre de valeur de retour.
 */
final readonly class CreateProductCommand implements Command
{
    public function __construct(
        public string $id,
        public string $name,
        public int $amount,
        public string $currency,
    ) {
    }
}
EOF

cat > "$SK"/src/Catalog/Application/Command/CreateProductHandler.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Application\Command;

use App\Catalog\Domain\Model\Price;
use App\Catalog\Domain\Model\Product;
use App\Catalog\Domain\Model\ProductId;
use App\Catalog\Domain\Model\ProductName;
use App\Catalog\Domain\Repository\ProductRepository;
use App\Shared\Application\Command\CommandHandler;
use App\Shared\Application\Event\EventBus;
use Psr\Clock\ClockInterface;

final class CreateProductHandler implements CommandHandler
{
    public function __construct(
        private readonly ProductRepository $products,
        private readonly EventBus $eventBus,
        private readonly ClockInterface $clock,
    ) {
    }

    public function __invoke(CreateProductCommand $command): void
    {
        $product = Product::create(
            ProductId::fromString($command->id),
            ProductName::fromString($command->name),
            new Price($command->amount, $command->currency),
            $this->clock->now(),
        );

        $this->products->save($product);
        // Publication APRÈS persistance : un abonné ne doit jamais voir un événement
        // dont l'état n'a pas été sauvegardé.
        $this->eventBus->publish(...$product->pullDomainEvents());
    }
}
EOF

cat > "$SK"/src/Catalog/Application/Query/GetProductQuery.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Application\Query;

use App\Shared\Application\Query\Query;

final readonly class GetProductQuery implements Query
{
    public function __construct(public string $id)
    {
    }
}
EOF

cat > "$SK"/src/Catalog/Application/DTO/ProductView.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Application\DTO;

use App\Catalog\Domain\Model\Product;

/**
 * Représentation de lecture, plate et sérialisable telle quelle en JSON.
 * Découple l'UI de la forme interne de l'agrégat.
 */
final readonly class ProductView
{
    public function __construct(
        public string $id,
        public string $name,
        public int $amount,
        public string $currency,
        public string $createdAt,
    ) {
    }

    public static function fromProduct(Product $product): self
    {
        return new self(
            $product->id()->value,
            $product->name()->value,
            $product->price()->amount,
            $product->price()->currency,
            $product->createdAt()->format(\DateTimeInterface::ATOM),
        );
    }
}
EOF

cat > "$SK"/src/Catalog/Application/Query/GetProductHandler.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Application\Query;

use App\Catalog\Application\DTO\ProductView;
use App\Catalog\Domain\Model\ProductId;
use App\Catalog\Domain\Repository\ProductRepository;
use App\Shared\Application\Query\QueryHandler;

final class GetProductHandler implements QueryHandler
{
    public function __construct(private readonly ProductRepository $products)
    {
    }

    public function __invoke(GetProductQuery $query): ProductView
    {
        return ProductView::fromProduct(
            $this->products->get(ProductId::fromString($query->id)),
        );
    }
}
EOF
```

`Psr\Clock\ClockInterface` : Symfony fournit le service `clock` (composant `symfony/clock`, présent dans le squelette) et son alias vers l'interface PSR. La regex de la couche `Vendor` de Deptrac (Task 3) exclut `Psr\` pour cette raison : une interface PSR est une norme, pas un framework.

- [ ] **Step 4 : Infrastructure — mapping XML, type DBAL, dépôts**

```bash
cat > "$SK"/src/Catalog/Infrastructure/Doctrine/Mapping/Product.orm.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!-- Mapping de l'agrégat Product. Le domaine ne porte aucun attribut Doctrine :
     tout ce que l'ORM doit savoir est ici. Nom de fichier = classe relative au
     préfixe App\Catalog\Domain\Model (pilote XML simplifié). -->
<doctrine-mapping xmlns="http://doctrine-project.org/schemas/orm/doctrine-mapping"
                  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                  xsi:schemaLocation="http://doctrine-project.org/schemas/orm/doctrine-mapping
                                      https://www.doctrine-project.org/schemas/orm/doctrine-mapping.xsd">

    <entity name="App\Catalog\Domain\Model\Product" table="catalog_product">
        <id name="id" type="product_id" column="id"/>
        <embedded name="name" class="App\Catalog\Domain\Model\ProductName" use-column-prefix="false"/>
        <embedded name="price" class="App\Catalog\Domain\Model\Price" column-prefix="price_"/>
        <field name="createdAt" type="datetime_immutable" column="created_at"/>
    </entity>

</doctrine-mapping>
EOF

cat > "$SK"/src/Catalog/Infrastructure/Doctrine/Mapping/ProductName.orm.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<doctrine-mapping xmlns="http://doctrine-project.org/schemas/orm/doctrine-mapping"
                  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                  xsi:schemaLocation="http://doctrine-project.org/schemas/orm/doctrine-mapping
                                      https://www.doctrine-project.org/schemas/orm/doctrine-mapping.xsd">

    <embeddable name="App\Catalog\Domain\Model\ProductName">
        <field name="value" type="string" length="120" column="name"/>
    </embeddable>

</doctrine-mapping>
EOF

cat > "$SK"/src/Catalog/Infrastructure/Doctrine/Mapping/Price.orm.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<doctrine-mapping xmlns="http://doctrine-project.org/schemas/orm/doctrine-mapping"
                  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                  xsi:schemaLocation="http://doctrine-project.org/schemas/orm/doctrine-mapping
                                      https://www.doctrine-project.org/schemas/orm/doctrine-mapping.xsd">

    <embeddable name="App\Catalog\Domain\Model\Price">
        <field name="amount" type="integer"/>
        <field name="currency" type="string" length="3"/>
    </embeddable>

</doctrine-mapping>
EOF

cat > "$SK"/src/Catalog/Infrastructure/Doctrine/Type/ProductIdType.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Infrastructure\Doctrine\Type;

use App\Catalog\Domain\Model\ProductId;
use Doctrine\DBAL\Platforms\AbstractPlatform;
use Doctrine\DBAL\Types\Exception\InvalidType;
use Doctrine\DBAL\Types\Type;

/**
 * Type DBAL `product_id` : colonne UUID native ↔ objet-valeur ProductId.
 * Déclaré dans config/packages/doctrine_catalog.yaml (dbal.types).
 */
final class ProductIdType extends Type
{
    public const string NAME = 'product_id';

    /** @param array<string, mixed> $column */
    public function getSQLDeclaration(array $column, AbstractPlatform $platform): string
    {
        return $platform->getGuidTypeDeclarationSQL($column);
    }

    public function convertToPHPValue(mixed $value, AbstractPlatform $platform): ?ProductId
    {
        if ($value === null || $value instanceof ProductId) {
            return $value;
        }
        if (!is_string($value)) {
            throw InvalidType::new($value, self::class, ['null', 'string', ProductId::class]);
        }

        return ProductId::fromString($value);
    }

    public function convertToDatabaseValue(mixed $value, AbstractPlatform $platform): ?string
    {
        if ($value === null) {
            return null;
        }
        if ($value instanceof ProductId) {
            return $value->value;
        }
        if (is_string($value)) {
            return ProductId::fromString($value)->value;
        }

        throw InvalidType::new($value, self::class, ['null', 'string', ProductId::class]);
    }
}
EOF

cat > "$SK"/src/Catalog/Infrastructure/Doctrine/DoctrineProductRepository.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Infrastructure\Doctrine;

use App\Catalog\Domain\Exception\ProductNotFound;
use App\Catalog\Domain\Model\Product;
use App\Catalog\Domain\Model\ProductId;
use App\Catalog\Domain\Repository\ProductRepository;
use Doctrine\ORM\EntityManagerInterface;

final class DoctrineProductRepository implements ProductRepository
{
    public function __construct(private readonly EntityManagerInterface $entityManager)
    {
    }

    public function save(Product $product): void
    {
        $this->entityManager->persist($product);
        // Le middleware doctrine_transaction du command.bus englobe ce flush dans
        // une transaction ; hors bus (console, tests d'intégration) il reste utile.
        $this->entityManager->flush();
    }

    public function get(ProductId $id): Product
    {
        // find() accepte l'objet-valeur : le type DBAL product_id le convertit.
        $product = $this->entityManager->find(Product::class, $id);
        if ($product === null) {
            throw new ProductNotFound($id);
        }

        return $product;
    }
}
EOF

cat > "$SK"/src/Catalog/Infrastructure/InMemory/InMemoryProductRepository.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\Infrastructure\InMemory;

use App\Catalog\Domain\Exception\ProductNotFound;
use App\Catalog\Domain\Model\Product;
use App\Catalog\Domain\Model\ProductId;
use App\Catalog\Domain\Repository\ProductRepository;

/**
 * Dépôt en mémoire pour les tests applicatifs : mêmes garanties que l'interface,
 * zéro base de données. Exclu de l'autowiring pour ne pas concurrencer Doctrine
 * (voir services.yaml : une interface → une implémentation).
 */
final class InMemoryProductRepository implements ProductRepository
{
    /** @var array<string, Product> */
    private array $products = [];

    public function save(Product $product): void
    {
        $this->products[$product->id()->value] = $product;
    }

    public function get(ProductId $id): Product
    {
        return $this->products[$id->value] ?? throw new ProductNotFound($id);
    }

    public function count(): int
    {
        return count($this->products);
    }
}
EOF
```

Le dépôt mémoire n'est pas un service : `services.yaml` (Task 3) exclut `Infrastructure/InMemory/`, sinon deux implémentations concurrenceraient l'auto-alias de `ProductRepository`.

- [ ] **Step 5 : `doctrine_catalog.yaml`**

```bash
mkdir -p "$SK"/config/packages
cat > "$SK"/config/packages/doctrine_catalog.yaml <<'EOF'
# Mapping du contexte Catalog. Fusionné avec doctrine.yaml et doctrine_ddd.yaml.
# Pour un nouveau contexte : copier ce fichier, adapter dir/prefix/alias/types.
doctrine:
    dbal:
        types:
            product_id: App\Catalog\Infrastructure\Doctrine\Type\ProductIdType
    orm:
        mappings:
            Catalog:
                type: xml
                is_bundle: false
                dir: '%kernel.project_dir%/src/Catalog/Infrastructure/Doctrine/Mapping'
                prefix: 'App\Catalog\Domain\Model'
                alias: Catalog
EOF
```

- [ ] **Step 6 : Tests du domaine**

```bash
cat > "$SK"/tests/Catalog/Domain/ProductNameTest.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Tests\Catalog\Domain;

use App\Catalog\Domain\Exception\InvalidProductName;
use App\Catalog\Domain\Model\ProductName;
use PHPUnit\Framework\TestCase;

final class ProductNameTest extends TestCase
{
    public function testTrimsSurroundingWhitespace(): void
    {
        self::assertSame('Clavier', ProductName::fromString('  Clavier ')->value);
    }

    public function testAcceptsMaximumLength(): void
    {
        $name = str_repeat('a', ProductName::MAX_LENGTH);

        self::assertSame($name, ProductName::fromString($name)->value);
    }

    public function testRejectsEmptyName(): void
    {
        $this->expectException(InvalidProductName::class);

        ProductName::fromString('   ');
    }

    public function testRejectsNameLongerThanMaximum(): void
    {
        $this->expectException(InvalidProductName::class);

        ProductName::fromString(str_repeat('a', ProductName::MAX_LENGTH + 1));
    }

    public function testEqualityIsByValue(): void
    {
        self::assertTrue(ProductName::fromString('A')->equals(ProductName::fromString('A')));
        self::assertFalse(ProductName::fromString('A')->equals(ProductName::fromString('B')));
    }
}
EOF

cat > "$SK"/tests/Catalog/Domain/PriceTest.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Tests\Catalog\Domain;

use App\Catalog\Domain\Exception\InvalidPrice;
use App\Catalog\Domain\Model\Price;
use PHPUnit\Framework\TestCase;

final class PriceTest extends TestCase
{
    public function testNormalizesCurrencyToUpperCase(): void
    {
        $price = new Price(1990, 'eur');

        self::assertSame(1990, $price->amount);
        self::assertSame('EUR', $price->currency);
    }

    public function testZeroIsAllowed(): void
    {
        self::assertSame(0, (new Price(0, 'EUR'))->amount);
    }

    public function testRejectsNegativeAmount(): void
    {
        $this->expectException(InvalidPrice::class);

        new Price(-1, 'EUR');
    }

    public function testRejectsMalformedCurrency(): void
    {
        $this->expectException(InvalidPrice::class);

        new Price(100, 'EU');
    }

    public function testEqualityIsByValue(): void
    {
        self::assertTrue((new Price(100, 'EUR'))->equals(new Price(100, 'eur')));
        self::assertFalse((new Price(100, 'EUR'))->equals(new Price(100, 'USD')));
    }
}
EOF

cat > "$SK"/tests/Catalog/Domain/ProductIdTest.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Tests\Catalog\Domain;

use App\Catalog\Domain\Exception\InvalidProductId;
use App\Catalog\Domain\Model\ProductId;
use PHPUnit\Framework\TestCase;

final class ProductIdTest extends TestCase
{
    public function testNormalizesToLowerCase(): void
    {
        $id = ProductId::fromString('0190F3A1-7C2B-7D3E-8F4A-5B6C7D8E9F00');

        self::assertSame('0190f3a1-7c2b-7d3e-8f4a-5b6c7d8e9f00', $id->value);
        self::assertSame($id->value, (string) $id);
    }

    public function testRejectsNonUuid(): void
    {
        $this->expectException(InvalidProductId::class);

        ProductId::fromString('42');
    }
}
EOF

cat > "$SK"/tests/Catalog/Domain/ProductTest.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Tests\Catalog\Domain;

use App\Catalog\Domain\Event\ProductCreated;
use App\Catalog\Domain\Model\Price;
use App\Catalog\Domain\Model\Product;
use App\Catalog\Domain\Model\ProductId;
use App\Catalog\Domain\Model\ProductName;
use PHPUnit\Framework\TestCase;

final class ProductTest extends TestCase
{
    private const string ID = '0190f3a1-7c2b-7d3e-8f4a-5b6c7d8e9f00';

    public function testCreateRecordsProductCreated(): void
    {
        $now = new \DateTimeImmutable('2026-09-13T10:00:00+00:00');

        $product = Product::create(
            ProductId::fromString(self::ID),
            ProductName::fromString('Clavier'),
            new Price(4990, 'EUR'),
            $now,
        );

        $events = $product->pullDomainEvents();

        self::assertCount(1, $events);
        self::assertInstanceOf(ProductCreated::class, $events[0]);
        self::assertSame(self::ID, $events[0]->aggregateId());
        self::assertSame($now, $events[0]->occurredOn());
        self::assertSame($now, $product->createdAt());
    }

    public function testChangePriceReplacesPrice(): void
    {
        $product = Product::create(
            ProductId::fromString(self::ID),
            ProductName::fromString('Clavier'),
            new Price(4990, 'EUR'),
            new \DateTimeImmutable(),
        );

        $product->changePrice(new Price(3990, 'EUR'));

        self::assertSame(3990, $product->price()->amount);
    }
}
EOF
```

- [ ] **Step 7 : Tests applicatifs (dépôt mémoire, bus espion, horloge fixe)**

Le bus espion est une classe nommée (et non anonyme) pour que PHPStan connaisse
sa propriété `published` ; il vit dans `tests/Shared/` pour servir à tout contexte.

```bash
mkdir -p "$SK"/tests/Shared/Application
cat > "$SK"/tests/Shared/Application/SpyEventBus.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Tests\Shared\Application;

use App\Shared\Application\Event\EventBus;
use App\Shared\Domain\Event\DomainEvent;

/**
 * Double de test : mémorise les événements publiés au lieu de les dispatcher.
 */
final class SpyEventBus implements EventBus
{
    /** @var list<DomainEvent> */
    public array $published = [];

    public function publish(DomainEvent ...$events): void
    {
        foreach ($events as $event) {
            $this->published[] = $event;
        }
    }
}
EOF

cat > "$SK"/tests/Catalog/Application/CreateProductHandlerTest.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Tests\Catalog\Application;

use App\Catalog\Application\Command\CreateProductCommand;
use App\Catalog\Application\Command\CreateProductHandler;
use App\Catalog\Domain\Event\ProductCreated;
use App\Catalog\Domain\Exception\InvalidProductName;
use App\Catalog\Domain\Model\ProductId;
use App\Catalog\Infrastructure\InMemory\InMemoryProductRepository;
use App\Tests\Shared\Application\SpyEventBus;
use PHPUnit\Framework\TestCase;
use Psr\Clock\ClockInterface;

final class CreateProductHandlerTest extends TestCase
{
    private const string ID = '0190f3a1-7c2b-7d3e-8f4a-5b6c7d8e9f00';

    private InMemoryProductRepository $products;

    private SpyEventBus $eventBus;

    private CreateProductHandler $handler;

    protected function setUp(): void
    {
        $this->products = new InMemoryProductRepository();
        $this->eventBus = new SpyEventBus();

        $clock = new class implements ClockInterface {
            public function now(): \DateTimeImmutable
            {
                return new \DateTimeImmutable('2026-09-13T10:00:00+00:00');
            }
        };

        $this->handler = new CreateProductHandler($this->products, $this->eventBus, $clock);
    }

    public function testCreatesSavesAndPublishes(): void
    {
        ($this->handler)(new CreateProductCommand(self::ID, 'Clavier', 4990, 'EUR'));

        $product = $this->products->get(ProductId::fromString(self::ID));

        self::assertSame('Clavier', $product->name()->value);
        self::assertSame(4990, $product->price()->amount);
        self::assertSame('2026-09-13T10:00:00+00:00', $product->createdAt()->format(\DateTimeInterface::ATOM));
        self::assertCount(1, $this->eventBus->published);
        self::assertInstanceOf(ProductCreated::class, $this->eventBus->published[0]);
    }

    public function testInvalidNameSavesNothingAndPublishesNothing(): void
    {
        try {
            ($this->handler)(new CreateProductCommand(self::ID, '', 4990, 'EUR'));
            self::fail('InvalidProductName attendue.');
        } catch (InvalidProductName) {
            self::assertSame(0, $this->products->count());
            self::assertSame([], $this->eventBus->published);
        }
    }
}
EOF

cat > "$SK"/tests/Catalog/Application/GetProductHandlerTest.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Tests\Catalog\Application;

use App\Catalog\Application\Query\GetProductHandler;
use App\Catalog\Application\Query\GetProductQuery;
use App\Catalog\Domain\Exception\ProductNotFound;
use App\Catalog\Domain\Model\Price;
use App\Catalog\Domain\Model\Product;
use App\Catalog\Domain\Model\ProductId;
use App\Catalog\Domain\Model\ProductName;
use App\Catalog\Infrastructure\InMemory\InMemoryProductRepository;
use PHPUnit\Framework\TestCase;

final class GetProductHandlerTest extends TestCase
{
    private const string ID = '0190f3a1-7c2b-7d3e-8f4a-5b6c7d8e9f00';

    public function testReturnsFlatView(): void
    {
        $products = new InMemoryProductRepository();
        $products->save(Product::create(
            ProductId::fromString(self::ID),
            ProductName::fromString('Clavier'),
            new Price(4990, 'EUR'),
            new \DateTimeImmutable('2026-09-13T10:00:00+00:00'),
        ));

        $view = (new GetProductHandler($products))(new GetProductQuery(self::ID));

        self::assertSame(self::ID, $view->id);
        self::assertSame('Clavier', $view->name);
        self::assertSame(4990, $view->amount);
        self::assertSame('EUR', $view->currency);
        self::assertSame('2026-09-13T10:00:00+00:00', $view->createdAt);
    }

    public function testUnknownProductThrows(): void
    {
        $this->expectException(ProductNotFound::class);

        (new GetProductHandler(new InMemoryProductRepository()))(new GetProductQuery(self::ID));
    }
}
EOF
fi  # WITH_DDD_EXAMPLE — l'UI (Task 5) rouvre ce bloc.
```

- [ ] **Step 8 : Vérifier**

```bash
bash -n create-symfony-project.sh
S=/tmp/claude-1000/-media-shared-data-projects-symfony-docker-generator/516574fe-7cc9-42f9-a675-89900343752b/scratchpad
rm -rf "$S/t4" && mkdir -p "$S/t4" && cd "$S/t4"
G=/media/shared_data/projects/symfony-docker-generator/create-symfony-project.sh
bash "$G" q --ddd --no-build >/dev/null && test ! -d q/docker/php/skeleton/src/Catalog && echo "sans exemple : OK"
bash "$G" r --ddd-example --no-build >/dev/null && find r/docker/php/skeleton/src/Catalog r/docker/php/skeleton/tests -type f | wc -l   # 29 (21 src Catalog, 1 test Shared, 1 SpyEventBus, 6 tests Catalog)
for f in $(find r/docker/php/skeleton -name '*.php'); do php -l "$f" >/dev/null || echo "KO $f"; done
xmllint --noout r/docker/php/skeleton/src/Catalog/Infrastructure/Doctrine/Mapping/*.xml && echo "XML bien formé"

# Build réel (mode full) — les tests, PHPStan et Deptrac doivent passer sans UI.
cd ~/dev && rm -rf ddd-t4 && bash "$G" ddd-t4 --ddd-example --no-build >/dev/null && cd ddd-t4
make build 2>&1 | tail -2 && make up && make init 2>&1 | tail -6
make phpstan 2>&1 | tail -4        # [OK] No errors
make deptrac 2>&1 | tail -6        # Violations 0
make test 2>&1 | tail -4           # OK (20 tests)
docker compose exec --user dev backend php bin/console doctrine:schema:validate 2>&1 | tail -6
#   attendu : "[OK] The mapping files are correct." (la base peut être "not in sync" : pas encore de migration)
docker compose exec --user dev backend php bin/console doctrine:schema:update --dump-sql 2>&1 | grep -i 'catalog_product'
#   attendu : CREATE TABLE catalog_product (id UUID NOT NULL, name VARCHAR(120), price_amount INT, price_currency VARCHAR(3), created_at TIMESTAMP...)
docker compose down -v
```

Si `doctrine:schema:validate` échoue sur les propriétés `readonly` des embeddables, remplacer `public readonly` par `public` (sans readonly) dans `Price` et `ProductName`, et le noter en commentaire : `// Pas de readonly : Doctrine hydrate les embeddables par réflexion.`

- [ ] **Step 9 : Commit**

```bash
git add create-symfony-project.sh
git commit -m "feat(ddd): contexte d'exemple Catalog (agrégat Product, bus, dépôts Doctrine et mémoire, tests)"
```

---

### Task 5 : UI du contexte `Catalog` — contrôleur JSON (mode full) ou ressource API Platform (mode api)

Le gabarit est produit sur l'hôte : le générateur connaît `WITH_FRONTEND` et choisit l'UI à écrire. Les deux variantes exposent les mêmes URL : `POST /api/products` (201 + `Location`) et `GET /api/products/{id}` (200 ou 404).

**Files:**
- Modify: `create-symfony-project.sh` — section 5.5d, avant son `fi`

**Interfaces:**
- Consumes : `CommandBus`, `QueryBus` (Task 3) ; `CreateProductCommand`, `GetProductQuery`, `ProductView`, `ProductNotFound`, `InvalidProductId`, `DomainException` (Task 4).

- [ ] **Step 1 : Mode full — contrôleur et fichier de routes**

Juste avant `fi  # WITH_DDD_EXAMPLE`, insérer :

```bash
if (( ! WITH_FRONTEND )); then
# Mode full : contrôleur JSON minimal. Pas d'AbstractController pour garder l'UI
# explicite ; #[AsController] suffit à l'enregistrer avec ses arguments.
mkdir -p "$SK"/config/routes
cat > "$SK"/src/Catalog/UI/Http/ProductController.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\UI\Http;

use App\Catalog\Application\Command\CreateProductCommand;
use App\Catalog\Application\DTO\ProductView;
use App\Catalog\Application\Query\GetProductQuery;
use App\Catalog\Domain\Exception\InvalidProductId;
use App\Catalog\Domain\Exception\ProductNotFound;
use App\Shared\Application\Command\CommandBus;
use App\Shared\Application\Query\QueryBus;
use App\Shared\Domain\Exception\DomainException;
use Symfony\Component\HttpFoundation\Exception\JsonException;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpKernel\Attribute\AsController;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\Uid\Uuid;

/**
 * Adaptateur HTTP du contexte Catalog. Ne contient aucune règle métier : il
 * traduit la requête en commande/requête, et l'exception métier en code HTTP.
 */
#[AsController]
final class ProductController
{
    public function __construct(
        private readonly CommandBus $commandBus,
        private readonly QueryBus $queryBus,
    ) {
    }

    #[Route('/api/products', name: 'catalog_product_create', methods: ['POST'])]
    public function create(Request $request): JsonResponse
    {
        try {
            $payload = $request->toArray();
        } catch (JsonException) {
            return new JsonResponse(['error' => 'Corps JSON invalide.'], Response::HTTP_BAD_REQUEST);
        }

        $name = $payload['name'] ?? null;
        $amount = $payload['amount'] ?? null;
        $currency = $payload['currency'] ?? 'EUR';
        if (!is_string($name) || !is_int($amount) || !is_string($currency)) {
            return new JsonResponse(
                ['error' => 'Attendu : {"name": string, "amount": int (centimes), "currency"?: string}.'],
                Response::HTTP_BAD_REQUEST,
            );
        }

        // L'identifiant est généré ICI (UUID v7, ordonnable) pour renvoyer Location.
        $id = Uuid::v7()->toRfc4122();

        try {
            $this->commandBus->dispatch(new CreateProductCommand($id, $name, $amount, $currency));
        } catch (DomainException $e) {
            return new JsonResponse(['error' => $e->getMessage()], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        return new JsonResponse(['id' => $id], Response::HTTP_CREATED, ['Location' => '/api/products/'.$id]);
    }

    #[Route('/api/products/{id}', name: 'catalog_product_get', methods: ['GET'])]
    public function get(string $id): JsonResponse
    {
        try {
            $view = $this->queryBus->ask(new GetProductQuery($id));
        } catch (ProductNotFound|InvalidProductId) {
            return new JsonResponse(['error' => 'Produit introuvable.'], Response::HTTP_NOT_FOUND);
        }
        if (!$view instanceof ProductView) {
            throw new \LogicException('GetProductQuery doit produire un ProductView.');
        }

        return new JsonResponse($view);
    }
}
EOF

# La recette ne charge que src/Controller/ : chaque contexte déclare ses routes.
cat > "$SK"/config/routes/catalog.yaml <<'EOF'
# Routes du contexte Catalog (attributs #[Route] des contrôleurs de sa couche UI).
catalog_http:
    resource:
        path: ../../src/Catalog/UI/Http/
        namespace: App\Catalog\UI\Http
    type: attribute
EOF
```

- [ ] **Step 2 : Mode api — ressource API Platform, provider, processor**

Enchaîner :

```bash
else
# Mode api : ressource API Platform sous forme de DTO (jamais l'entité). Le
# provider et le processor sont les seuls points de contact avec les bus.
mkdir -p "$SK"/src/Catalog/UI/Http/{Resource,State}
cat > "$SK"/src/Catalog/UI/Http/Resource/ProductResource.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\UI\Http\Resource;

use ApiPlatform\Metadata\ApiResource;
use ApiPlatform\Metadata\Get;
use ApiPlatform\Metadata\Post;
use App\Catalog\UI\Http\State\ProductProcessor;
use App\Catalog\UI\Http\State\ProductProvider;

/**
 * Représentation HTTP du produit. Découplée de l'agrégat : API Platform ne voit
 * jamais Doctrine ni le domaine, seulement ce DTO et ses provider/processor.
 */
#[ApiResource(
    shortName: 'Product',
    operations: [
        new Get(uriTemplate: '/products/{id}', provider: ProductProvider::class),
        new Post(uriTemplate: '/products', processor: ProductProcessor::class),
    ],
)]
final class ProductResource
{
    public ?string $id = null;

    public string $name = '';

    /** Montant en centimes. */
    public int $amount = 0;

    public string $currency = 'EUR';

    public ?string $createdAt = null;
}
EOF

cat > "$SK"/src/Catalog/UI/Http/State/ProductProvider.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\UI\Http\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProviderInterface;
use App\Catalog\Application\DTO\ProductView;
use App\Catalog\Application\Query\GetProductQuery;
use App\Catalog\Domain\Exception\InvalidProductId;
use App\Catalog\Domain\Exception\ProductNotFound;
use App\Catalog\UI\Http\Resource\ProductResource;
use App\Shared\Application\Query\QueryBus;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

/**
 * @implements ProviderInterface<ProductResource>
 */
final class ProductProvider implements ProviderInterface
{
    public function __construct(private readonly QueryBus $queryBus)
    {
    }

    /**
     * @param array<string, mixed> $uriVariables
     * @param array<string, mixed> $context
     */
    public function provide(Operation $operation, array $uriVariables = [], array $context = []): ?ProductResource
    {
        $id = $uriVariables['id'] ?? null;
        if (!is_string($id)) {
            throw new NotFoundHttpException('Produit introuvable.');
        }

        try {
            $view = $this->queryBus->ask(new GetProductQuery($id));
        } catch (ProductNotFound|InvalidProductId $e) {
            throw new NotFoundHttpException('Produit introuvable.', $e);
        }
        if (!$view instanceof ProductView) {
            throw new \LogicException('GetProductQuery doit produire un ProductView.');
        }

        $resource = new ProductResource();
        $resource->id = $view->id;
        $resource->name = $view->name;
        $resource->amount = $view->amount;
        $resource->currency = $view->currency;
        $resource->createdAt = $view->createdAt;

        return $resource;
    }
}
EOF

cat > "$SK"/src/Catalog/UI/Http/State/ProductProcessor.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Catalog\UI\Http\State;

use ApiPlatform\Metadata\Operation;
use ApiPlatform\State\ProcessorInterface;
use App\Catalog\Application\Command\CreateProductCommand;
use App\Catalog\Application\DTO\ProductView;
use App\Catalog\Application\Query\GetProductQuery;
use App\Catalog\UI\Http\Resource\ProductResource;
use App\Shared\Application\Command\CommandBus;
use App\Shared\Application\Query\QueryBus;
use App\Shared\Domain\Exception\DomainException;
use Symfony\Component\HttpKernel\Exception\UnprocessableEntityHttpException;
use Symfony\Component\Uid\Uuid;

/**
 * @implements ProcessorInterface<ProductResource, ProductResource>
 */
final class ProductProcessor implements ProcessorInterface
{
    public function __construct(
        private readonly CommandBus $commandBus,
        private readonly QueryBus $queryBus,
    ) {
    }

    /**
     * @param array<string, mixed> $uriVariables
     * @param array<string, mixed> $context
     */
    public function process(mixed $data, Operation $operation, array $uriVariables = [], array $context = []): ProductResource
    {
        if (!$data instanceof ProductResource) {
            throw new \LogicException('Ce processor ne traite que ProductResource.');
        }

        $id = Uuid::v7()->toRfc4122();
        try {
            $this->commandBus->dispatch(new CreateProductCommand($id, $data->name, $data->amount, $data->currency));
        } catch (DomainException $e) {
            throw new UnprocessableEntityHttpException($e->getMessage(), $e);
        }

        // Relecture par le bus de requête : la réponse reflète l'état persisté
        // (normalisation de la devise, date de création), pas le corps reçu.
        $view = $this->queryBus->ask(new GetProductQuery($id));
        if (!$view instanceof ProductView) {
            throw new \LogicException('GetProductQuery doit produire un ProductView.');
        }

        $data->id = $view->id;
        $data->name = $view->name;
        $data->amount = $view->amount;
        $data->currency = $view->currency;
        $data->createdAt = $view->createdAt;

        return $data;
    }
}
EOF

# API Platform ne scanne que src/ApiResource et src/Entity : on ajoute le dossier
# des ressources du contexte (fusionné avec api_platform.yaml de la recette).
cat > "$SK"/config/packages/api_platform_ddd.yaml <<'EOF'
# Dossiers de ressources des contextes bornés. Fusionné avec api_platform.yaml.
api_platform:
    mapping:
        paths:
            - '%kernel.project_dir%/src/Catalog/UI/Http/Resource'
EOF
fi  # WITH_FRONTEND
```

- [ ] **Step 3 : Vérifier la génération**

```bash
bash -n create-symfony-project.sh
S=/tmp/claude-1000/-media-shared-data-projects-symfony-docker-generator/516574fe-7cc9-42f9-a675-89900343752b/scratchpad
rm -rf "$S/t5" && mkdir -p "$S/t5" && cd "$S/t5"
G=/media/shared_data/projects/symfony-docker-generator/create-symfony-project.sh
bash "$G" f --ddd-example --no-build >/dev/null
ls f/docker/php/skeleton/src/Catalog/UI/Http/ f/docker/php/skeleton/config/routes/     # ProductController.php ; catalog.yaml
test ! -e f/docker/php/skeleton/config/packages/api_platform_ddd.yaml && echo "full : pas d'API Platform, OK"
bash "$G" a --ddd-example --frontend --no-build >/dev/null
ls a/docker/php/skeleton/src/Catalog/UI/Http/Resource a/docker/php/skeleton/src/Catalog/UI/Http/State    # ProductResource ; ProductProvider, ProductProcessor
test ! -e a/docker/php/skeleton/config/routes/catalog.yaml && echo "api : pas de routes.yaml, OK"
for f in $(find f a -path '*skeleton*' -name '*.php'); do php -l "$f" >/dev/null || echo "KO $f"; done
```

- [ ] **Step 4 : Vérifier par un build réel — mode full**

```bash
cd ~/dev && rm -rf ddd-t5f && bash "$G" ddd-t5f --ddd-example --no-build >/dev/null && cd ddd-t5f
make build 2>&1 | tail -2 && make up && make init 2>&1 | tail -4
make phpstan 2>&1 | tail -3 && make deptrac 2>&1 | tail -3 && make test 2>&1 | tail -3
docker compose exec --user dev backend php bin/console debug:router | grep catalog_product      # 2 routes
docker compose exec --user dev backend php bin/console make:migration --no-interaction | tail -2
make db-migrate 2>&1 | tail -2
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' -X POST localhost:8080/api/products \
     -H 'Content-Type: application/json' -d '{"name":"Clavier","amount":4990,"currency":"eur"}'
#   attendu : 201 (Location dans les en-têtes : ajouter -D - pour le voir)
ID=$(curl -s -X POST localhost:8080/api/products -H 'Content-Type: application/json' -d '{"name":"Souris","amount":1990}' | jq -r .id)
curl -s localhost:8080/api/products/$ID | jq .        # {"id":..., "name":"Souris", "amount":1990, "currency":"EUR", "createdAt":"..."}
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/api/products/0190f3a1-7c2b-7d3e-8f4a-5b6c7d8e9f00   # 404
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/api/products/pas-un-uuid                             # 404
curl -s -w ' %{http_code}\n' -X POST localhost:8080/api/products -H 'Content-Type: application/json' -d '{"name":"","amount":1}'      # {"error":"Nom de produit invalide : le nom est vide."} 422
curl -s -w ' %{http_code}\n' -X POST localhost:8080/api/products -H 'Content-Type: application/json' -d '{"name":"X","amount":"1"}'   # 400
docker compose down -v
```

- [ ] **Step 5 : Vérifier par un build réel — mode api**

```bash
cd ~/dev && rm -rf ddd-t5a && bash "$G" ddd-t5a --ddd-example --frontend --no-build >/dev/null && cd ddd-t5a
make build 2>&1 | tail -2 && make up && make init 2>&1 | tail -4
make phpstan 2>&1 | tail -3 && make deptrac 2>&1 | tail -3 && make test 2>&1 | tail -3
docker compose exec --user dev backend php bin/console debug:router | grep -i product    # _api_/products{._format}_post, _api_/products/{id}{._format}_get
docker compose exec --user dev backend php bin/console make:migration --no-interaction | tail -2 && make db-migrate 2>&1 | tail -2
ID=$(curl -s -X POST localhost:8080/api/products -H 'Content-Type: application/ld+json' -d '{"name":"Souris","amount":1990,"currency":"eur"}' | jq -r .id)
echo "$ID"                                            # un UUID
curl -s localhost:8080/api/products/$ID | jq '{name, amount, currency}'    # Souris, 1990, EUR
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/api/products/0190f3a1-7c2b-7d3e-8f4a-5b6c7d8e9f00   # 404
curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8080/api/products -H 'Content-Type: application/ld+json' -d '{"name":"","amount":1}'   # 422
docker compose down -v
```

Le service `frontend` démarre avec `make up` et affiche « Projet Vite absent » : c'est attendu, il n'est pas utilisé ici.

- [ ] **Step 6 : Commit**

```bash
git add create-symfony-project.sh
git commit -m "feat(ddd): UI du contexte Catalog — contrôleur JSON (full) ou ressource API Platform (api)"
```

---

### Task 6 : Squelette frontend (`--frontend --ddd`) — couches, ESLint boundaries, exemple TypeScript

**Files:**
- Modify: `create-symfony-project.sh` — `mkdir` (l. 283) ; nouvelle section `5.8d` après 5.8c (`docker/node/nginx.conf`) ; Makefile (`front-init`, `front-arch`) ; étape 6 (après `npm install`)

**Interfaces:**
- Consumes : `ESLINT_VERSION`, `ESLINT_BOUNDARIES_VERSION`, `TS_ESLINT_PARSER_VERSION` (Task 1, lus dans `.env`).
- Produces : `docker/node/skeleton/` ; `docker/node/apply-skeleton.sh` (hôte, idempotent, code retour 0 même si projet JS) ; script npm `lint:arch` ; cible `front-arch`.

- [ ] **Step 1 : Dossier**

Ligne 283, remplacer par :

```bash
(( WITH_FRONTEND )) && mkdir -p "$PROJECT_DIR/frontend" "$PROJECT_DIR/docker/node"
(( WITH_FRONTEND && WITH_DDD )) && mkdir -p "$PROJECT_DIR/docker/node/skeleton/src"/{domain,application,infrastructure,ui}
```

- [ ] **Step 2 : Section 5.8d — READMEs de couches et configuration ESLint**

Après le `EOF` de `docker/node/nginx.conf` (fin de 5.8c) et avant `# 5.9 Makefile`, insérer :

```bash
# -----------------------------------------------------------------------------
# 5.8d docker/node/skeleton — couches DDD côté front (--frontend --ddd)
# -----------------------------------------------------------------------------
# Appliqué SUR L'HÔTE par docker/node/apply-skeleton.sh, après `npm create vite`,
# car le framework et TypeScript ne sont connus qu'à ce moment-là. TypeScript
# uniquement : sans tsconfig.json, le script avertit et n'applique rien.
if (( WITH_FRONTEND && WITH_DDD )); then
FS=docker/node/skeleton

cat > "$FS"/src/domain/README.md <<'EOF'
# domain

Règles métier pures : entités, objets-valeur, erreurs, interfaces de dépôt.
Aucun import depuis `application`, `infrastructure`, `ui`, ni d'aucune bibliothèque.
EOF

cat > "$FS"/src/application/README.md <<'EOF'
# application

Cas d'usage : orchestrent le domaine à travers ses interfaces (dépôts, générateur d'identifiant).
Importent uniquement `domain`. Ne connaissent ni `fetch`, ni le DOM, ni le framework.
EOF

cat > "$FS"/src/infrastructure/README.md <<'EOF'
# infrastructure

Implémentations techniques des interfaces du domaine : appels HTTP vers l'API
(`VITE_API_URL`), stockage local, génération d'identifiants…
Importent `domain` et `application`.
EOF

cat > "$FS"/src/ui/README.md <<'EOF'
# ui

Composants et pages du framework choisi (React, Vue, Svelte…). C'est la seule
couche autorisée à importer `infrastructure` : elle assemble les dépendances
(composition root) et les passe aux cas d'usage.

Vérifier les dépendances : `make front-arch` (ESLint boundaries).
EOF

# Config ESLint SÉPARÉE de celle que le gabarit Vite a pu créer (eslint.config.js) :
# on ne modifie jamais un fichier généré par un outil tiers.
cat > "$FS"/eslint.boundaries.config.js <<'EOF'
// Règles de dépendance entre couches — lancer : npm run lint:arch (ou make front-arch)
// Fichier volontairement séparé d'eslint.config.js (gabarit Vite) pour ne pas le modifier.
import boundaries from 'eslint-plugin-boundaries';
import tsParser from '@typescript-eslint/parser';

export default [
  {
    files: ['src/**/*.ts', 'src/**/*.tsx'],
    languageOptions: {
      parser: tsParser,
      ecmaVersion: 'latest',
      sourceType: 'module',
    },
    plugins: { boundaries },
    settings: {
      'boundaries/elements': [
        { type: 'domain', pattern: 'src/domain/**' },
        { type: 'application', pattern: 'src/application/**' },
        { type: 'infrastructure', pattern: 'src/infrastructure/**' },
        { type: 'ui', pattern: 'src/ui/**' },
      ],
      // Résolution des imports sans extension (.ts) : même règle que Vite.
      'import/resolver': { node: { extensions: ['.js', '.ts', '.tsx'] } },
    },
    rules: {
      'boundaries/element-types': [
        'error',
        {
          default: 'disallow',
          rules: [
            { from: 'domain', allow: ['domain'] },
            { from: 'application', allow: ['domain', 'application'] },
            { from: 'infrastructure', allow: ['domain', 'application', 'infrastructure'] },
            // Sans conteneur d'injection, l'UI est la composition root : elle seule assemble l'infrastructure.
            { from: 'ui', allow: ['domain', 'application', 'infrastructure', 'ui'] },
          ],
        },
      ],
      // main.ts, vite-env.d.ts… ne sont dans aucune couche : on ne les juge pas.
      'boundaries/no-unknown': 'off',
      'boundaries/no-unknown-files': 'off',
    },
  },
];
EOF
```

- [ ] **Step 3 : Script hôte `apply-skeleton.sh`**

```bash
# Script HÔTE : cp local (les fichiers appartiennent au dev) + npm dans le conteneur.
cat > docker/node/apply-skeleton.sh <<'EOF'
#!/usr/bin/env bash
# =============================================================================
# Applique le squelette DDD frontend (docker/node/skeleton) sur frontend/.
# À lancer APRÈS `npm create vite` (make front-init le fait automatiquement).
# Idempotent. TypeScript uniquement.
# =============================================================================
set -Eeuo pipefail
cd "$(dirname "$0")/../.."

env_value() { { grep "^$1=" .env || true; } | cut -d= -f2; }

if [[ ! -f frontend/package.json ]]; then
  echo "✘ Projet Vite absent : lancez d'abord 'make front-init'." >&2
  exit 1
fi
if [[ ! -f frontend/tsconfig.json ]]; then
  echo "⚠ Projet Vite en JavaScript : le squelette DDD est TypeScript uniquement, rien n'est appliqué." >&2
  echo "  Recréez le projet avec un gabarit *-ts, puis relancez : bash docker/node/apply-skeleton.sh" >&2
  exit 0
fi
if [[ -f frontend/eslint.boundaries.config.js ]]; then
  echo "→ Squelette DDD déjà appliqué, rien à faire."
  exit 0
fi

echo "→ Copie des couches domain/application/infrastructure/ui"
cp -R docker/node/skeleton/. frontend/

echo "→ Installation d'ESLint + boundaries + parser TypeScript (versions figées dans .env)"
docker compose run --rm frontend npm install -D \
  "eslint@$(env_value ESLINT_VERSION)" \
  "eslint-plugin-boundaries@$(env_value ESLINT_BOUNDARIES_VERSION)" \
  "@typescript-eslint/parser@$(env_value TS_ESLINT_PARSER_VERSION)"
docker compose run --rm frontend npm pkg set 'scripts.lint:arch=eslint -c eslint.boundaries.config.js src'

echo "✔ Squelette DDD frontend appliqué. Vérifier : make front-arch"
EOF
chmod +x docker/node/apply-skeleton.sh
```

- [ ] **Step 4 : Exemple TypeScript (`--ddd-example`)**

```bash
if (( WITH_DDD_EXAMPLE )); then
mkdir -p "$FS"/src/domain/product "$FS"/src/application/product "$FS"/src/infrastructure/{http,id}

cat > "$FS"/src/domain/product/errors.ts <<'EOF'
// Erreurs métier du produit. Étendre Error garde les traces et permet `instanceof`.
export class InvalidProductId extends Error {
  constructor(value: string) {
    super(`"${value}" n'est pas un identifiant de produit valide (UUID attendu).`);
    this.name = 'InvalidProductId';
  }
}

export class InvalidProductName extends Error {
  constructor(reason: string) {
    super(`Nom de produit invalide : ${reason}.`);
    this.name = 'InvalidProductName';
  }
}

export class InvalidPrice extends Error {
  constructor(reason: string) {
    super(`Prix invalide : ${reason}.`);
    this.name = 'InvalidPrice';
  }
}

export class ProductNotFound extends Error {
  constructor(id: string) {
    super(`Produit "${id}" introuvable.`);
    this.name = 'ProductNotFound';
  }
}
EOF

cat > "$FS"/src/domain/product/ProductId.ts <<'EOF'
import { InvalidProductId } from './errors';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// Pas de "parameter properties" : le tsconfig de Vite active erasableSyntaxOnly.
export class ProductId {
  readonly value: string;

  private constructor(value: string) {
    this.value = value;
  }

  static fromString(value: string): ProductId {
    const normalized = value.trim().toLowerCase();
    if (!UUID.test(normalized)) {
      throw new InvalidProductId(value);
    }
    return new ProductId(normalized);
  }

  equals(other: ProductId): boolean {
    return other.value === this.value;
  }
}
EOF

cat > "$FS"/src/domain/product/ProductName.ts <<'EOF'
import { InvalidProductName } from './errors';

export const PRODUCT_NAME_MAX_LENGTH = 120;

export class ProductName {
  readonly value: string;

  private constructor(value: string) {
    this.value = value;
  }

  static fromString(value: string): ProductName {
    const trimmed = value.trim();
    if (trimmed === '') {
      throw new InvalidProductName('le nom est vide');
    }
    if (trimmed.length > PRODUCT_NAME_MAX_LENGTH) {
      throw new InvalidProductName(`${PRODUCT_NAME_MAX_LENGTH} caractères maximum`);
    }
    return new ProductName(trimmed);
  }

  equals(other: ProductName): boolean {
    return other.value === this.value;
  }
}
EOF

cat > "$FS"/src/domain/product/Price.ts <<'EOF'
import { InvalidPrice } from './errors';

// Montant en centimes + devise ISO 4217 : jamais de flottant pour de l'argent.
export class Price {
  readonly amount: number;
  readonly currency: string;

  constructor(amount: number, currency: string) {
    if (!Number.isInteger(amount) || amount < 0) {
      throw new InvalidPrice('le montant doit être un entier positif en centimes');
    }
    const upper = currency.toUpperCase();
    if (!/^[A-Z]{3}$/.test(upper)) {
      throw new InvalidPrice(`"${currency}" n'est pas un code devise ISO 4217`);
    }
    this.amount = amount;
    this.currency = upper;
  }

  equals(other: Price): boolean {
    return other.amount === this.amount && other.currency === this.currency;
  }
}
EOF

cat > "$FS"/src/domain/product/Product.ts <<'EOF'
import type { Price } from './Price';
import type { ProductId } from './ProductId';
import type { ProductName } from './ProductName';

export class Product {
  readonly id: ProductId;
  readonly name: ProductName;
  readonly price: Price;
  readonly createdAt: Date;

  constructor(id: ProductId, name: ProductName, price: Price, createdAt: Date) {
    this.id = id;
    this.name = name;
    this.price = price;
    this.createdAt = createdAt;
  }
}
EOF

cat > "$FS"/src/domain/product/ProductRepository.ts <<'EOF'
import type { Product } from './Product';
import type { ProductId } from './ProductId';

// Port : le domaine dit CE qu'il attend, l'infrastructure dit COMMENT (HTTP, mémoire…).
export interface ProductRepository {
  /** Crée le produit côté API et renvoie l'identifiant attribué. */
  create(name: string, amount: number, currency: string): Promise<ProductId>;
  /** @throws ProductNotFound */
  get(id: ProductId): Promise<Product>;
}
EOF

cat > "$FS"/src/application/product/createProduct.ts <<'EOF'
import type { ProductId } from '../../domain/product/ProductId';
import { ProductName } from '../../domain/product/ProductName';
import { Price } from '../../domain/product/Price';
import type { ProductRepository } from '../../domain/product/ProductRepository';

export interface CreateProductInput {
  name: string;
  amount: number;
  currency?: string;
}

// Cas d'usage : valide via le domaine AVANT d'appeler l'API, pour échouer vite
// et avec le même vocabulaire que le backend.
export function createProduct(products: ProductRepository) {
  return async (input: CreateProductInput): Promise<ProductId> => {
    const name = ProductName.fromString(input.name);
    const price = new Price(input.amount, input.currency ?? 'EUR');
    return products.create(name.value, price.amount, price.currency);
  };
}
EOF

cat > "$FS"/src/application/product/getProduct.ts <<'EOF'
import type { Product } from '../../domain/product/Product';
import { ProductId } from '../../domain/product/ProductId';
import type { ProductRepository } from '../../domain/product/ProductRepository';

export function getProduct(products: ProductRepository) {
  return (id: string): Promise<Product> => products.get(ProductId.fromString(id));
}
EOF

cat > "$FS"/src/infrastructure/http/HttpProductRepository.ts <<'EOF'
import { ProductNotFound } from '../../domain/product/errors';
import { Price } from '../../domain/product/Price';
import { Product } from '../../domain/product/Product';
import { ProductId } from '../../domain/product/ProductId';
import { ProductName } from '../../domain/product/ProductName';
import type { ProductRepository } from '../../domain/product/ProductRepository';

interface ProductPayload {
  id: string;
  name: string;
  amount: number;
  currency: string;
  createdAt: string;
}

// Adaptateur HTTP vers le backend généré (routes /api/products). VITE_API_URL est
// inliné au build par Vite : changer l'URL impose de reconstruire.
export class HttpProductRepository implements ProductRepository {
  private readonly baseUrl: string;

  constructor(baseUrl: string = String(import.meta.env.VITE_API_URL ?? '')) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
  }

  async create(name: string, amount: number, currency: string): Promise<ProductId> {
    const response = await fetch(`${this.baseUrl}/api/products`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ name, amount, currency }),
    });
    if (!response.ok) {
      throw new Error(`Création refusée par l'API (HTTP ${response.status}).`);
    }
    const body = (await response.json()) as { id: string };
    return ProductId.fromString(body.id);
  }

  async get(id: ProductId): Promise<Product> {
    const response = await fetch(`${this.baseUrl}/api/products/${id.value}`, {
      headers: { Accept: 'application/json' },
    });
    if (response.status === 404) {
      throw new ProductNotFound(id.value);
    }
    if (!response.ok) {
      throw new Error(`Lecture refusée par l'API (HTTP ${response.status}).`);
    }
    const payload = (await response.json()) as ProductPayload;
    return new Product(
      ProductId.fromString(payload.id),
      ProductName.fromString(payload.name),
      new Price(payload.amount, payload.currency),
      new Date(payload.createdAt),
    );
  }
}
EOF
fi  # WITH_DDD_EXAMPLE
fi  # WITH_FRONTEND && WITH_DDD
```

- [ ] **Step 5 : Makefile — `front-init` enchaîne l'application, cible `front-arch`**

Dans le bloc `if (( WITH_FRONTEND )); then cat <<'EOF'` de la section 5.9, la cible `front-init` devient conditionnelle. Remplacer :

```make
front-init: ## Crée le projet Vite en mode INTERACTIF (à lancer une seule fois)
	$(DC) run --rm frontend npm create vite@$(shell grep '^CREATE_VITE_VERSION=' .env | cut -d= -f2) .
```

par la fermeture du heredoc puis :

```bash
if (( WITH_DDD )); then
cat <<'EOF'
front-init: ## Crée le projet Vite (INTERACTIF) puis applique le squelette DDD
	$(DC) run --rm frontend npm create vite@$(shell grep '^CREATE_VITE_VERSION=' .env | cut -d= -f2) .
	bash docker/node/apply-skeleton.sh

front-arch: ## Vérifie les dépendances entre couches du front (ESLint boundaries)
	$(DC) exec frontend npm run lint:arch
EOF
else
cat <<'EOF'
front-init: ## Crée le projet Vite en mode INTERACTIF (à lancer une seule fois)
	$(DC) run --rm frontend npm create vite@$(shell grep '^CREATE_VITE_VERSION=' .env | cut -d= -f2) .
EOF
fi
cat <<'EOF'
```

et le heredoc reprend à `# --- Images déployables du frontend ...`.

- [ ] **Step 6 : Étape 6 du générateur**

Dans le bloc `if (( WITH_FRONTEND )); then` de l'étape 6 (l. 1544-1550), après `docker compose run --rm frontend npm install`, ajouter :

```bash
    if (( WITH_DDD )); then
      info "Application du squelette DDD frontend…"
      bash docker/node/apply-skeleton.sh
    fi
```

- [ ] **Step 7 : Vérifier la génération**

```bash
bash -n create-symfony-project.sh
S=/tmp/claude-1000/-media-shared-data-projects-symfony-docker-generator/516574fe-7cc9-42f9-a675-89900343752b/scratchpad
rm -rf "$S/t6" && mkdir -p "$S/t6" && cd "$S/t6"
G=/media/shared_data/projects/symfony-docker-generator/create-symfony-project.sh
bash "$G" a --frontend --no-build >/dev/null && test ! -d a/docker/node/skeleton && (cd a && make help | grep -c front-arch)   # 0
bash "$G" b --frontend --ddd --no-build >/dev/null && find b/docker/node/skeleton -type f | sort            # 4 README + eslint.boundaries.config.js
test -x b/docker/node/apply-skeleton.sh && bash -n b/docker/node/apply-skeleton.sh && echo "script hôte OK"
(cd b && make help | grep -E 'front-init|front-arch')
bash "$G" c --frontend --ddd-example --no-build >/dev/null && find c/docker/node/skeleton/src -name '*.ts' | wc -l   # 9
node --check c/docker/node/skeleton/eslint.boundaries.config.js && echo "config ESLint : syntaxe OK"
```

- [ ] **Step 8 : Vérifier par un build réel (front vanilla-ts, non interactif)**

```bash
cd ~/dev && rm -rf ddd-t6 && bash "$G" ddd-t6 --frontend --ddd-example --no-build >/dev/null && cd ddd-t6
make build 2>&1 | tail -1 && make up
docker compose run --rm frontend npm create vite@$(grep '^CREATE_VITE_VERSION=' .env | cut -d= -f2) . -- --template vanilla-ts
docker compose run --rm frontend npm install 2>&1 | tail -1
bash docker/node/apply-skeleton.sh 2>&1 | tail -3           # "✔ Squelette DDD frontend appliqué"
ls frontend/src                                             # application domain infrastructure ui main.ts style.css ...
docker compose run --rm frontend npx tsc --noEmit -p tsconfig.json && echo "TypeScript OK"
make front-arch 2>&1 | tail -3                              # aucune erreur ESLint
bash docker/node/apply-skeleton.sh                          # "déjà appliqué" (idempotence)
```

**Preuve que le garde-fou mord** :

```bash
echo "import { HttpProductRepository } from '../../infrastructure/http/HttpProductRepository'; export const leak = HttpProductRepository;" > frontend/src/domain/product/leak.ts
make front-arch 2>&1 | grep -c 'boundaries/element-types'   # ≥ 1, et make sort en erreur
rm frontend/src/domain/product/leak.ts
make front-arch 2>&1 | tail -2                              # propre
docker compose down -v
```

Cas JavaScript : sur un projet neuf, créer avec `--template vanilla` (sans TS), lancer `bash docker/node/apply-skeleton.sh` : attendu, l'avertissement « Projet Vite en JavaScript », code retour 0, `frontend/src/domain` absent.

- [ ] **Step 9 : Commit**

```bash
git add create-symfony-project.sh
git commit -m "feat(ddd): squelette frontend TypeScript par couches, ESLint boundaries, script apply-skeleton"
```

---

### Task 7 : Documentation — README du générateur, README généré, invariants `CLAUDE.md`

**Files:**
- Modify: `README.md` (tableau des options l. 78-84, nouvelle section après « Les deux modes de génération » l. 90-100, « Le Makefile » l. 292, « Arborescence générée » l. 184)
- Modify: `create-symfony-project.sh` — README généré (section 5.10, avant `## Versions`)
- Modify: `.claude/CLAUDE.md` (section Invariants)

- [ ] **Step 1 : README du générateur — options**

Dans le tableau des options (l. 80-83), après la ligne `--frontend`, ajouter :

```markdown
| `--ddd` | Architecture DDD par contextes bornés : `src/Shared/`, bus Messenger command/query/event, mapping Doctrine XML, Deptrac. Côté front (avec `--frontend`) : couches + ESLint boundaries |
| `--ddd-example` | Ajoute un contexte borné d'exemple complet (`Catalog`, agrégat `Product`, tests). Implique `--ddd` |
```

- [ ] **Step 2 : README du générateur — nouvelle section**

Après la section « Les deux modes de génération » (avant `## Gestion des versions`), insérer :

```markdown
## Architecture DDD (`--ddd`)

Par défaut, le projet généré est un squelette Symfony standard. Avec `--ddd`, le
code applicatif est organisé par **contextes bornés** :

```
backend/src/
├── Shared/                       socle commun à tous les contextes
│   ├── Domain/                   AggregateRoot, DomainEvent, ValueObject, DomainException
│   ├── Application/              CommandBus, QueryBus, EventBus (interfaces + marqueurs)
│   └── Infrastructure/Messenger/ implémentations sur trois bus Messenger
└── <Contexte>/
    ├── Domain/                   entités, objets-valeur, événements, ports (interfaces de dépôt)
    ├── Application/              commandes, requêtes, handlers, DTO de lecture
    ├── Infrastructure/           Doctrine (mapping XML, types, dépôts), doubles de test
    └── UI/                       HTTP (contrôleur ou ressource API Platform), CLI
```

Ce découpage est **contraint**, pas suggéré :

- **Deptrac** (`make deptrac`) interdit à `Domain` toute dépendance, à `Application`
  toute dépendance vendor (hors interfaces PSR), et réserve Doctrine, Symfony et
  API Platform à `Infrastructure` et `UI`.
- Les **handlers** sont reconnus par leurs interfaces marqueurs et tagués dans
  `services.yaml` : la couche Application n'importe rien de Messenger.
- Le **mapping Doctrine est en XML** : les entités du domaine ne portent aucun attribut.
- Côté front (`--frontend --ddd`), les dossiers `domain/`, `application/`,
  `infrastructure/`, `ui/` sont créés et **ESLint boundaries** (`make front-arch`)
  impose le même sens de dépendance. TypeScript uniquement.

`--ddd-example` ajoute un contexte `Catalog` complet (agrégat `Product`, commande,
requête, dépôts Doctrine et mémoire, UI, tests PHPUnit) qui sert de modèle à
copier, puis se supprime en une commande.

### Comment c'est appliqué

Le générateur ne peut pas écrire dans `backend/` avant `symfony new`. Il produit
donc un **gabarit** `docker/php/skeleton/`, monté en lecture seule dans le
conteneur, que `init-symfony` copie après les recettes Flex : ses fichiers ont le
dernier mot. Le même mécanisme, côté hôte, applique `docker/node/skeleton/` après
`npm create vite` (`docker/node/apply-skeleton.sh`).

### PHPStan, avec ou sans `--ddd`

Tout projet généré embarque **PHPStan niveau max + strict-rules** (extensions
Symfony et Doctrine incluses explicitement, sans plugin Composer) : `make phpstan`.
Le squelette nu passe à zéro erreur ; c'est vérifié à chaque évolution du générateur.
```

Dans la section « Le Makefile » (l. 292), ajouter les cibles `phpstan`, `test`, `deptrac` (avec `--ddd`), `front-arch` (avec `--frontend --ddd`) au tableau existant, en respectant son format. Dans « Arborescence générée » (l. 184), ajouter `docker/php/skeleton/` et, sous condition, `docker/node/skeleton/` + `apply-skeleton.sh`. Dans « Gestion des versions », ajouter PHPStan, Deptrac (`deptrac/deptrac`, ex-`qossmic`) et les paquets npm ESLint à la liste des sources résolues.

- [ ] **Step 3 : README généré — section Architecture**

Dans le heredoc **non quoté** du README généré (section 5.10), avant `## Versions`, insérer (motif identique à `FRONTDOC` : sous-heredoc **quoté**, donc backticks non échappés) :

```bash
$( (( WITH_DDD )) && cat <<'DDDDOC'

## Architecture

Le code est organisé par **contextes bornés** (DDD) : `src/Shared/` + un dossier
par contexte, chacun découpé en `Domain`, `Application`, `Infrastructure`, `UI`.
Sens de dépendance autorisé, vérifié par Deptrac :

```
UI ──────────┐
Infrastructure ─┴─▶ Application ─▶ Domain
```

- **Domain** : aucune dépendance (ni Doctrine, ni Symfony). Objets-valeur auto-validés,
  agrégats qui enregistrent leurs événements, exceptions métier, ports (interfaces).
- **Application** : commandes et requêtes, handlers. Dépend du domaine et des
  interfaces PSR uniquement. Les handlers implémentent `CommandHandler` /
  `QueryHandler` et sont tagués automatiquement (`services.yaml`, `_instanceof`).
- **Infrastructure** : Doctrine (mapping XML dans `Infrastructure/Doctrine/Mapping`,
  types DBAL, dépôts), bus Messenger, doubles de test.
- **UI** : HTTP (contrôleurs ou ressources API Platform), CLI. Traduit les
  exceptions métier en codes HTTP.

Trois bus Messenger : `command.bus` (transactionnel), `query.bus`, `event.bus`.

```bash
make phpstan    # analyse statique niveau max
make deptrac    # dépendances entre couches
make test       # PHPUnit
```

### Ajouter un contexte

1. Copier `src/Catalog` (si généré) ou créer `src/<Contexte>/{Domain,Application,Infrastructure,UI}`.
2. Déclarer son mapping dans `config/packages/doctrine_<contexte>.yaml` (modèle : `doctrine_catalog.yaml`).
3. Mode full : déclarer ses routes dans `config/routes/<contexte>.yaml`. Mode api : ajouter
   son dossier `UI/Http/Resource` dans `config/packages/api_platform_ddd.yaml`.
4. Générer la migration : `make sh` puis `bin/console make:migration`, puis `make db-migrate`.

Le contexte d'exemple se retire ainsi :
`rm -r src/Catalog tests/Catalog config/packages/doctrine_catalog.yaml config/routes/catalog.yaml`
(ou `config/packages/api_platform_ddd.yaml` en mode api).
DDDDOC
)
```

Si `WITH_FRONTEND && WITH_DDD`, ajouter dans le sous-heredoc `FRONTDOC` existant un paragraphe final : « Le front est organisé en `src/{domain,application,infrastructure,ui}` ; `make front-arch` vérifie les dépendances (ESLint boundaries). TypeScript uniquement. » — via un second sous-heredoc conditionnel `$( (( WITH_DDD )) && cat <<'FRONTDDDDOC' ... )` placé juste après `FRONTDOC`.

- [ ] **Step 4 : `.claude/CLAUDE.md` — invariants et pièges**

Dans la section « Invariants », ajouter :

```markdown
- **Le gabarit `docker/php/skeleton/` est appliqué par `init-symfony` dans le
  conteneur, après `symfony new` et les `composer require`.** Jamais écrit dans
  `backend/` avant le build : `symfony new` exige un dossier vide et les recettes
  Flex écraseraient `services.yaml`. Il est toujours généré (il porte `phpstan.neon`) ;
  `--ddd` et `--ddd-example` l'enrichissent.
- **PHPStan niveau max est systématique, DDD ne l'est pas.** Le squelette Symfony nu
  doit passer à zéro erreur : toute modification du générateur se vérifie par un
  `make phpstan` réel sur un projet sans `--ddd`.
- **Le squelette DDD frontend est TypeScript uniquement.** Sans `tsconfig.json`,
  `apply-skeleton.sh` avertit et ne fait rien (code 0). Ne pas ajouter de variante JS.
- **Deptrac : `deptrac/deptrac`, pas `qossmic/deptrac`** (figé en 2.0). La couche
  `Vendor` exclut volontairement `Psr\` : les interfaces PSR sont admises en Application.
- **`services.yaml` est le seul fichier de configuration écrasé.** Doctrine, Messenger
  et API Platform sont complétés par des fichiers `*_ddd.yaml` / `*_catalog.yaml`
  fusionnés par le composant Config : ne pas revenir à une réécriture de `doctrine.yaml`.
```

Dans « Pièges d'écriture du script », ajouter : « Le gabarit backend est produit par des heredocs **quotés** un par fichier (`cat > "$SK"/... <<'EOF'`) ; le README généré imbrique des sous-heredocs quotés (`FRONTDOC`, `DDDDOC`) dans un heredoc non quoté : y écrire des backticks sans échappement. »

Dans « Vérifier une modification », ajouter les quatre combinaisons `--ddd`, `--ddd-example`, `--frontend --ddd`, `--frontend --ddd-example` et le contrôle « sans `--ddd`, `docker/php/skeleton/` ne contient que `phpstan.neon` ».

- [ ] **Step 5 : Vérifier**

```bash
bash -n create-symfony-project.sh
S=/tmp/claude-1000/-media-shared-data-projects-symfony-docker-generator/516574fe-7cc9-42f9-a675-89900343752b/scratchpad
rm -rf "$S/t7" && mkdir -p "$S/t7" && cd "$S/t7"
G=/media/shared_data/projects/symfony-docker-generator/create-symfony-project.sh
bash "$G" p --no-build >/dev/null && grep -c '## Architecture' p/README.md                  # 0
bash "$G" q --ddd-example --frontend --no-build >/dev/null && grep -c '## Architecture' q/README.md   # 1
grep -n '\\`' q/README.md | head                                                             # aucun backtick échappé littéral
grep -c -- '--ddd' /media/shared_data/projects/symfony-docker-generator/README.md            # ≥ 4
```

- [ ] **Step 6 : Commit**

```bash
git add README.md .claude/CLAUDE.md create-symfony-project.sh
git commit -m "docs: architecture DDD optionnelle, PHPStan systématique, nouveaux invariants"
```

---

### Task 8 : Matrice de vérification finale et revue

**Files:** aucun nouveau ; correction éventuelle de `create-symfony-project.sh`.

- [ ] **Step 1 : Matrice `--no-build`**

```bash
bash -n create-symfony-project.sh
S=/tmp/claude-1000/-media-shared-data-projects-symfony-docker-generator/516574fe-7cc9-42f9-a675-89900343752b/scratchpad
rm -rf "$S/t8" && mkdir -p "$S/t8" && cd "$S/t8"
G=/media/shared_data/projects/symfony-docker-generator/create-symfony-project.sh
for args in "" "--frontend" "--ddd" "--ddd-example" "--frontend --ddd" "--frontend --ddd-example"; do
  n="p$(echo "$args" | tr -d ' -')"; bash "$G" "$n" $args --no-build >"$n.log" 2>&1 || { echo "ÉCHEC $args"; tail -5 "$n.log"; }
  ( cd "$n" && make help >/dev/null ) || echo "make help KO : $args"
  printf '%-28s skeleton=%s node-skel=%s deptrac=%s front-arch=%s\n' "[$args]" \
    "$(find "$n"/docker/php/skeleton -type f | wc -l)" \
    "$([[ -d $n/docker/node/skeleton ]] && echo oui || echo non)" \
    "$(grep -c '^deptrac:' "$n"/Makefile)" "$(grep -c '^front-arch:' "$n"/Makefile)"
done
```

Attendu :

| args | skeleton (fichiers) | node-skel | deptrac | front-arch |
|---|---|---|---|---|
| (vide) | 1 | non | 0 | 0 |
| `--frontend` | 1 | non | 0 | 0 |
| `--ddd` | 15 | non | 1 | 0 |
| `--ddd-example` | 46 (15 + 21 Catalog + 7 tests + doctrine_catalog + contrôleur + routes) | non | 1 | 0 |
| `--frontend --ddd` | 15 | oui (5 fichiers) | 1 | 1 |
| `--frontend --ddd-example` | 48 (15 + 21 + 7 + doctrine_catalog + 3 UI api + api_platform_ddd) | oui (14 fichiers) | 1 | 1 |

Ajuster les compteurs exacts après la première exécution, puis les figer dans ce tableau.

- [ ] **Step 2 : Alignement `make help` et absence de fuite**

```bash
for n in "$S"/t8/p*/; do awk 'length($0) > 0 && /^  / && length($1) > 20 {print FILENAME": "$0}' <(cd "$n" && make help); done   # rien
grep -rn 'skeleton' "$S"/t8/p/docker-compose.yml | wc -l      # 1 (le montage, même sans --ddd)
diff <(cd "$S"/t8/p && find . -type f | sort) <(cd "$S"/t8/pfrontend && find . -type f | sort) | grep -v 'node\|override\|frontend'   # rien d'inattendu
```

- [ ] **Step 3 : Revue de code**

Lancer la revue du dépôt (`/code-review` ou `superpowers:requesting-code-review`) sur `develop..feature/ddd-skeleton`. Corriger, régénérer la matrice, committer.

- [ ] **Step 4 : Mettre à jour le spec si la réalité a divergé**

Relire `docs/superpowers/specs/2026-09-13-ddd-skeleton-design.md` et y refléter tout écart constaté pendant les builds réels (excludePaths PHPStan, `readonly` des embeddables, motifs `exclude` de `services.yaml`). Commit `docs(spec): aligner sur l'implémentation`.

- [ ] **Step 5 : Fin de branche**

Ne pas fusionner ici : suivre `superpowers:finishing-a-development-branch` (git-flow : `git flow feature finish ddd-skeleton`, puis release `v2.1.0`). Le bump de version, le tag, la release GitHub et l'entrée « Historique des versions » du README sont **hors de ce plan**.
