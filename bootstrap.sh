#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# bootstrap.sh | Version: 2026-05-26.03 (Vollständig inkl. Features)
# -----------------------------------------------------------------------------
set -Eeuo pipefail

: "${WORKSPACE:=/workspace}"
: "${PRIVATE_REPO_OWNER:?"PRIVATE_REPO_OWNER fehlt"}"
: "${PRIVATE_REPO_NAME:?"PRIVATE_REPO_NAME fehlt"}"
: "${PRIVATE_REPO_REF:=main}"
: "${GITHUB_PAT:?"GITHUB_PAT fehlt"}"

mkdir -p "$WORKSPACE"
LOG_FILE="$WORKSPACE/vast-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

C_RESET=$'\033[0m'
C_RED=$'\033[1;31m'
C_GREEN=$'\033[1;32m'
C_YELLOW=$'\033[1;33m'
C_BLUE=$'\033[1;34m'
C_CYAN=$'\033[1;36m'

ts(){ date -u '+%H:%M:%S'; }
info(){ echo -e "${C_BLUE}[BOOTSTRAP][INFO]${C_RESET}   [$(ts)] $*"; }
warn(){ echo -e "${C_YELLOW}[BOOTSTRAP][WARN]${C_RESET}   [$(ts)] $*"; }
err(){ echo -e "${C_RED}[BOOTSTRAP][ERROR]${C_RESET}  [$(ts)] $*" >&2; }
ok(){ echo -e "${C_GREEN}[BOOTSTRAP][OK]${C_RESET}     [$(ts)] $*"; }
section(){ echo; echo -e "${C_CYAN}========== $* ==========${C_RESET}"; }

trap 'err "Abbruch in Zeile $LINENO: $BASH_COMMAND"' ERR

API_BASE="https://api.github.com/repos/${PRIVATE_REPO_OWNER}/${PRIVATE_REPO_NAME}/contents"
AUTH_HEADER="Authorization: token $GITHUB_PAT"
JSON_ACCEPT="Accept: application/vnd.github+json"
RAW_ACCEPT="Accept: application/vnd.github.v3.raw"

info "WORKSPACE=$WORKSPACE"
info "PRIVATE_REPO_OWNER=$PRIVATE_REPO_OWNER"
info "PRIVATE_REPO_NAME=$PRIVATE_REPO_NAME"
info "PRIVATE_REPO_REF=$PRIVATE_REPO_REF"

start_banner() {
  echo -e "${C_GREEN}############################################################${C_RESET}"
  echo -e "${C_GREEN}#                       BOOTSTRAP START                    #${C_RESET}"
  echo -e "${C_GREEN}############################################################${C_RESET}"
}

end_banner() {
  echo -e "${C_GREEN}############################################################${C_RESET}"
  echo -e "${C_GREEN}#                        BOOTSTRAP END                     #${C_RESET}"
  echo -e "${C_GREEN}############################################################${C_RESET}"
}

api_json() {
  local repo_path="$1"
  curl -fsSL -H "$AUTH_HEADER" -H "$JSON_ACCEPT" "${API_BASE}/${repo_path}?ref=${PRIVATE_REPO_REF}"
}

download_file_direct() {
  local repo_path="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"

  section "DOWNLOAD $repo_path"
  info "Rufe Datei via GitHub-Raw-API ab..."
  
  if ! curl -fsSL -H "$AUTH_HEADER" -H "$RAW_ACCEPT" "${API_BASE}/${repo_path}?ref=${PRIVATE_REPO_REF}" -o "$dest"; then
    err "Direct Download fehlgeschlagen für $repo_path"
    return 1
  fi

  # FIX: Konvertierung sofort nach dem Download
  sed -i 's/\r$//' "$dest"

  [[ -s "$dest" ]] || { err "Datei extrahiert, aber leer: $dest"; return 1; }
  ok "Erfolgreich geladen: $repo_path -> $dest ($(stat -c %s "$dest" 2>/dev/null || echo 0) bytes)"
}

start_banner

section "ROOT CHECK"
info "Prüfe Repository-Struktur für Ref: $PRIVATE_REPO_REF"
root_json="$(api_json "" 2>/dev/null || echo "")"
if [[ -n "$root_json" ]]; then
  echo "$root_json" | jq -r '.[] | "- \(.type): \(.path)"'
else
  warn "Root-Verzeichnisstruktur konnte nicht abgefragt werden."
fi

section "DOWNLOAD PLAN"
download_file_direct "provisioning.sh" "$WORKSPACE/provisioning.sh"
download_file_direct "model-list.sh" "$WORKSPACE/model-list.sh"
download_file_direct "configs/config.json" "$WORKSPACE/config.json"
download_file_direct "configs/ui-config.json" "$WORKSPACE/ui-config.json"

section "PERMISSIONS"
chmod +x "$WORKSPACE/provisioning.sh"
ok "Ausführungsrechte für provisioning.sh gesetzt"

section "LOCAL CHECK"
[[ -s "$WORKSPACE/provisioning.sh" ]] || { err "provisioning.sh fehlt"; exit 1; }
[[ -s "$WORKSPACE/model-list.sh" ]] || { err "model-list.sh fehlt"; exit 1; }
ok "Integritätsprüfung bestanden"

section "PREP ENVIRONMENT"
export WORKSPACE PRIVATE_REPO_OWNER PRIVATE_REPO_NAME PRIVATE_REPO_REF

section "START PROVISIONING"
info "Übergebe Kontrolle an provisioning.sh via exec"
end_banner
echo ""

exec "$WORKSPACE/provisioning.sh" "$@"