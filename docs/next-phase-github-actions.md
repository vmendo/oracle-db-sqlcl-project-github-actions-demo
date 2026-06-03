# Phase 2: GitHub Actions

This local demo stops at `project stage` and pull request creation.

The next phase moves release, artifact generation, and deployment into GitHub Actions.

The repository should not depend on a developer-local SQLcl connection name. The
project scaffold keeps `sqlcl.connectionName` empty, and each workflow must
connect to the appropriate database before running SQLcl Projects commands.

## Workflow 1: Validate Development Branches

Trigger:

```yaml
on:
  push:
    branches-ignore: [ main ]
```

Goal:

- check out the repository
- skip direct `main` pushes so the initial scaffold does not trigger validation
- validate development branch commits before merge
- install or configure SQLcl
- configure the Autonomous Database wallet
- connect directly to the target validation database
- run SQLcl Project verification
- fail the workflow if the SQLcl verify summary reports errors

Expected command:

```sql
project verify -verbose
```

SQLcl 26.1 uses `project verify` for project validation. The workflow can still
be named "SQLcl Project Validate" for demo clarity.

Expected GitHub secrets:

```text
TARGET_DB_USER
TARGET_DB_PASSWORD
TARGET_DB_CONNECT_STRING
TARGET_DB_WALLET_ZIP_B64
```

Expected GitHub variable:

```text
None.
```

`TARGET_DB_CONNECT_STRING` should be the TNS alias from the wallet, for example
`myadb_low`. `TARGET_DB_WALLET_ZIP_B64` contains the Autonomous Database wallet
ZIP encoded as base64. The project keeps `sqlcl.connectionName` empty, so the
workflow does not depend on a saved SQLcl connection name.

Create the wallet secret from the downloaded wallet ZIP:

```bash
base64 -w 0 Wallet_TARGET.zip
```

The demo runner includes an interactive helper that performs this encoding and
sets the required GitHub secrets:

```bash
cd /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/run
./configure_github_actions.sh
```

The helper asks for the wallet ZIP first and lists the available TNS aliases
from `tnsnames.ora` before asking which alias should be stored as
`TARGET_DB_CONNECT_STRING`.

The verify step reads the target database metadata to validate project filters
and project structure. It does not deploy the staged changes.

The generated workflow ignores direct pushes to `main`. Development branch
pushes run `project verify` once `dist/releases/main.changelog.xml` exists in
the branch. This validates PR branches before they are merged.

The workflow opens one SQLcl session, connects directly with the wallet ZIP, and
runs `project verify` in the same session:

```bash
sql -s -L /nolog
```

```sql
connect -cloudconfig "$RUNNER_TEMP/adb-wallet.zip" -user "$TARGET_DB_USER" -password "$TARGET_DB_PASSWORD" -url "$TARGET_DB_CONNECT_STRING"
project verify -verbose
```

## Source Templates

The generated project receives GitHub Actions files from:

```text
/home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/templates/github-actions
```

`run/create_project.sh` copies those templates into the generated project under
`.github/` before committing the scaffold to GitHub. Update the template source
first when changing CI/CD workflows.

## Workflow 2: On-Demand Release

Trigger:

```yaml
on:
  workflow_dispatch:
    inputs:
      version:
        description: Release version
        required: true
```

Goal:

- start from `main`
- run `project release -version <version>`
- run `project gen-artifact`
- commit the closed release state back to `main`
- upload the ZIP file to GitHub Releases

Expected commands:

```sql
project release -version 1.0 -verbose
project gen-artifact -name MyAppCICD -version 1.0 -format zip -force -verbose
```

The workflow asks for the release version through `workflow_dispatch`. It closes
the SQLcl Project release locally, commits `.dbtools` and `dist` back to `main`,
uploads the generated ZIP as a workflow artifact, and creates a GitHub Release
with the generated ZIP attached.

## Workflow 3: On-Demand Deploy

Trigger:

```yaml
on:
  workflow_dispatch:
    inputs:
      operation:
        description: list, preview, or deploy
        required: true
      release_tag:
        description: GitHub Release tag to deploy
        required: false
      artifact_name:
        description: Optional ZIP asset name
        required: false
```

Goal:

- list available GitHub Release ZIP artifacts
- download the artifact from GitHub Releases
- connect to the target database
- infer the currently installed release from `DATABASECHANGELOG`
- block older release deployment unless explicitly allowed
- optionally generate a deploy preview with Liquibase `update-sql`
- run `project deploy`

Expected preview command:

```sql
lb update-sql -changelog-file releases/main.changelog.xml -search-path "." -defaults-file env/default.properties
```

Expected deploy command:

```sql
project deploy -file artifact/MyAppCICD-1.0.zip -verbose
```

Native GitHub Actions `workflow_dispatch` inputs cannot dynamically populate a
choice list from GitHub Releases. The deploy workflow therefore includes a
`list` operation that writes available release tags and ZIP assets to the run
summary. The operator then reruns the same workflow with `preview` or `deploy`
and the selected release tag.

SQLcl 26.1 `project deploy` does not expose a dry-run option. The workflow uses
SQLcl Liquibase `lb update-sql` as the preview mode after extracting the
selected artifact. This generates SQL from the artifact changelog without
applying changes.

## Expected Secrets

The exact implementation depends on the target environment, but typical secrets are:

```text
DB_USER
DB_PASSWORD
DB_SERVICE
WALLET_ZIP_B64
```

The production workflow should use the same direct wallet connection pattern
unless the team later chooses to manage SQLcl connections separately.

## Suggested Policy

- `main` can accumulate staged changelogs.
- A release is created only when the team decides to close a package.
- Deployment is executed with a manual workflow run and an explicit production confirmation input.
- Production consumes versioned artifacts, not development branches.
