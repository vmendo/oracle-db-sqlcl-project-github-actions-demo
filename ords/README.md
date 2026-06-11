# ORDS Demo Dashboard API

This folder contains the read-only ORDS module used by the static demo
dashboard.

Install it in both demo schemas:

```bash
cd /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/run
./install_demo_dashboard_api.sh both
```

The script uses the saved SQLcl connections from `run/setup_env.sh`:

- `DB_CONNECT_DEV`, default `MIKE[MYAPP]`
- `DB_CONNECT_PROD`, default `MYAPP_PRO`

Override them from the shell when needed:

```bash
export DB_CONNECT_DEV="MY_DEV_CONNECTION"
export DB_CONNECT_PROD="MY_PROD_CONNECTION"
```

The installed module base path is:

```text
/ords/myapp/demo-dashboard/
```

Use different host names for development and production in the frontend
configuration.

For Autonomous Database, set these optional variables so the installer can print
the exact health links after installation:

```bash
export DEMO_DASHBOARD_DEV_API_BASE_URL="https://<dev-ords-host>/ords/myapp/demo-dashboard"
export DEMO_DASHBOARD_PROD_API_BASE_URL="https://<prod-ords-host>/ords/myapp/demo-dashboard"
```

The installer configures CORS for:

```text
http://localhost:8088,http://127.0.0.1:8088
```

To repair or change CORS later:

```bash
cd /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/run
./configure_demo_dashboard_cors.sh both
```

## Endpoints

| Endpoint | Purpose |
|---|---|
| `health/` | Current schema, database name, object health, and metadata table presence. |
| `summary/` | Object counts, latest deployment, and latest SQLcl Project changeset. |
| `objects/` | Schema objects classified as `APPLICATION` or `DEMO_METADATA`. |
| `tables/` | Table columns, data types, nullable flags, and PK/FK flags. |
| `changelog/` | Recent `DATABASECHANGELOG` rows, or an empty list before deployment. |
| `project-control/` | Recent `PROJECT_CONTROL` rows, or an empty list before deployment. |

All endpoints are `GET` only.

## Cleanup

To remove the ORDS module:

```bash
cd /home/opc/mcp_demos/oracle-db-sqlcl-project-github-actions-demo/run
./uninstall_demo_dashboard_api.sh both
```

`cleanup_demo.sh` does not remove the ORDS module. The dashboard API is demo
infrastructure, not part of the application schema lifecycle.
