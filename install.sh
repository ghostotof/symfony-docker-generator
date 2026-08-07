#!/usr/bin/env bash
#
# =============================================================================
#  install.sh — installe `create-symfony-project` dans le PATH
# -----------------------------------------------------------------------------
#  Crée un lien symbolique vers create-symfony-project.sh dans un répertoire du
#  PATH, afin de pouvoir appeler la commande depuis n'importe où :
#
#      create-symfony-project mon-projet --frontend
#
#  Un lien symbolique (et non une copie) est utilisé volontairement : le script
#  reste modifiable dans son dépôt, et toute mise à jour (git pull, édition)
#  est immédiatement effective sans réinstallation.
#
#  Destination par défaut : ~/.local/bin, qui est le répertoire standard XDG
#  pour les exécutables utilisateur. Aucun sudo n'est donc nécessaire.
#
#  Usage :
#    ./install.sh              Installe dans ~/.local/bin
#    ./install.sh --system     Installe dans /usr/local/bin (demande sudo)
#    ./install.sh --uninstall  Retire le lien
# =============================================================================

set -Eeuo pipefail

# --- Affichage ----------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'
else
  C_RESET=""; C_OK=""; C_WARN=""; C_ERR=""
fi
ok()   { printf '%s ✔ %s %s\n' "$C_OK"   "$C_RESET" "$*"; }
warn() { printf '%s ⚠ %s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
die()  { printf '%s ✘ %s %s\n' "$C_ERR"  "$C_RESET" "$*" >&2; exit 1; }

# --- Paramètres ---------------------------------------------------------------
CMD_NAME="create-symfony-project"
# Résolution du chemin ABSOLU du script source : l'installation doit fonctionner
# quel que soit le répertoire courant au moment de l'appel.
SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC_DIR}/${CMD_NAME}.sh"

BIN_DIR="${HOME}/.local/bin"
USE_SUDO=""
UNINSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --system)    BIN_DIR="/usr/local/bin"; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)   sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           die "Option inconnue : $1" ;;
  esac
done

DEST="${BIN_DIR}/${CMD_NAME}"

# Une installation système exige les droits d'écriture sur /usr/local/bin.
if [[ "$BIN_DIR" == "/usr/local/bin" && ! -w "$BIN_DIR" ]]; then
  command -v sudo >/dev/null || die "Droits insuffisants sur $BIN_DIR et sudo est absent."
  USE_SUDO="sudo"
fi

# --- Désinstallation ----------------------------------------------------------
if (( UNINSTALL )); then
  [[ -e "$DEST" || -L "$DEST" ]] || die "Rien à désinstaller : $DEST est absent."
  $USE_SUDO rm -f "$DEST"
  ok "Lien supprimé : $DEST"
  exit 0
fi

# --- Vérifications ------------------------------------------------------------
[[ -f "$SRC" ]] || die "Script introuvable : $SRC (install.sh doit être placé à côté)."

# On rend la source exécutable : le lien hérite des permissions de la cible.
chmod +x "$SRC" 2>/dev/null || warn "Impossible de rendre $SRC exécutable."

$USE_SUDO mkdir -p "$BIN_DIR"

# Un lien préexistant est remplacé (`-f`), ce qui rend le script rejouable.
if [[ -e "$DEST" || -L "$DEST" ]]; then
  warn "Remplacement de l'entrée existante : $DEST"
fi
$USE_SUDO ln -sfn "$SRC" "$DEST"
ok "Installé : $DEST -> $SRC"

# --- Vérification du PATH -----------------------------------------------------
# ~/.local/bin est dans le PATH par défaut sur la plupart des distributions
# récentes, mais pas toutes. On vérifie plutôt que de le supposer.
if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
  # Détection du fichier de configuration selon le shell de l'utilisateur.
  case "$(basename "${SHELL:-bash}")" in
    zsh)  RC="${HOME}/.zshrc" ;;
    fish) RC="${HOME}/.config/fish/config.fish" ;;
    *)    RC="${HOME}/.bashrc" ;;
  esac

  warn "$BIN_DIR n'est pas dans votre PATH."
  printf '\n  Ajoutez cette ligne à %s :\n\n' "$RC"
  if [[ "$RC" == *"fish"* ]]; then
    printf '      fish_add_path %s\n\n' "$BIN_DIR"
  else
    printf '      export PATH="%s:$PATH"\n\n' "$BIN_DIR"
  fi
  printf '  Puis rechargez votre shell :  source %s\n\n' "$RC"
else
  # Le PATH est correct : on confirme que la commande répond réellement.
  if command -v "$CMD_NAME" >/dev/null 2>&1; then
    ok "Commande disponible : $CMD_NAME"
  else
    warn "Le lien existe mais la commande n'est pas résolue. Ouvrez un nouveau terminal."
  fi
  printf '\n  Essayez :  %s mon-projet --frontend\n\n' "$CMD_NAME"
fi
