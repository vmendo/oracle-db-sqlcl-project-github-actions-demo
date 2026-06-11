# Presenter Notes

## Main Message

SQLcl Projects lets teams treat database changes as code:

- the real schema is exported to `src/`
- changes are materialized as changelogs under `dist/releases/next/`
- GitHub PRs become the review point
- release and deploy can be automated later with GitHub Actions

## Suggested Opening

"In this demo, we are not deploying an application. We are solving a more fundamental and common problem: how to version database changes so they are reviewable, repeatable, and ready for CI/CD."

## Story Structure

| Moment | What To Show | Message |
|---|---|---|
| Project | `create_project.sh` | SQLcl creates the standard project structure once. |
| Base | `dev_cycle.sh base_release` | The initial schema enters GitHub as source and changelog. |
| V1 | v1 scripts + `dev_cycle.sh v1_changes` | Real data model changes are captured from the database. |
| V2 | v2 scripts + `dev_cycle.sh v2_changes` | The same pattern repeats without changing the process. |
| Close | GitHub Actions phase 2 | Release, artifact, and deploy move to controlled automation. |

## Points To Emphasize

- The developer does not hand-write changelogs for every object.
- Review happens in GitHub, not in an isolated SQL session.
- The local cycle does not deploy to production.
- `main` accumulates staged changes that are not yet packaged as a release.
- The flow is intentionally simple: one schema, one developer, one branch per cycle.

## Demo Moments

### 1. Before `create_project.sh`

Show the base folder:

```bash
tree -L 2 /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo
```

Explain that the SQL scripts simulate manual development work.

### 2. After `project init`

Show:

```bash
tree -a MIKE/projects/MyAppCICD -L 3
```

Point out:

- `.dbtools`
- `src`
- `dist`
- `project.filters`

### 3. After `project export`

Show `git status` and `src/database`.

Message:

"SQLcl has converted the Oracle catalog into versionable files."

### 4. After `project stage`

Show `dist/releases/next`.

Message:

"SQLcl has converted the difference against main into reviewable Liquibase changes."

### 5. Pull Request

Show in GitHub:

- `src/` diff
- `dist/releases/next/` diff
- PR review and merge

## Expected Questions

### "Why not run release locally?"

Because the demo separates responsibilities:

- development: export, stage, PR
- CI: validate on branch push before merge
- on-demand release: close a version and generate an artifact
- on-demand deploy: apply the artifact to production

### "What about multiple developers?"

This version uses only `MIKE` to keep the story focused. A second version can add:

- concurrent branches
- rebase from `main`
- controls around `dist/releases/next`
- automated PR validations

### "What about internal tooling objects?"

The project filters prevent helper objects such as `DBTOOLS$MCP_LOG`, deployment control metadata, and ORDS dashboard modules from being exported.
