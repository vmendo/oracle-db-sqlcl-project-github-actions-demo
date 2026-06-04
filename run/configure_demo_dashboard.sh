#!/bin/bash

# Generate the local static dashboard configuration.

set -euo pipefail

RED='\033[31m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

CONFIG_FILE="$DEMO_HOME/frontend/config.local.js"

prompt_required() {
  local prompt_text="$1"
  local value

  while true; do
    read -r -p "$prompt_text: " value
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return
    fi
    echo -e "${YELLOW}Value required.${NC}"
  done
}

prompt_default() {
  local prompt_text="$1"
  local default_value="$2"
  local value

  if [[ -n "$default_value" ]]; then
    read -r -p "$prompt_text [$default_value]: " value
    printf '%s' "${value:-$default_value}"
  else
    prompt_required "$prompt_text"
  fi
}

normalize_api_url() {
  local value="$1"
  local schema_path

  schema_path="$(echo "$SCHEMA_NAME" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  value="${value%/}"

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
  printf '%s/health/' "${1%/}"
}

echo ""
echo -e "${BLUE}Static dashboard configuration${NC}"
echo -e "${YELLOW}Project: $PROJECT_NAME${NC}"
echo -e "${YELLOW}Schema:  $SCHEMA_NAME${NC}"
echo ""
echo "For Autonomous Database, use the browser URL from Database Actions or APEX."
echo "You can paste either the ADB host or a longer URL that already contains /ords/."
echo "The script normalizes it to this API base URL format:"
echo ""
echo "  https://<adb-ords-host>/ords/$(echo "$SCHEMA_NAME" | tr '[:upper:]' '[:lower:]')/demo-dashboard"
echo ""

dev_api_base_url="$(normalize_api_url "$(prompt_default "DEV Autonomous ORDS host or API URL" "$DEMO_DASHBOARD_DEV_API_BASE_URL")")"
prod_api_base_url="$(normalize_api_url "$(prompt_default "PROD Autonomous ORDS host or API URL" "$DEMO_DASHBOARD_PROD_API_BASE_URL")")"
refresh_seconds="$(prompt_default "Auto-refresh seconds" "$DEMO_DASHBOARD_REFRESH_SECONDS")"

if [[ ! "$refresh_seconds" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}ERROR: Auto-refresh seconds must be a non-negative integer.${NC}"
  exit 1
fi

cat > "$CONFIG_FILE" <<EOF
window.DEMO_DASHBOARD_CONFIG = {
  projectName: "$(js_escape "$PROJECT_NAME")",
  schemaName: "$(js_escape "$SCHEMA_NAME")",
  refreshSeconds: $refresh_seconds,
  devApiBaseUrl: "$(js_escape "$dev_api_base_url")",
  prodApiBaseUrl: "$(js_escape "$prod_api_base_url")"
};
EOF

echo ""
echo -e "${GREEN}Wrote $CONFIG_FILE${NC}"
echo -e "${GREEN}DEV health endpoint:  $(health_url "$dev_api_base_url")${NC}"
echo -e "${GREEN}PROD health endpoint: $(health_url "$prod_api_base_url")${NC}"
echo ""
echo -e "${BLUE}Open the dashboard with:${NC}"
echo "cd $DEMO_HOME/frontend"
echo "python3 -m http.server $DEMO_DASHBOARD_PORT"
echo ""
echo -e "${BLUE}Then browse:${NC}"
echo "http://localhost:$DEMO_DASHBOARD_PORT"
