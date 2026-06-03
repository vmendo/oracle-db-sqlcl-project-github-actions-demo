# GitHub Actions Templates

These files are the source templates used by `run/create_project.sh`.

When the SQLcl Project is created or resumed, the script copies `.github/` from
this directory into the generated project folder:

```text
MIKE/projects/MyAppCICD/.github
```

Keep workflow changes here first, then rerun `run/create_project.sh` or copy the
templates into the generated project before committing.

The validation workflow connects directly to Autonomous Database with
`connect -cloudconfig`; it does not create a saved SQLcl connection on the
GitHub Actions runner.

The release workflow is manual. It asks for a version, runs `project release`
and `project gen-artifact`, commits the closed SQLcl release state back to
`main`, and publishes the generated ZIP to GitHub Releases.

The deploy workflow is manual. It can list release artifacts, generate a
production deploy preview with `lb update-sql`, or deploy a selected release
ZIP with `project deploy`. It uses the same direct wallet connection pattern
and the same `TARGET_DB_*` secrets.

The controlled deploy workflow is also manual. It takes a selected release tag,
creates `PROJECT_CONTROL` if it is missing, shows the current and selected
production versions in the preview job summary, uploads the preview SQL, waits
on the GitHub Environment `production`, deploys after approval, and records the
successful deployment in `PROJECT_CONTROL`.

Configure required reviewers on the GitHub Environment `production` if the
deploy job should pause for manual approval. Without environment protection,
GitHub Actions will continue from preview to deploy automatically.
