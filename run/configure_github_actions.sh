#!/bin/bash

# Configure GitHub Actions secrets for the MyApp SQLcl Projects demo.

set -euo pipefail

RED='\033[31m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

GITHUB_REPOSITORY="$GITHUB_USER/$GITHUB_REPO"
MAX_SECRET_BYTES=49152

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}ERROR: $1 not found in PATH${NC}"
    exit 1
  }
}

prompt_default() {
  local prompt_text="$1"
  local default_value="$2"
  local answer

  read -r -p "$prompt_text [$default_value]: " answer
  printf '%s' "${answer:-$default_value}"
}

prompt_required() {
  local prompt_text="$1"
  local answer

  while true; do
    read -r -p "$prompt_text: " answer
    if [[ -n "$answer" ]]; then
      printf '%s' "$answer"
      return
    fi
    echo -e "${YELLOW}Value is required.${NC}" >&2
  done
}

prompt_password() {
  local password
  local confirm_password

  while true; do
    read -r -s -p "Target database password: " password
    echo "" >&2
    read -r -s -p "Confirm target database password: " confirm_password
    echo "" >&2

    if [[ -z "$password" ]]; then
      echo -e "${YELLOW}Password is required.${NC}" >&2
    elif [[ "$password" != "$confirm_password" ]]; then
      echo -e "${YELLOW}Passwords do not match. Try again.${NC}" >&2
    else
      printf '%s' "$password"
      return
    fi
  done
}

normalize_path() {
  local input_path="$1"
  printf '%s' "${input_path/#\~/$HOME}"
}

encode_wallet() {
  local wallet_zip="$1"
  local output_file="$2"

  if base64 --help 2>/dev/null | grep -q -- '-w'; then
    base64 -w 0 "$wallet_zip" > "$output_file"
  else
    base64 "$wallet_zip" | tr -d '\n' > "$output_file"
  fi
}

list_wallet_tns_aliases() {
  local wallet_zip="$1"

  unzip -p "$wallet_zip" tnsnames.ora 2>/dev/null \
    | awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*=/ {
          alias_name = $0
          sub(/^[[:space:]]*/, "", alias_name)
          sub(/[[:space:]]*=.*/, "", alias_name)
          print alias_name
        }
      ' \
    | sort -u
}

prompt_tns_alias() {
  local aliases_text="$1"
  local default_alias="$2"
  local selected_alias
  local alias_found

  if [[ -n "$aliases_text" ]]; then
    echo "" >&2
    echo -e "${BLUE}Wallet TNS aliases:${NC}" >&2
    printf '%s\n' "$aliases_text" | sed 's/^/  - /' >&2
  fi

  while true; do
    if [[ -n "$default_alias" ]]; then
      selected_alias="$(prompt_default "Target database wallet TNS alias" "$default_alias")"
    else
      selected_alias="$(prompt_required "Target database wallet TNS alias")"
    fi

    if [[ -z "$aliases_text" ]]; then
      printf '%s' "$selected_alias"
      return
    fi

    alias_found=false
    while IFS= read -r alias_name; do
      if [[ "$selected_alias" == "$alias_name" ]]; then
        alias_found=true
        break
      fi
    done <<< "$aliases_text"

    if [[ "$alias_found" == "true" ]]; then
      printf '%s' "$selected_alias"
      return
    fi

    echo -e "${YELLOW}Alias not found in wallet. Choose one of the listed aliases.${NC}" >&2
  done
}

echo ""
echo -e "${BLUE}This script configures GitHub Actions for SQLcl Project validation.${NC}"
echo -e "${BLUE}Repository:        $GITHUB_REPOSITORY${NC}"
echo -e "${BLUE}Default schema:    $SCHEMA_NAME${NC}"
echo ""

require_cmd gh
require_cmd base64
require_cmd wc
require_cmd unzip

