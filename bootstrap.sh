#!/usr/bin/env bash
set -Eeuo pipefail

: "${WORKSPACE:=/workspace}"
: "${PRIVATE_REPO_OWNER:?PRIVATE_REPO_OWNER fehlt}"
: "${PRIVATE_REPO_NAME:?PRIVATE_REPO_NAME fehlt}"
: "${PRIVATE_REPO_REF:=main}"
: "${GITHUB_PAT:?GITHUB_PAT fehlt}"

LOG_FILE="$WORKSPACE/vast-bootstrap.log"
mkdir -p "$WORKSPACE"
exec > >(tee -a "$LOG_FILE") 2>&1

C_RESET=$'\033[0m'
C_RED=$'\033[1;31m'
C_GREEN=$'\033[1;32m'
C_YELLOW=$'\033[1;33m'
C_BLUE=$'\033[1;34m'
C_CYAN=$'\033[1;36m'

ts(){ date '+%H:%M:%S'; }
info(){ echo -e "${C_BLUE}[BOOTSTRAP][INFO]${C_RESET}  [$(ts)] $*"; }
warn(){ echo -e "${C_YELLOW}[BOOTSTRAP][WARN]${C_RESET}  [$(ts)] $*"; }
err(){ echo -e "${C_RED}[BOOTSTRAP][ERROR]${C_RESET} [$(ts)] $*" >&2; }
ok(){ echo -e "${C_GREEN}[BOOTSTRAP][OK]${C_RESET}    [$(ts)] $*"; }
section(){ echo; echo -e "${C_CYAN}========== $* ==========${C_RESET}"; }

trap 'err "Abbruch in Zeile $LINENO: $BASH_COMMAND"' ERR

API_BASE="https://api.github.com/repos/${PRIVATE_REPO_OWNER}/${PRIVATE_REPO_NAME}/contents"
AUTH_HEADER="Authorization: token ${GITHUB_PAT}"
ACCEPT_HEADER="Accept: application/vnd.github.v3.raw"

fetch_private_file() {
  local repo_path="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  info "Hole ${repo_path} -> ${dest}"
  curl -fsSL \
    -H "$AUTH_HEADER" \
    -H "$ACCEPT_HEADER" \
    "${API_BASE}/${repo_path}?ref=${PRIVATE_REPO_REF}" \
    -o "$dest"
  ok "Geladen: ${repo_path}"
}

start_banner() {
  echo -e "${C_GREEN}############################################################${C_RESET}"
  echo -e "${C_GREEN}#                      BOOTSTRAP START                     #${C_RESET}"
  echo -e "${C_GREEN}############################################################${C_RESET}"
}

end_banner() {
  echo -e "${C_GREEN}############################################################${C_RESET}"
  echo -e "${C_GREEN}#                       BOOTSTRAP END                      #${C_RESET}"
  echo -e "${C_GREEN}############################################################${C_RESET}"
}

start_banner
section "CONFIG"
info "WORKSPACE=$WORKSPACE"
info "PRIVATE_REPO_OWNER=$PRIVATE_REPO_OWNER"
info "PRIVATE_REPO_NAME=$PRIVATE_REPO_NAME"
info "PRIVATE_REPO_REF=$PRIVATE_REPO_REF"

section "DOWNLOAD"
info "Repo-Layout erwartet: provisioning.sh, model-list.sh, configs/config.json, configs/ui-config.json"
fetch_private_file "provisioning.sh" "$WORKSPACE/provisioning.sh"
fetch_private_file "model-list.sh" "$WORKSPACE/model-list.sh"
fetch_private_file "configs/config.json" "$WORKSPACE/config.json"
fetch_private_file "configs/ui-config.json" "$WORKSPACE/ui-config.json"

section "PERMISSIONS"
chmod +x "$WORKSPACE/provisioning.sh" "$WORKSPACE/model-list.sh"
ok "Ausführungsrechte gesetzt"

section "CHECK"
[[ -s "$WORKSPACE/provisioning.sh" ]] || { err "provisioning.sh ist leer oder fehlt"; exit 1; }
[[ -s "$WORKSPACE/model-list.sh" ]] || { err "model-list.sh ist leer oder fehlt"; exit 1; }
[[ -s "$WORKSPACE/config.json" ]] || { err "config.json ist leer oder fehlt"; exit 1; }
[[ -s "$WORKSPACE/ui-config.json" ]] || { err "ui-config.json ist leer oder fehlt"; exit 1; }
ok "Alle Dateien vorhanden"

section "START PROVISIONING"
info "Starte provisioning.sh"
exec "$WORKSPACE/provisioning.sh"
