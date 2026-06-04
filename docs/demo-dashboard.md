# Demo Dashboard

The demo dashboard is a static HTML frontend backed by read-only ORDS endpoints.
It shows the current state of the development and production schemas while the
SQLcl Projects CI/CD demo progresses.

## Components

```text
frontend/
  index.html
  config.example.js
  config.local.js
  assets/demo-dashboard.css
  assets/demo-dashboard.js

ords/
  install_demo_dashboard_api.sql
  uninstall_demo_dashboard_api.sql

run/
  install_demo_dashboard_api.sh
  configure_demo_dashboard.sh
  uninstall_demo_dashboard_api.sh
```

`frontend/config.local.js` is ignored by Git because it contains environment
URLs that are local to the demo installation.

## Install the ORDS API

The installer uses the SQLcl connections configured in `run/setup_env.sh`.
Override them from the shell if your saved connection names are different:

```bash
export DB_CONNECT_DEV="MIKE[MYAPP]"
export DB_CONNECT_PROD="MYAPP_PRO"
```

For Autonomous Database, the API URL is based on the ORDS host used by Database
Actions or APEX:

```text
https://<adb-ords-host>/ords/myapp/demo-dashboard
```

Set the URLs before installing if you want the installer to print the health
links when it finishes:

```bash
export DEMO_DASHBOARD_DEV_API_BASE_URL="https://<dev-ords-host>/ords/myapp/demo-dashboard"
export DEMO_DASHBOARD_PROD_API_BASE_URL="https://<prod-ords-host>/ords/myapp/demo-dashboard"
```

Install the read-only API in both environments:

```bash
cd /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/run
./install_demo_dashboard_api.sh both
```

Install only one environment if needed:

```bash
./install_demo_dashboard_api.sh dev
./install_demo_dashboard_api.sh prod
```

## Configure the Frontend

Use the helper to generate `frontend/config.local.js`:

```bash
cd /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/run
./configure_demo_dashboard.sh
```

It prompts for:

- DEV ORDS API base URL
- PROD ORDS API base URL
- auto-refresh interval

The generated file looks like this:

```javascript
window.DEMO_DASHBOARD_CONFIG = {
  projectName: "MyAppCICD",
  schemaName: "MYAPP",
  refreshSeconds: 0,
  devApiBaseUrl: "https://dev-host.example.com/ords/myapp/demo-dashboard",
  prodApiBaseUrl: "https://prod-host.example.com/ords/myapp/demo-dashboard"
};
```

If `refreshSeconds` is greater than zero, the auto-refresh toggle uses that
interval.

You can also create the file manually by copying the example:

```bash
cd /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/frontend
cp config.example.js config.local.js
```

## Open the Dashboard

Use any static web server. For example:

```bash
cd /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/frontend
python3 -m http.server 8088
```

Then open:

```text
http://localhost:8088
```

Serving the files over HTTP avoids browser restrictions that can appear with
`file://` URLs.

## Data Sources

The browser does not connect directly to Oracle Database and does not call the
GitHub API. It calls ORDS in both environments:

```text
Browser -> DEV ORDS -> MYAPP DEV
Browser -> PROD ORDS -> MYAPP PROD
```

GitHub deployment metadata is shown only when it has been recorded in
`PROJECT_CONTROL` by the controlled deploy workflow.

## Dashboard Views

- `Overview` shows DEV and PROD health, object counts, current production
  release, and the demo lifecycle.
- `Development` shows current DEV objects, table columns, and changelog rows.
- `Production` shows current PROD objects, table columns, and changelog rows.
- `Compare` calculates application table and column drift in the browser.
- `Deploy History` shows rows from production `PROJECT_CONTROL`.

`PROJECT_CONTROL`, `DATABASECHANGELOG%`, and `DBTOOLS$%` objects are classified
as `DEMO_METADATA`. The compare view focuses on `APPLICATION` objects.
