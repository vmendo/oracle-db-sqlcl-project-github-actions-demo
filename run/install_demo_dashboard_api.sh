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
CONFIG_FILE="$DEMO_HOME/frontend/config.local.js"

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
  DEMO_DASHBOARD_REFRESH_SECONDS
EOF
}

prompt_default() {
  local prompt_text="$1"
  local default_value="$2"
  local value

  if [[ -n "$default_value" ]]; then
    read -r -p "$prompt_text [$default_value]: " value
    printf '%s' "${value:-$default_value}"
  else
    read -r -p "$prompt_text: " value
    printf '%s' "$value"
  fi
}

normalize_api_url() {
  local value="$1"
  local schema_path

  schema_path="$(echo "$SCHEMA_NAME" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  value="${value%/}"

  if [[ -z "$value" ]]; then
    printf ''
    return
  fi

  if [[ ! "$value" =~ ^https?:// ]]; then
    value="https://$value"
  fi

  if [[ "$value" =~ ^(https?://[^/]+)/ords(/.*)?$ ]]; then
    printf '%s/ords/%s/demo-dashboard' "${BASH_REMATCH[1]}" "$schema_path"
    return
  fi

  printf '%s/ords/%s/demo-dashboard' "$value" "$schema_path"
}

js_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

health_url() {
  local api_base_url="$1"
  if [[ -z "$api_base_url" ]]; then
    return 0
  fi

  printf '%s/health/\n' "${api_base_url%/}"
}

explain_autonomous_url() {
  echo ""
  echo -e "${BLUE}Autonomous Database ORDS URL help${NC}"
  echo "Use the browser URL from Database Actions or APEX for each Autonomous Database."
  echo "You can paste either:"
  echo ""
  echo "  https://<adb-ords-host>/"
  echo "  https://<adb-ords-host>/ords/sql-developer"
  echo "  https://<adb-ords-host>/ords/r/..."
  echo ""
  echo "The script will normalize it to:"
  echo ""
  echo "  https://<adb-ords-host>/ords/$(echo "$SCHEMA_NAME" | tr '[:upper:]' '[:lower:]')/demo-dashboard"
  echo ""
}

collect_api_url() {
  local label="$1"
  local current_value="$2"
  local answer

  answer="$(prompt_default "$label Autonomous ORDS host or API URL" "$current_value")"
  normalize_api_url "$answer"
}

write_frontend_config() {
  local dev_api_base_url="$1"
  local prod_api_base_url="$2"

  if [[ -z "$dev_api_base_url" || -z "$prod_api_base_url" ]]; then
    echo -e "${YELLOW}frontend/config.local.js was not generated because one API URL is missing.${NC}"
    echo -e "${YELLOW}Run $SCRIPT_DIR/configure_demo_dashboard.sh later if needed.${NC}"
    return
  fi

  cat > "$CONFIG_FILE" <<EOF
window.DEMO_DASHBOARD_CONFIG = {
  projectName: "$(js_escape "$PROJECT_NAME")",
  schemaName: "$(js_escape "$SCHEMA_NAME")",
  refreshSeconds: $DEMO_DASHBOARD_REFRESH_SECONDS,
  devApiBaseUrl: "$(js_escape "$dev_api_base_url")",
  prodApiBaseUrl: "$(js_escape "$prod_api_base_url")"
};
EOF

  echo -e "${GREEN}Wrote frontend config: $CONFIG_FILE${NC}"
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

if [[ ! "$DEMO_DASHBOARD_REFRESH_SECONDS" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}ERROR: DEMO_DASHBOARD_REFRESH_SECONDS must be a non-negative integer.${NC}"
  exit 1
fi

echo ""
echo -e "${BLUE}SQLcl Projects demo dashboard API installer${NC}"
echo -e "${YELLOW}Schema: $SCHEMA_NAME${NC}"

explain_autonomous_url

if [[ "$target" == "dev" || "$target" == "both" ]]; then
  DEMO_DASHBOARD_DEV_API_BASE_URL="$(collect_api_url "DEV" "$DEMO_DASHBOARD_DEV_API_BASE_URL")"
fi

if [[ "$target" == "prod" || "$target" == "both" ]]; then
  DEMO_DASHBOARD_PROD_API_BASE_URL="$(collect_api_url "PROD" "$DEMO_DASHBOARD_PROD_API_BASE_URL")"
fi

export DEMO_DASHBOARD_DEV_API_BASE_URL
export DEMO_DASHBOARD_PROD_API_BASE_URL

if [[ "$target" == "dev" || "$target" == "both" ]]; then
  install_api "DEV" "$DB_CONNECT_DEV" "$DEMO_DASHBOARD_DEV_API_BASE_URL"
fi

if [[ "$target" == "prod" || "$target" == "both" ]]; then
  install_api "PROD" "$DB_CONNECT_PROD" "$DEMO_DASHBOARD_PROD_API_BASE_URL"
fi

echo ""
echo -e "${GREEN}Dashboard API installation complete.${NC}"
write_frontend_config "$DEMO_DASHBOARD_DEV_API_BASE_URL" "$DEMO_DASHBOARD_PROD_API_BASE_URL"
echo ""
echo -e "${BLUE}Open the dashboard with:${NC}"
echo "cd $DEMO_HOME/frontend"
echo "python3 -m http.server $DEMO_DASHBOARD_PORT"
echo ""
echo -e "${BLUE}Then browse:${NC}"
echo "http://localhost:$DEMO_DASHBOARD_PORT"
