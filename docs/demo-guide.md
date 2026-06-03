# Demo Guide

This guide explains how to run the development portion of the SQLcl Projects demo.

The demo focuses on the local development loop:

```text
manual DB change -> project export -> project stage -> GitHub PR -> merge
```

Release creation, artifact generation, and production deployment are reserved for a second phase with GitHub Actions.

## 1. Preparation

Check that the SQLcl connection exists:

```bash
sql /nolog
```

Inside SQLcl:

```sql
CONNECT -name "MIKE[MYAPP]"
SHOW USER
```

`SHOW USER` should return `MYAPP`, with `MIKE` acting as the proxy user.

Reset the database to the initial state if needed:

```sql
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/reset/01_reset_to_initial_schema.sql
```

## 2. Create The Project

Run once:

```bash
cd /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/run
./create_project.sh
```

This script:

- runs `project init`
- sets `git.defaultBranch=main`
- adds the `object_name not like 'DBTOOLS$%'` filter
- creates the generated SQLcl Project README
- initializes Git
- configures the GitHub remote
- pushes `main`

## 3. Base Cycle

The base cycle captures the initial `MYAPP` schema.

```bash
./dev_cycle.sh base_release
```

The script creates this branch:

```text
dev_base_release
```

It generates:

- source files under `src/`
- staged changelogs under `dist/releases/next/`
- a pull request into `main`

Merge the PR manually before continuing.

## 4. V1 Cycle

Apply v1 changes manually in SQLcl:

```sql
CONNECT -name "MIKE[MYAPP]"
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/v1_sql_scripts/01_add_training_sessions_table.sql
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/v1_sql_scripts/02_add_player_social_media_handle.sql
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/v1_sql_scripts/03_rename_expenses_vendor_column.sql
```

Capture the cycle:

```bash
./dev_cycle.sh v1_changes
```

Review in the PR:

- new table `TRAINING_SESSIONS`
- new column `PLAYERS.SOCIAL_MEDIA_HANDLE`
- column rename from `EXPENSES.VENDOR_NAME` to `EXPENSES.PAYEE_NAME`

Note: if SQLcl represents the rename as drop/add instead of `RENAME COLUMN`, correct it before merging or handle it as custom SQL.

Merge the PR manually before continuing.

## 5. V2 Cycle

Apply v2 changes manually:

```sql
CONNECT -name "MIKE[MYAPP]"
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/v2_sql_scripts/01_add_injury_reports_table.sql
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/v2_sql_scripts/02_add_game_revenue_columns.sql
```

Capture the cycle:

```bash
./dev_cycle.sh v2_changes
```

Review in the PR:

- new table `INJURY_REPORTS`
- new columns in `GAMES`
  - `ATTENDANCE`
  - `TICKET_REVENUE_AMOUNT`

## 6. Reset

Prepare the demo for another run:

```bash
./cleanup_demo.sh
```

This can:

- remove the generated SQLcl Project under `MIKE/projects/MyAppCICD`
- reset the development database schema
- optionally drop production application and SQLcl Project/Liquibase objects while creating `PROJECT_CONTROL` if needed, keeping it, and truncating its contents
- optionally reset the GitHub repository

Production and remote cleanup are guarded by separate `y/N` prompts.
