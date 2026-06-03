# Troubleshooting

## SQLcl Fails With Java

Symptom:

```text
No such file or directory ... java
```

The scripts set `JAVA_HOME` locally with:

```bash
SQLCL_JAVA_HOME=/usr/lib/jvm/java-21-openjdk-21.0.11.0.10-1.0.1.el8.x86_64
```

If your host uses a different Java installation, export it before running the scripts:

```bash
export SQLCL_JAVA_HOME=/path/to/your/jdk
```

## GitHub CLI Is Not Authenticated

Symptom:

```text
GitHub CLI is not authenticated
```

Fix:

```bash
gh auth login
gh auth status
```

## The `MIKE[MYAPP]` Connection Does Not Exist

List saved connections:

```bash
sql /nolog
```

Inside SQLcl:

```sql
CONNMGR LIST -flat
```

The connection must use proxy authentication:

```text
MIKE[MYAPP]
```

## The Project Already Exists

Symptom:

```text
ERROR: /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/MIKE/projects/MyAppCICD already exists
```

Options:

- run `run/cleanup_demo.sh`
- manually remove `MIKE/projects/MyAppCICD`
- choose a different project name when running `run/create_project.sh`
- change `PROJECT_NAME_DEFAULT` in `run/setup_env.sh`

If the project exists because `create_project.sh` failed after creating the
SQLcl Project scaffold, run `create_project.sh` again. The script can resume
when the scaffold already exists.

## GitHub Actions Files Are Missing

Symptom:

```text
.github/workflows/sqlcl-project-validate.yml is not present in the generated project
```

Cause:

The generated project was created before the GitHub Actions templates were
installed, or the `.github/` directory was removed manually.

Fix:

```bash
cd /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/run
./create_project.sh
```

The script copies templates from `templates/github-actions` into the generated
project and commits them when there are changes.

## Push Fails With Stale Info

Symptom:

```text
! [rejected] main -> main (stale info)
error: failed to push some refs
```

Cause:

`--force-with-lease` needs a fresh local view of `origin/main`. If the remote
branch exists and the local repository has not fetched it yet, Git rejects the
push.

Fix:

```bash
git fetch origin main
git push -u origin main --force-with-lease
```

The `create_project.sh` script runs this fetch automatically before pushing.

## `project export` Produces No Changes

Possible causes:

- the database did not change compared with `main`
- the v1/v2 scripts were not applied
- the filter in `.dbtools/filters/project.filters` excludes the object
- the branch starts from a `main` that does not include the previous cycle

Validate in SQLcl:

```sql
SELECT table_name
FROM user_tables
WHERE table_name IN ('TRAINING_SESSIONS','INJURY_REPORTS');
```

## `project stage` Produces No Changes

Check that the script committed `src` before running `project stage`.

SQLcl Projects compares the current branch against the configured base branch. For this demo:

```sql
project config -list -name git.defaultBranch
```

It should return `main`.

## `DBTOOLS$MCP_LOG` Appears In The Export

Review the filter file:

```text
.dbtools/filters/project.filters
```

It should contain:

```sql
object_name not like 'DBTOOLS$%',
```

## Column Rename Appears As Drop/Add

The v1 change renames:

```sql
EXPENSES.VENDOR_NAME -> EXPENSES.PAYEE_NAME
```

If the generated changelog does not preserve the rename as a safe operation, do not merge the PR without reviewing it. For an advanced demo, insert custom SQL under `dist/releases/next` with `project stage add-custom`.

## Remote Branch Already Exists

Symptom:

```text
remote branch dev_<cycle_name> already exists
```

Fix for repeating a demo:

```bash
git push origin --delete dev_<cycle_name>
git branch -D dev_<cycle_name>
```

Or run `run/cleanup_demo.sh` and use the remote reset option.
