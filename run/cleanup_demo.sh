#!/bin/bash

# Reset the local demo workspace and optionally reset production and GitHub.

set -euo pipefail

RED='\033[31m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh"

PROJECT_DIR="$PROJECTS_HOME/$PROJECT_NAME"
RESET_SQL="$DEMO_HOME/reset/01_reset_to_initial_schema.sql"
PROD_RESET_SQL="$DEMO_HOME/reset/02_drop_all_schema_objects.sql"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}ERROR: $1 not found in PATH${NC}"
    exit 1
  }
}

echo ""
echo -e "${BLUE}Cleanup for MyApp SQLcl Projects demo${NC}"
echo -e "${YELLOW}Local project directory: $PROJECT_DIR${NC}"
echo -e "${YELLOW}Database reset script:   $RESET_SQL${NC}"
echo -e "${YELLOW}Production drop script:  $PROD_RESET_SQL${NC}"
echo ""
echo -e "${RED}This removes the local SQLcl Project directory and resets $SCHEMA_NAME to the initial schema state.${NC}"
read -r -p "Continue with local cleanup? [y/N]: " CONFIRM
case "$CONFIRM" in
  y|Y|yes|YES)
    ;;
  *)
    echo -e "${YELLOW}Cleanup cancelled.${NC}"
    exit 0
    ;;
esac

if [[ -d "$PROJECT_DIR" ]]; then
  echo -e "${BLUE}Removing local project directory...${NC}"
  rm -rf "$PROJECT_DIR"
  echo -e "${GREEN}Removed $PROJECT_DIR${NC}"
else
  echo -e "${YELLOW}Project directory does not exist: $PROJECT_DIR${NC}"
fi

if [[ -f "$RESET_SQL" ]]; then
  require_cmd sql
  echo -e "${BLUE}Resetting $SCHEMA_NAME schema with $DB_CONNECT_DEV...${NC}"
  sql -name "$DB_CONNECT_DEV" <<EOF
@$RESET_SQL
exit
EOF
  echo -e "${GREEN}Database reset complete.${NC}"
else
  echo -e "${RED}ERROR: reset script not found: $RESET_SQL${NC}"
  exit 1
fi

echo ""
echo -e "${RED}Optional destructive step: drop production demo objects in schema $SCHEMA_NAME using $DB_CONNECT_PROD.${NC}"
echo -e "${YELLOW}This includes application objects and SQLcl Project/Liquibase tables. PROJECT_CONTROL is kept and truncated.${NC}"
read -r -p "Reset production schema too? [y/N]: " PROD_CONFIRM

case "$PROD_CONFIRM" in
  y|Y|yes|YES)
    ;;
  *)
    echo -e "${GREEN}Skipped production schema reset.${NC}"
    ;;
esac

if [[ "$PROD_CONFIRM" =~ ^([yY]|yes|YES)$ ]]; then
  if [[ -f "$PROD_RESET_SQL" ]]; then
    require_cmd sql
    echo -e "${BLUE}Dropping all production schema objects with $DB_CONNECT_PROD...${NC}"
    sql -name "$DB_CONNECT_PROD" <<EOF
@$PROD_RESET_SQL "$SCHEMA_NAME"
exit
EOF
    echo -e "${GREEN}Production schema reset complete.${NC}"
  else
    echo -e "${RED}ERROR: production reset script not found: $PROD_RESET_SQL${NC}"
    exit 1
  fi
fi

echo ""
echo -e "${YELLOW}Optional destructive step: reset GitHub repository $GITHUB_USER/$GITHUB_REPO.${NC}"
echo -e "${YELLOW}This deletes workflow runs, deployments, non-main branches, tags, releases, and force-pushes a clean main branch.${NC}"
read -r -p "Reset GitHub repository too? [y/N]: " REMOTE_CONFIRM

case "$REMOTE_CONFIRM" in
  y|Y|yes|YES)
    ;;
  *)
    echo -e "${GREEN}Skipped GitHub remote reset.${NC}"
    echo -e "${GREEN}Cleanup complete.${NC}"
    exit 0
    ;;
esac

require_cmd gh
require_cmd git

if ! gh auth status >/dev/null 2>&1; then
  echo -e "${RED}ERROR: GitHub CLI is not authenticated.${NC}"
  echo -e "${YELLOW}Run: gh auth login${NC}"
  exit 1
fi

FULL_REPO="$GITHUB_USER/$GITHUB_REPO"

echo -e "${BLUE}Deleting GitHub Actions workflow runs...${NC}"
while true; do
  mapfile -t run_ids < <(gh run list --repo "$FULL_REPO" --limit 100 --json databaseId --jq '.[].databaseId')

  if [[ "${#run_ids[@]}" -eq 0 ]]; then
    echo -e "${GREEN}No workflow runs remain.${NC}"
    break
  fi

  for run_id in "${run_ids[@]}"; do
    echo "Deleting workflow run: $run_id"
    gh run delete "$run_id" --repo "$FULL_REPO" || true
  done
done

echo -e "${BLUE}Deleting GitHub Deployments...${NC}"
mapfile -t deployment_ids < <(gh api --paginate "repos/$FULL_REPO/deployments" --jq '.[].id')

if [[ "${#deployment_ids[@]}" -eq 0 ]]; then
  echo -e "${GREEN}No deployments remain.${NC}"
else
  for deployment_id in "${deployment_ids[@]}"; do
    echo "Deleting deployment: $deployment_id"
    gh api \
      -X POST \
      "repos/$FULL_REPO/deployments/$deployment_id/statuses" \
      -f state=inactive \
      -f description="Reset SQLcl Projects demo deployment history" \
      -F auto_inactive=true >/dev/null || true
    gh api -X DELETE "repos/$FULL_REPO/deployments/$deployment_id" || true
  done
fi

echo -e "${BLUE}Deleting remote branches except $GIT_DEFAULT_BRANCH...${NC}"
for branch in $(gh api "repos/$FULL_REPO/branches" --jq '.[].name'); do
  if [[ "$branch" != "$GIT_DEFAULT_BRANCH" ]]; then
    echo "Deleting branch: $branch"
    gh api -X DELETE "repos/$FULL_REPO/git/refs/heads/$branch" || true
  fi
done

echo -e "${BLUE}Deleting releases...${NC}"
for release_id in $(gh api "repos/$FULL_REPO/releases" --jq '.[].id'); do
  echo "Deleting release id: $release_id"
  gh api -X DELETE "repos/$FULL_REPO/releases/$release_id" || true
done

echo -e "${BLUE}Deleting tags...${NC}"
for tag in $(gh api "repos/$FULL_REPO/tags" --jq '.[].name'); do
  echo "Deleting tag: $tag"
  gh api -X DELETE "repos/$FULL_REPO/git/refs/tags/$tag" || true
done

TEMP_DIR="$(mktemp -d)"
cd "$TEMP_DIR"
git init --initial-branch="$GIT_DEFAULT_BRANCH"
git config user.name "$GIT_AUTHOR_NAME"
git config user.email "$GIT_AUTHOR_EMAIL"
cat > README.md <<EOF
# $GITHUB_REPO

Repository reset for the MyApp SQLcl Projects CI/CD demo.
EOF
git add README.md
git commit -m "chore: reset repository for demo"
git remote add origin "$GITHUB_URL"
git push -f origin "$GIT_DEFAULT_BRANCH"

echo -e "${GREEN}GitHub repository reset complete.${NC}"
echo -e "${GREEN}Cleanup complete.${NC}"
