# MyApp SQLcl Projects Demo Runner

These scripts drive the development side of the MyApp database CI/CD demo.

They intentionally stop at `project stage`. Release creation, artifact generation,
and deployment are deferred to GitHub Actions in the next phase.

## Scripts

- `setup_env.sh` - common configuration.
- `create_project.sh` - one-time SQLcl Project bootstrap, GitHub Actions template install, and GitHub sync.
- `configure_github_actions.sh` - interactive GitHub Actions secrets setup.
- `dev_cycle.sh` - reusable development cycle: export, stage, commit, push, PR.
- `cleanup_demo.sh` - local cleanup, development reset, optional production schema reset, and optional remote reset.

## Demo Sequence

Create the SQLcl Project once:

```bash
cd /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/run
./create_project.sh
```

The script asks for the project name and default schema. Press Enter to use the
demo defaults from `setup_env.sh`: `MyAppCICD` and `MYAPP`. The selected values
are saved in `run/.demo_selection.env` so follow-up scripts use the same
project directory and schema.

The script copies GitHub Actions source templates from:

```text
/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/templates/github-actions
```

into the generated project `.github/` directory before the initial Git commit.

The generated GitHub Actions workflow connects directly to Autonomous Database
with the wallet ZIP and `connect -cloudconfig`. It does not create or reuse a
saved SQLcl connection name on the runner.

`dev_cycle.sh` keeps the committed project configuration independent from local
SQLcl connection names. To avoid SQLcl warning noise during local `project
export` and `project stage`, the script temporarily sets `sqlcl.connectionName`
to the development connection and restores the empty value before each commit.

`create_project.sh` offers to configure the target database secrets before the
first development branch is pushed. The initial scaffold push to `main` does not
trigger `project verify`. Run the helper before pushing `base_release` if you
want validation to run immediately on that branch.

After staged changes are merged to `main`, use the manual `SQLcl Project
Release` GitHub Action to enter a version number, close the SQLcl Project
release, generate the ZIP artifact, and publish it to GitHub Releases.

For production deployment, the original `SQLcl Project Deploy` workflow remains
available with separate `list`, `preview`, and `deploy` operations. The parallel
`SQLcl Project Controlled Deploy` workflow uses `PROJECT_CONTROL` to show the
current production version, creates the deploy preview, waits on the GitHub
Environment `production`, and records the deployed version after approval.

Configure required reviewers on the GitHub Environment `production` if the
controlled deploy job should pause for manual approval.

Configure the target database secrets and wallet for GitHub Actions:

```bash
./configure_github_actions.sh
```

The script prompts for the production Autonomous Database wallet ZIP first. If
`TARGET_WALLET_ZIP_DEFAULT` is exported in your shell, that value is offered as
the default; otherwise the path is required interactively. It lists the TNS
aliases found in `tnsnames.ora`, and then asks for the target user and password.
It creates the required repository secrets with `gh`.

Capture the initial database state:

```bash
./dev_cycle.sh base_release
```

Merge the generated PR into `main` before continuing.

Apply v1 changes manually in SQLcl:

```sql
CONNECT -name "MIKE[MYAPP]"
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/v1_sql_scripts/01_add_training_sessions_table.sql
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/v1_sql_scripts/02_add_player_social_media_handle.sql
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/v1_sql_scripts/03_rename_expenses_vendor_column.sql
```

Capture v1:

```bash
./dev_cycle.sh v1_changes
```

Merge the generated PR into `main` before continuing.

Apply v2 changes manually in SQLcl:

```sql
CONNECT -name "MIKE[MYAPP]"
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/v2_sql_scripts/01_add_injury_reports_table.sql
@/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/v2_sql_scripts/02_add_game_revenue_columns.sql
```

Capture v2:

```bash
./dev_cycle.sh v2_changes
```

## Reset

Reset the demo state:

```bash
./cleanup_demo.sh
```

Production reset is optional and guarded by a separate `y/N` prompt. When
enabled, it connects with `DB_CONNECT_PROD` and drops every object owned by the
target schema except `PROJECT_CONTROL`. It truncates `PROJECT_CONTROL` so the
next demo starts with no installed production version recorded. If
`PROJECT_CONTROL` is missing, the reset creates it first.

Remote GitHub reset is optional and guarded by a separate `y/N` prompt.
