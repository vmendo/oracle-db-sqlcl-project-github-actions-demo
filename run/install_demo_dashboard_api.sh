#!/bin/bash

# Install the read-only ORDS API used by the static demo dashboard.

set -euo pipefail

RED='\033[31m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

INSTALL_SQL="$DEMO_HOME/ords/install_demo_dashboard_api.sql"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}ERROR: $1 not found in PATH${NC}"
    exit 1
  }
}

usage() {
  cat <<EOF
Usage: $0 [dev|prod|both]

Installs the read-only ORDS demo dashboard API.

Defaults:
  DEV connection:  $DB_CONNECT_DEV
  PROD connection: $DB_CONNECT_PROD
  Schema:          $SCHEMA_NAME

Configurable with environment variables:
  DB_CONNECT_DEV
  DB_CONNECT_PROD
  SCHEMA_NAME
  DEMO_DASHBOARD_DEV_API_BASE_URL
  DEMO_DASHBOARD_PROD_API_BASE_URL
EOF
}

health_url() {
  local api_base_url="$1"
  if [[ -z "$api_base_url" ]]; then
    return 0
  fi

  printf '%s/health/\n' "${api_base_url%/}"
}

print_access_link() {
  local label="$1"
  local api_base_url="$2"

  if [[ -n "$api_base_url" ]]; then
    echo -e "${GREEN}$label health endpoint:${NC} $(health_url "$api_base_url")"
  else
    echo -e "${YELLOW}$label health endpoint not printed because the API base URL is not configured.${NC}"
    echo -e "${YELLOW}Set DEMO_DASHBOARD_${label}_API_BASE_URL to https://<adb-ords-host>/ords/$(echo "$SCHEMA_NAME" | tr '[:upper:]' '[:lower:]')/demo-dashboard${NC}"
  fi
}

install_api() {
  local label="$1"
  local connection="$2"
  local api_base_url="$3"

  echo ""
  echo -e "${BLUE}Installing ORDS demo dashboard API in $label using $connection...${NC}"
  sql -name "$connection" <<EOF
@$INSTALL_SQL "$SCHEMA_NAME"
exit
EOF
  echo -e "${GREEN}$label ORDS demo dashboard API installed.${NC}"
  print_access_link "$label" "$api_base_url"
}

target="${1:-both}"

case "$target" in
  -h|--help)
    usage
    exit 0
    ;;
  dev|prod|both)
    ;;
  *)
    usage
    exit 1
    ;;
esac

require_cmd sql

if [[ ! -f "$INSTALL_SQL" ]]; then
  echo -e "${RED}ERROR: installer not found: $INSTALL_SQL${NC}"
  exit 1
fi

echo ""
echo -e "${BLUE}SQLcl Projects demo dashboard API installer${NC}"
echo -e "${YELLOW}Schema: $SCHEMA_NAME${NC}"

if [[ "$target" == "dev" || "$target" == "both" ]]; then
  install_api "DEV" "$DB_CONNECT_DEV" "$DEMO_DASHBOARD_DEV_API_BASE_URL"
fi

if [[ "$target" == "prod" || "$target" == "both" ]]; then
  install_api "PROD" "$DB_CONNECT_PROD" "$DEMO_DASHBOARD_PROD_API_BASE_URL"
fi

echo ""
echo -e "${GREEN}Dashboard API installation complete.${NC}"
echo -e "${BLUE}Generate or refresh frontend/config.local.js with:${NC}"
echo -e "${YELLOW}$SCRIPT_DIR/configure_demo_dashboard.sh${NC}"
