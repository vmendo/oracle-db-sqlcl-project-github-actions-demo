#!/bin/bash

# Capture a database development cycle after the developer manually changes DEV.
# This script intentionally stops at project stage. Release, artifact, and deploy
# are left for GitHub Actions in a later phase.

set -euo pipefail

RED='\033[31m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

if [[ $# -ne 1 ]]; then
  echo -e "${RED}Usage: $0 <cycle_name>${NC}"
  echo -e "${RED}Examples:${NC}"
  echo -e "${RED}  $0 base_release${NC}"
  echo -e "${RED}  $0 v1_changes${NC}"
  echo -e "${RED}  $0 v2_changes${NC}"
  exit 1
fi

CYCLE_NAME="$1"
CYCLE_SLUG="$(echo "$CYCLE_NAME" | tr '[:upper:] ' '[:lower:]_' | sed 's/[^a-z0-9_]/_/g; s/_\+/_/g; s/^_//; s/_$//')"
if [[ -z "$CYCLE_SLUG" ]]; then
  echo -e "${RED}ERROR: cycle_name produced an empty branch suffix.${NC}"
  exit 1
fi

BRANCH_NAME="dev_${CYCLE_SLUG}"
PROJECT_DIR="$PROJECTS_HOME/$PROJECT_NAME"
CONFIG_FILE="$PROJECT_DIR/.dbtools/project.config.json"
PROJECT_CONFIG_BACKUP=""

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}ERROR: $1 not found in PATH${NC}"
    exit 1
  }
}

configure_git_identity() {
  git config user.name "$GIT_AUTHOR_NAME"
  git config user.email "$GIT_AUTHOR_EMAIL"
}

backup_project_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}ERROR: project config not found: $CONFIG_FILE${NC}"
    exit 1
  fi

  PROJECT_CONFIG_BACKUP="$(mktemp)"
  cp "$CONFIG_FILE" "$PROJECT_CONFIG_BACKUP"
}

restore_project_config() {
  if [[ -n "${PROJECT_CONFIG_BACKUP:-}" && -f "$PROJECT_CONFIG_BACKUP" && -f "$CONFIG_FILE" ]]; then
    cp "$PROJECT_CONFIG_BACKUP" "$CONFIG_FILE"
  fi
}

cleanup_project_config_backup() {
  restore_project_config
  if [[ -n "${PROJECT_CONFIG_BACKUP:-}" && -f "$PROJECT_CONFIG_BACKUP" ]]; then
    rm -f "$PROJECT_CONFIG_BACKUP"
  fi
}

set_project_connection_for_sqlcl() {
  local command_name="$1"
  local tmp_config

  echo -e "${BLUE}Temporarily setting sqlcl.connectionName for project $command_name...${NC}"
  tmp_config="$(mktemp)"
  jq --arg connection_name "$DB_CONNECT_DEV" '.sqlcl.connectionName = $connection_name' "$CONFIG_FILE" > "$tmp_config"
  mv "$tmp_config" "$CONFIG_FILE"
}

show_tree_or_find() {
  local path="$1"
  if [[ ! -d "$path" ]]; then
    echo -e "${YELLOW}$path does not exist yet.${NC}"
    return
  fi

  if command -v tree >/dev/null 2>&1; then
    tree "$path"
  else
    find "$path" -maxdepth 4 -type f -print
  fi
}

apply_known_stage_adjustments() {
  local adjusted_count=0
  local file
  local tmp_file

  while IFS= read -r file; do
    if grep -Fq "This script might contain a rename case" "$file" \
      && grep -Fq "payee_name varchar2(120)" "$file" \
      && grep -Fq 'DROP ("VENDOR_NAME")' "$file"; then

      tmp_file="$(mktemp)"
      sed -n '1,3p' "$file" > "$tmp_file"
      cat >> "$tmp_file" <<'EOF'

-- Demo adjustment:
-- SQLcl generated a cautious add/drop pattern for VENDOR_NAME -> PAYEE_NAME.
-- The intended migration is a column rename so existing values are preserved.

ALTER TABLE expenses RENAME COLUMN vendor_name TO payee_name
/
EOF

      mv "$tmp_file" "$file"
      adjusted_count=$((adjusted_count + 1))
      echo -e "${GREEN}Adjusted staged rename migration: $file${NC}"
    fi
  done < <(find "$PROJECT_DIR/dist/releases/next" -path "*/myapp/tables/expenses.sql" -type f -print 2>/dev/null || true)

  if [[ "$adjusted_count" -gt 0 ]]; then
    echo -e "${GREEN}Applied $adjusted_count known staged rename adjustment(s).${NC}"
  fi
}

require_cmd sql
require_cmd git
require_cmd gh
require_cmd jq