if ! gh auth status >/dev/null 2>&1; then
  echo -e "${RED}ERROR: GitHub CLI is not authenticated.${NC}"
  echo -e "${YELLOW}Run: gh auth login${NC}"
  exit 1
fi

if [[ -n "${TARGET_WALLET_ZIP_DEFAULT:-}" ]]; then
  wallet_zip="$(normalize_path "$(prompt_default "Path to Autonomous Database wallet ZIP" "$TARGET_WALLET_ZIP_DEFAULT")")"
else
  wallet_zip="$(normalize_path "$(prompt_required "Path to Autonomous Database wallet ZIP")")"
fi

if [[ ! -f "$wallet_zip" ]]; then
  echo -e "${RED}ERROR: wallet ZIP not found: $wallet_zip${NC}"
  exit 1
fi

wallet_aliases="$(list_wallet_tns_aliases "$wallet_zip")"
default_alias="$(printf '%s\n' "$wallet_aliases" | grep -i '_high$' | head -n 1 || true)"
if [[ -z "$default_alias" ]]; then
  default_alias="$(printf '%s\n' "$wallet_aliases" | head -n 1 || true)"
fi

target_connect_string="$(prompt_tns_alias "$wallet_aliases" "$default_alias")"
target_user="$(prompt_default "Target database user" "$SCHEMA_NAME")"
target_password="$(prompt_password)"

wallet_b64_file="$(mktemp)"
trap 'rm -f "$wallet_b64_file"' EXIT

encode_wallet "$wallet_zip" "$wallet_b64_file"
wallet_b64_bytes="$(wc -c < "$wallet_b64_file" | tr -d ' ')"

if (( wallet_b64_bytes > MAX_SECRET_BYTES )); then
  echo -e "${RED}ERROR: base64 wallet secret is too large for a GitHub Actions secret.${NC}"
  echo -e "${YELLOW}Encoded wallet size: $wallet_b64_bytes bytes${NC}"
  echo -e "${YELLOW}GitHub secret limit used by this script: $MAX_SECRET_BYTES bytes${NC}"
  echo -e "${YELLOW}Use an encrypted file or an external secure download mechanism instead.${NC}"
  exit 1
fi

echo ""
echo -e "${BLUE}Values to configure:${NC}"
echo "  Repository:                  $GITHUB_REPOSITORY"
echo "  TARGET_DB_USER:              $target_user"
echo "  TARGET_DB_CONNECT_STRING:    $target_connect_string"
echo "  TARGET_DB_WALLET_ZIP_B64:    $wallet_b64_bytes bytes"
echo "  TARGET_DB_PASSWORD:          [hidden]"
echo ""
read -r -p "Overwrite repository secrets now? [y/N]: " confirm

case "$confirm" in
  y|Y|yes|YES)
    ;;
  *)
    echo -e "${YELLOW}Aborted. No GitHub values were changed.${NC}"
    exit 0
    ;;
esac

echo ""
echo -e "${BLUE}Configuring GitHub secrets...${NC}"
printf '%s' "$target_user" | gh secret set TARGET_DB_USER --repo "$GITHUB_REPOSITORY"
printf '%s' "$target_password" | gh secret set TARGET_DB_PASSWORD --repo "$GITHUB_REPOSITORY"
printf '%s' "$target_connect_string" | gh secret set TARGET_DB_CONNECT_STRING --repo "$GITHUB_REPOSITORY"
gh secret set TARGET_DB_WALLET_ZIP_B64 --repo "$GITHUB_REPOSITORY" < "$wallet_b64_file"

echo ""
echo -e "${GREEN}GitHub Actions configuration completed.${NC}"
echo ""
echo -e "${BLUE}Configured repository secrets:${NC}"
gh secret list --repo "$GITHUB_REPOSITORY" | grep -E '^TARGET_DB_(USER|PASSWORD|CONNECT_STRING|WALLET_ZIP_B64)[[:space:]]' || true
