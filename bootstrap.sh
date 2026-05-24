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
JSON_ACCEPT="Accept: application/vnd.github+json"

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

api_json() {
  local repo_path="$1"
  curl -fsSL \
    -H "$AUTH_HEADER" \
    -H "$JSON_ACCEPT" \
    "${API_BASE}/${repo_path}?ref=${PRIVATE_REPO_REF}"
}

dump_meta() {
  local label="$1" meta="$2"
  err "Diagnose für $label:"
  echo "$meta" | jq .
}

download_from_meta() {
  local repo_path="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"

  section "DOWNLOAD $repo_path"
  info "Schritt 1/3: GitHub-Metadaten abrufen"
  local meta path size download_url type
  if ! meta="$(api_json "$repo_path")"; then
    err "GitHub-API fehlgeschlagen für $repo_path (ref=$PRIVATE_REPO_REF)"
    return 1
  fi

  type="$(jq -r '.type // empty' <<<"$meta")"
  path="$(jq -r '.path // empty' <<<"$meta")"
  size="$(jq -r '.size // empty' <<<"$meta")"
  download_url="$(jq -r '.download_url // empty' <<<"$meta")"

  if [[ "$type" != "file" || -z "$path" || -z "$download_url" || "$download_url" == "null" ]]; then
    dump_meta "$repo_path" "$meta"
    err "Ungültige GitHub-Metadaten für $repo_path"
    return 1
  fi

  ok "GitHub bestätigt: path=$path size=$size"

  info "Schritt 2/3: Dateiinhalt von download_url holen"
  if ! curl -fsSL -H "$AUTH_HEADER" "$download_url" -o "$dest"; then
    err "Download fehlgeschlagen für $repo_path via download_url"
    return 1
  fi

  info "Schritt 3/3: lokale Datei prüfen"
  [[ -s "$dest" ]] || { err "Datei wurde geladen, ist aber leer: $dest"; return 1; }

  ok "Fertig: $repo_path -> $dest"
}

start_banner

section "CONFIG"
info "WORKSPACE=$WORKSPACE"
info "PRIVATE_REPO_OWNER=$PRIVATE_REPO_OWNER"
info "PRIVATE_REPO_NAME=$PRIVATE_REPO_NAME"
info "PRIVATE_REPO_REF=$PRIVATE_REPO_REF"

section "ROOT CHECK"
info "GitHub Root-Inhalt für ref=$PRIVATE_REPO_REF"
if root_json="$(api_json "")"; then
  jq -r '.[] | "- \(.type): \(.path)"' <<<"$root_json" || true
else
  warn "Root-Inhalt konnte nicht geladen werden"
fi

section "DOWNLOAD PLAN"
info "Erwartete Dateien:"
info "  1) provisioning.sh"
info "  2) model-list.sh"
info "  3) configs/config.json"
info "  4) configs/ui-config.json"

download_from_meta "provisioning.sh" "$WORKSPACE/provisioning.sh"
download_from_meta "model-list.sh" "$WORKSPACE/model-list.sh"
download_from_meta "configs/config.json" "$WORKSPACE/config.json"
download_from_meta "configs/ui-config.json" "$WORKSPACE/ui-config.json"

section "PERMISSIONS"
chmod +x "$WORKSPACE/provisioning.sh" "$WORKSPACE/model-list.sh"
ok "Ausführungsrechte gesetzt"

section "LOCAL CHECK"
[[ -s "$WORKSPACE/provisioning.sh" ]] || { err "provisioning.sh fehlt oder ist leer"; exit 1; }
[[ -s "$WORKSPACE/model-list.sh" ]] || { err "model-list.sh fehlt oder ist leer"; exit 1; }
[[ -s "$WORKSPACE/config.json" ]] || { err "config.json fehlt oder ist leer"; exit 1; }
[[ -s "$WORKSPACE/ui-config.json" ]] || { err "ui-config.json fehlt oder ist leer"; exit 1; }
ok "Alle Dateien sind vorhanden und nicht leer"

section "START PROVISIONING"
info "Starte provisioning.sh"
end_banner
exec "$WORKSPACE/provisioning.sh"
