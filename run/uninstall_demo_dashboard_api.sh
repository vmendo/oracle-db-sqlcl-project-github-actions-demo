#!/bin/bash

# Remove the read-only ORDS API used by the static demo dashboard.

set -euo pipefail

RED='\033[31m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

UNINSTALL_SQL="$DEMO_HOME/ords/uninstall_demo_dashboard_api.sql"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}ERROR: $1 not found in PATH${NC}"
    exit 1
  }
}

usage() {
  cat <<EOF
Usage: $0 [dev|prod|both]

Removes the read-only ORDS demo dashboard API.

Defaults:
  DEV connection:  $DB_CONNECT_DEV
  PROD connection: $DB_CONNECT_PROD
  Schema:          $SCHEMA_NAME
EOF
}

uninstall_api() {
  local label="$1"
  local connection="$2"

  echo ""
  echo -e "${BLUE}Removing ORDS demo dashboard API from $label using $connection...${NC}"
  sql -name "$connection" <<EOF
@$UNINSTALL_SQL "$SCHEMA_NAME"
exit
EOF
  echo -e "${GREEN}$label ORDS demo dashboard API removed.${NC}"
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

if [[ ! -f "$UNINSTALL_SQL" ]]; then
  echo -e "${RED}ERROR: uninstaller not found: $UNINSTALL_SQL${NC}"
  exit 1
fi

echo ""
echo -e "${BLUE}SQLcl Projects demo dashboard API uninstaller${NC}"
echo -e "${YELLOW}Schema: $SCHEMA_NAME${NC}"

if [[ "$target" == "dev" || "$target" == "both" ]]; then
  uninstall_api "DEV" "$DB_CONNECT_DEV"
fi

if [[ "$target" == "prod" || "$target" == "both" ]]; then
  uninstall_api "PROD" "$DB_CONNECT_PROD"
fi

echo ""
echo -e "${GREEN}Dashboard API removal complete.${NC}"
