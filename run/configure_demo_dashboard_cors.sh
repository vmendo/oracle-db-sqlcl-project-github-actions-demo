#!/bin/bash

# Configure CORS origins for the read-only ORDS dashboard module.

set -euo pipefail

RED='\033[31m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

CORS_SQL="$DEMO_HOME/ords/configure_demo_dashboard_cors.sql"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}ERROR: $1 not found in PATH${NC}"
    exit 1
  }
}

usage() {
  cat <<EOF
Usage: $0 [dev|prod|both]

Configures CORS for the read-only ORDS demo dashboard API.

Defaults:
  DEV connection:    $DB_CONNECT_DEV
  PROD connection:   $DB_CONNECT_PROD
  Schema:            $SCHEMA_NAME
  Allowed origins:   $(default_allowed_origins)

Override allowed origins with:
  DEMO_DASHBOARD_ALLOWED_ORIGINS="http://localhost:8088,http://127.0.0.1:8088"
EOF
}

default_allowed_origins() {
  if [[ -n "$DEMO_DASHBOARD_ALLOWED_ORIGINS" ]]; then
    printf '%s' "$DEMO_DASHBOARD_ALLOWED_ORIGINS"
    return
  fi

  printf 'http://localhost:%s,http://127.0.0.1:%s' "$DEMO_DASHBOARD_PORT" "$DEMO_DASHBOARD_PORT"
}

configure_cors() {
  local label="$1"
  local connection="$2"
  local origins="$3"

  echo ""
  echo -e "${BLUE}Configuring ORDS dashboard CORS in $label using $connection...${NC}"
  sql -name "$connection" <<EOF
@$CORS_SQL "$SCHEMA_NAME" "$origins"
exit
EOF
  echo -e "${GREEN}$label CORS configured for: $origins${NC}"
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

if [[ ! -f "$CORS_SQL" ]]; then
  echo -e "${RED}ERROR: CORS SQL script not found: $CORS_SQL${NC}"
  exit 1
fi

origins="$(default_allowed_origins)"

echo ""
echo -e "${BLUE}SQLcl Projects demo dashboard CORS configuration${NC}"
echo -e "${YELLOW}Schema: $SCHEMA_NAME${NC}"
echo -e "${YELLOW}Allowed origins: $origins${NC}"

if [[ "$target" == "dev" || "$target" == "both" ]]; then
  configure_cors "DEV" "$DB_CONNECT_DEV" "$origins"
fi

if [[ "$target" == "prod" || "$target" == "both" ]]; then
  configure_cors "PROD" "$DB_CONNECT_PROD" "$origins"
fi

echo ""
echo -e "${GREEN}Dashboard CORS configuration complete.${NC}"