if ! gh auth status >/dev/null 2>&1; then
  echo -e "${RED}ERROR: GitHub CLI is not authenticated.${NC}"
  echo -e "${YELLOW}Run: gh auth login${NC}"
  exit 1
fi

if [[ ! -d "$PROJECT_DIR/.git" ]]; then
  echo -e "${RED}ERROR: $PROJECT_DIR is not an initialized Git repository.${NC}"
  echo -e "${YELLOW}Run create_project.sh first.${NC}"
  exit 1
fi

cd "$PROJECT_DIR"
configure_git_identity

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo -e "${RED}ERROR: working tree has uncommitted changes.${NC}"
  git status --short
  exit 1
fi

echo ""
echo -e "${BLUE}Starting development cycle: $CYCLE_NAME${NC}"
echo -e "${BLUE}Branch:        $BRANCH_NAME${NC}"
echo -e "${BLUE}Project:       $PROJECT_DIR${NC}"
echo -e "${BLUE}Schema:        $SCHEMA_NAME${NC}"
echo -e "${BLUE}DB connection: $DB_CONNECT_DEV${NC}"
echo ""
echo -e "${YELLOW}Expected state: the developer has already applied the desired DB changes manually.${NC}"
read -p "Press Enter to capture this DB state with project export/stage..." -r

echo ""
echo -e "${BLUE}Synchronizing $GIT_DEFAULT_BRANCH...${NC}"
git checkout "$GIT_DEFAULT_BRANCH"
git pull --ff-only origin "$GIT_DEFAULT_BRANCH"

if git rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
  echo -e "${RED}ERROR: local branch $BRANCH_NAME already exists.${NC}"
  exit 1
fi

if git ls-remote --exit-code --heads origin "$BRANCH_NAME" >/dev/null 2>&1; then
  echo -e "${RED}ERROR: remote branch $BRANCH_NAME already exists.${NC}"
  exit 1
fi

echo -e "${BLUE}Creating branch $BRANCH_NAME...${NC}"
git checkout -b "$BRANCH_NAME"
backup_project_config
trap cleanup_project_config_backup EXIT

echo ""
echo -e "${BLUE}Running SQLcl project export...${NC}"
echo -e "${YELLOW}project export -schemas $SCHEMA_NAME -verbose${NC}"
set_project_connection_for_sqlcl "export"
sql -name "$DB_CONNECT_DEV" <<EOF
project export -schemas $SCHEMA_NAME -verbose
exit
EOF
restore_project_config

echo ""
echo -e "${BLUE}Source changes after export:${NC}"
git status --short src .dbtools || true
show_tree_or_find "$PROJECT_DIR/src"

git add src .dbtools
if git diff --cached --quiet; then
  echo -e "${RED}ERROR: project export did not produce source changes.${NC}"
  echo -e "${YELLOW}Check that the DB state is different from main, or that filters are not excluding the objects.${NC}"
  exit 1
fi

git commit -m "feat: source export for $CYCLE_NAME"

echo ""
echo -e "${BLUE}Running SQLcl project stage...${NC}"
echo -e "${YELLOW}project stage -verbose${NC}"
set_project_connection_for_sqlcl "stage"
sql -name "$DB_CONNECT_DEV" <<EOF
project stage -verbose
exit
EOF
restore_project_config

echo ""
echo -e "${BLUE}Generated staged changelogs:${NC}"
show_tree_or_find "$PROJECT_DIR/dist/releases/next"

echo ""
echo -e "${BLUE}Applying known demo staged changelog adjustments...${NC}"
apply_known_stage_adjustments

echo ""
echo -e "${YELLOW}Review dist/releases/next before committing staged changelogs.${NC}"
echo -e "${YELLOW}Pay special attention to column renames such as VENDOR_NAME -> PAYEE_NAME.${NC}"
read -p "Press Enter to commit staged changelogs, or Ctrl+C to abort..." -r

git add dist
if git diff --cached --quiet; then
  echo -e "${RED}ERROR: project stage did not produce dist changes.${NC}"
  exit 1
fi

git commit -m "feat: staged changelogs for $CYCLE_NAME"

echo ""
echo -e "${BLUE}Pushing branch and creating pull request...${NC}"
git push -u origin "$BRANCH_NAME"

PR_TITLE="Development cycle: $CYCLE_NAME"
PR_BODY="Captures database source export and staged SQLcl Project changelogs for cycle: $CYCLE_NAME."

PR_URL="$(gh pr create \
  --base "$GIT_DEFAULT_BRANCH" \
  --head "$BRANCH_NAME" \
  --title "$PR_TITLE" \
  --body "$PR_BODY")"

echo ""
echo -e "${GREEN}Development cycle captured.${NC}"
echo -e "${BLUE}Pull request: $PR_URL${NC}"
echo -e "${YELLOW}Merge this PR before starting the next cycle.${NC}"
