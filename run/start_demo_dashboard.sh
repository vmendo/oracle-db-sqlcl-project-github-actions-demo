#!/bin/bash

# Configure on first run and start the static demo dashboard.

set -euo pipefail

RED='\033[31m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

CONFIG_FILE="$DEMO_HOME/frontend/config.local.js"
FRONTEND_DIR="$DEMO_HOME/frontend"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}ERROR: $1 not found in PATH${NC}"
    exit 1
  }
}

usage() {
  cat <<EOF
Usage: $0 [--reconfigure] [--port PORT] [--bind ADDRESS]

Starts the static SQLcl Projects demo dashboard.

First run:
  Prompts for DEV and PROD Autonomous ORDS URLs.
  Writes frontend/config.local.js.
  Starts a local HTTP server.

Later runs:
  Reuses frontend/config.local.js and starts the HTTP server directly.

Options:
  --reconfigure   Regenerate frontend/config.local.js before starting.
  --port PORT     Override DEMO_DASHBOARD_PORT for this run.
  --bind ADDRESS  Override DEMO_DASHBOARD_BIND for this run.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reconfigure)
      RECONFIGURE=true
      shift
      ;;
    --port)
      if [[ $# -lt 2 ]]; then
        echo -e "${RED}ERROR: --port requires a value.${NC}"
        exit 1
      fi
      DEMO_DASHBOARD_PORT="$2"
      shift 2
      ;;
    --bind)
      if [[ $# -lt 2 ]]; then
        echo -e "${RED}ERROR: --bind requires a value.${NC}"
        exit 1
      fi
      DEMO_DASHBOARD_BIND="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo -e "${RED}ERROR: Unknown option: $1${NC}"
      usage
      exit 1
      ;;
  esac
done

RECONFIGURE="${RECONFIGURE:-false}"

if [[ ! "$DEMO_DASHBOARD_PORT" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}ERROR: DEMO_DASHBOARD_PORT must be a positive integer.${NC}"
  exit 1
fi

if [[ ! -d "$FRONTEND_DIR" ]]; then
  echo -e "${RED}ERROR: Frontend directory not found: $FRONTEND_DIR${NC}"
  exit 1
fi

require_cmd python3

if [[ "$RECONFIGURE" == "true" || ! -f "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${YELLOW}Dashboard configuration not found: $CONFIG_FILE${NC}"
  else
    echo -e "${YELLOW}Regenerating dashboard configuration: $CONFIG_FILE${NC}"
  fi

  "$SCRIPT_DIR/configure_demo_dashboard.sh"
else
  echo -e "${GREEN}Using existing dashboard configuration: $CONFIG_FILE${NC}"
fi

if [[ "$DEMO_DASHBOARD_BIND" == "127.0.0.1" || "$DEMO_DASHBOARD_BIND" == "localhost" ]]; then
  BROWSER_URL="http://localhost:$DEMO_DASHBOARD_PORT"
else
  BROWSER_URL="http://$DEMO_DASHBOARD_BIND:$DEMO_DASHBOARD_PORT"
fi

echo ""
echo -e "${BLUE}Starting SQLcl Projects demo dashboard${NC}"
echo -e "${GREEN}Open this URL in your browser:${NC} $BROWSER_URL"
echo -e "${YELLOW}Press Ctrl+C to stop the server.${NC}"
echo ""

cd "$FRONTEND_DIR"
python3 -m http.server "$DEMO_DASHBOARD_PORT" --bind "$DEMO_DASHBOARD_BIND"
