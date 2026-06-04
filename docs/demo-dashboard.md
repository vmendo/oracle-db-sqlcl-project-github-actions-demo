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
  configure_demo_dashboard_cors.sh
  start_demo_dashboard.sh
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

The installer asks for the DEV and PROD Autonomous URLs. Paste either the ADB
host, a Database Actions URL, or an APEX URL. The script normalizes the value to
`/ords/myapp/demo-dashboard`, prints the health endpoints, and writes
`frontend/config.local.js`.

The installer also configures CORS for the local dashboard origins:

```text
http://localhost:8088,http://127.0.0.1:8088
```

Override this with `DEMO_DASHBOARD_ALLOWED_ORIGINS` when serving the dashboard
from a different host or port.

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

In the normal flow, `install_demo_dashboard_api.sh` generates
`frontend/config.local.js` automatically.

Use the separate helper only when you need to refresh the frontend URLs without
reinstalling ORDS:

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

Use the runner script:

```bash
cd /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/run
./start_demo_dashboard.sh
```

On the first run, it prompts for DEV and PROD ORDS URLs, writes
`frontend/config.local.js`, starts the HTTP server, and prints the browser URL:

```text
http://localhost:8088
```

Later runs reuse `frontend/config.local.js` and start the HTTP server directly.
Use `./start_demo_dashboard.sh --reconfigure` to update the saved URLs.

Serving the files over HTTP avoids browser restrictions that can appear with
`file://` URLs. The default bind address is `127.0.0.1`; override it with
`DEMO_DASHBOARD_BIND` or `--bind` if the browser must connect from another
machine.

## CORS Troubleshooting

If the dashboard shows `Failed to fetch`, first open the health endpoints
directly in the browser:

```text
https://<dev-ords-host>/ords/myapp/demo-dashboard/health/
https://<prod-ords-host>/ords/myapp/demo-dashboard/health/
```

If those endpoints return JSON but the dashboard still fails, the ORDS module
needs the dashboard origin in its allowed origins list:

```bash
cd /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/run
./configure_demo_dashboard_cors.sh both
```

When using a non-default port:

```bash
export DEMO_DASHBOARD_ALLOWED_ORIGINS="http://localhost:8090,http://127.0.0.1:8090"
./configure_demo_dashboard_cors.sh both
./start_demo_dashboard.sh --port 8090
```

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
- `Development` shows current DEV application objects, table columns, and changelog rows.
- `Production` shows current PROD application objects, table columns, and changelog rows.
- `Compare` calculates application table and column drift in the browser.
- `Deploy History` shows rows from production `PROJECT_CONTROL`.

The environment tabs hide demo metadata and system-generated objects from the
main object list. Use the object type filter to switch between tables, views,
indexes, and other application objects. Use the table selector to inspect one
table's columns at a time. Object counters, including invalid object counters,
are scoped to application objects.

`PROJECT_CONTROL`, `DATABASECHANGELOG%`, `DBTOOLS$%`, and ORDS helper objects
are classified as `DEMO_METADATA`. The compare view focuses on `APPLICATION`
objects.
