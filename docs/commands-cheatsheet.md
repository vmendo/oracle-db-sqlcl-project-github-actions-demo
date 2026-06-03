# Commands Cheatsheet

## SQLcl Connection

```sql
CONNECT -name "MIKE[MYAPP]"
SHOW USER
```

## Database Reset

```sql
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/reset/01_reset_to_initial_schema.sql
```

## Create Project

```bash
cd /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/run
./create_project.sh
```

## Capture Development Cycle

```bash
./dev_cycle.sh base_release
./dev_cycle.sh v1_changes
./dev_cycle.sh v2_changes
```

## Apply V1 Manually

```sql
CONNECT -name "MIKE[MYAPP]"
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/v1_sql_scripts/01_add_training_sessions_table.sql
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/v1_sql_scripts/02_add_player_social_media_handle.sql
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/v1_sql_scripts/03_rename_expenses_vendor_column.sql
```

## Apply V2 Manually

```sql
CONNECT -name "MIKE[MYAPP]"
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/v2_sql_scripts/01_add_injury_reports_table.sql
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/v2_sql_scripts/02_add_game_revenue_columns.sql
```

## SQLcl Projects Commands Used By The Scripts

```sql
project init -name MyAppCICD -schemas MYAPP -makeroot
project config set -name git.defaultBranch -value main
project export -schemas MYAPP -verbose
project stage -verbose
```

`MyAppCICD` and `MYAPP` are the demo defaults from `run/setup_env.sh`.
`run/create_project.sh` prompts for both values and saves the selected values in
`run/.demo_selection.env` for follow-up scripts.

After `project init`, `run/create_project.sh` sets `sqlcl.connectionName` to an
empty string in `.dbtools/project.config.json` so the project is not bound to a
developer-local SQLcl connection. During `dev_cycle.sh`, the value is set
temporarily before `project export` and `project stage`, then restored before
commits.

## Git Commands Used By The Cycle

```bash
git checkout main
git pull --ff-only origin main
git checkout -b dev_<cycle_name>
git add src .dbtools
git commit -m "feat: source export for <cycle_name>"
git add dist
git commit -m "feat: staged changelogs for <cycle_name>"
git push -u origin dev_<cycle_name>
gh pr create --base main --head dev_<cycle_name>
```
