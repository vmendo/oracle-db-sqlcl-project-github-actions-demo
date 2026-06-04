(function () {
  "use strict";

  const defaults = {
    projectName: "MyAppCICD",
    schemaName: "MYAPP",
    refreshSeconds: 0,
    devApiBaseUrl: "",
    prodApiBaseUrl: ""
  };

  const config = Object.assign({}, defaults, window.DEMO_DASHBOARD_CONFIG || {});
  const state = {
    activeTab: "overview",
    dev: null,
    prod: null,
    errors: {},
    lastRefresh: null,
    refreshTimer: null
  };

  const endpoints = ["health", "summary", "objects", "tables", "changelog", "project-control"];

  const els = {};

  document.addEventListener("DOMContentLoaded", init);

  function init() {
    els.title = document.getElementById("dashboard-title");
    els.schemaName = document.getElementById("schema-name");
    els.devApiStatus = document.getElementById("dev-api-status");
    els.prodApiStatus = document.getElementById("prod-api-status");
    els.lastRefresh = document.getElementById("last-refresh");
    els.configWarning = document.getElementById("config-warning");
    els.refreshButton = document.getElementById("refresh-button");
    els.autoRefresh = document.getElementById("auto-refresh-toggle");
    els.panels = {
      overview: document.getElementById("tab-overview"),
      development: document.getElementById("tab-development"),
      production: document.getElementById("tab-production"),
      compare: document.getElementById("tab-compare"),
      history: document.getElementById("tab-history")
    };

    els.title.textContent = `${config.projectName} Demo Dashboard`;
    els.schemaName.textContent = config.schemaName;

    document.querySelectorAll(".tab").forEach((button) => {
      button.addEventListener("click", () => activateTab(button.dataset.tab));
    });

    els.refreshButton.addEventListener("click", refresh);
    els.autoRefresh.addEventListener("change", toggleAutoRefresh);
    els.autoRefresh.checked = Number(config.refreshSeconds) > 0;

    renderConfigWarning();
    refresh();
    toggleAutoRefresh();
  }

  function renderConfigWarning() {
    const missing = [];
    if (!isRealApiUrl(config.devApiBaseUrl)) missing.push("DEV");
    if (!isRealApiUrl(config.prodApiBaseUrl)) missing.push("PROD");

    if (missing.length === 0) {
      els.configWarning.classList.add("hidden");
      return;
    }

    els.configWarning.classList.remove("hidden");
    els.configWarning.textContent = `Configure ${missing.join(" and ")} ORDS API URLs in frontend/config.local.js before using live data.`;
  }

  function isRealApiUrl(url) {
    return typeof url === "string" && url.trim() !== "" && !url.includes("example.com");
  }

  function activateTab(tabName) {
    state.activeTab = tabName;
    document.querySelectorAll(".tab").forEach((button) => {
      button.classList.toggle("is-active", button.dataset.tab === tabName);
    });
    Object.entries(els.panels).forEach(([name, panel]) => {
      panel.classList.toggle("is-active", name === tabName);
    });
  }

  function toggleAutoRefresh() {
    if (state.refreshTimer) {
      window.clearInterval(state.refreshTimer);
      state.refreshTimer = null;
    }

    const seconds = Number(config.refreshSeconds);
    if (els.autoRefresh.checked && seconds > 0) {
      state.refreshTimer = window.setInterval(refresh, seconds * 1000);
    }
  }

  async function refresh() {
    els.refreshButton.disabled = true;
    els.refreshButton.textContent = "Refreshing";

    const [dev, prod] = await Promise.all([
      loadEnvironment("dev", config.devApiBaseUrl),
      loadEnvironment("prod", config.prodApiBaseUrl)
    ]);

    state.dev = dev.data;
    state.prod = prod.data;
    state.errors.dev = dev.error;
    state.errors.prod = prod.error;
    state.lastRefresh = new Date();

    render();

    els.refreshButton.disabled = false;
    els.refreshButton.textContent = "Refresh";
  }

  async function loadEnvironment(name, baseUrl) {
    if (!isRealApiUrl(baseUrl)) {
      return {
        data: null,
        error: `${name.toUpperCase()} API URL is not configured.`
      };
    }

    const data = {};
    try {
      await Promise.all(endpoints.map(async (endpoint) => {
        data[toCamel(endpoint)] = await fetchJson(apiUrl(baseUrl, endpoint));
      }));
      return { data, error: null };
    } catch (err) {
      return { data: null, error: err.message || String(err) };
    }
  }

  async function fetchJson(url) {
    const response = await fetch(url, {
      method: "GET",
      headers: { "Accept": "application/json" },
      cache: "no-store"
    });

    if (!response.ok) {
      throw new Error(`${response.status} ${response.statusText} for ${url}`);
    }

    return response.json();
  }

  function apiUrl(baseUrl, endpoint) {
    return `${String(baseUrl).replace(/\/+$/, "")}/${endpoint.replace(/^\/+/, "")}/`;
  }

  function toCamel(value) {
    return value.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
  }

  function render() {
    els.devApiStatus.textContent = envStatusText("dev");
    els.prodApiStatus.textContent = envStatusText("prod");
    els.lastRefresh.textContent = state.lastRefresh ? formatDateTime(state.lastRefresh) : "Never";

    renderOverview();
    renderEnvironment("development", "DEV", state.dev, state.errors.dev);
    renderEnvironment("production", "PROD", state.prod, state.errors.prod);
    renderCompare();
    renderHistory();
  }

  function envStatusText(name) {
    if (state.errors[name]) return "Error";
    if (state[name]) return "Connected";
    return "Not configured";
  }

  function renderOverview() {
    const devSummary = getSummary(state.dev);
    const prodSummary = getSummary(state.prod);
    const prodVersion = latestReleaseVersion(state.prod);
    const diff = buildCompareModel();

    els.panels.overview.innerHTML = `
      <div class="stack">
        <div class="grid two">
          ${environmentCard("DEV", state.dev, state.errors.dev)}
          ${environmentCard("PROD", state.prod, state.errors.prod, prodVersion)}
        </div>
        <div class="panel">
          <h2>Demo Flow</h2>
          <div class="timeline">
            ${timelineStep("Reset", "Initial schema in DEV, empty PROD control")}
            ${timelineStep("Create Project", "SQLcl Project scaffold")}
            ${timelineStep("Base Release", "Capture baseline")}
            ${timelineStep("v1 Branch", "First schema change set")}
            ${timelineStep("v2 Branch", "Second schema change set")}
            ${timelineStep("Release 1.1", "Close accumulated changes")}
            ${timelineStep("Deploy", "Apply artifact to PROD")}
          </div>
        </div>
        <div class="grid three">
          ${metricPanel(countObjects(devSummary), "Current schema objects", "DEV Objects")}
          ${metricPanel(countObjects(prodSummary), "Current schema objects", "PROD Objects")}
          ${metricPanel(diff.totalDifferences, "Application differences", "DEV vs PROD Drift")}
        </div>
      </div>
    `;
  }

  function environmentCard(label, env, error, releaseVersion) {
    if (error) {
      return `
        <div class="panel">
          <h2>${escapeHtml(label)}</h2>
          <p class="badge bad">Unavailable</p>
          <p class="error">${escapeHtml(error)}</p>
        </div>
      `;
    }

    if (!env) {
      return `
        <div class="panel">
          <h2>${escapeHtml(label)}</h2>
          <p class="badge warn">Not configured</p>
        </div>
      `;
    }

    const health = env.health || {};
    const summary = getSummary(env);
    const invalidCount = Number(health.invalidObjectCount || 0);

    return `
      <div class="panel">
        <h2>${escapeHtml(label)}</h2>
        <div class="metric-row">
          ${miniMetric("Tables", getObjectTypeCount(summary, "TABLE"))}
          ${miniMetric("Views", getObjectTypeCount(summary, "VIEW"))}
          ${miniMetric("Indexes", getObjectTypeCount(summary, "INDEX"))}
          ${miniMetric("Invalid", invalidCount)}
        </div>
        <p>
          <span class="badge ${invalidCount > 0 ? "bad" : "ok"}">${invalidCount > 0 ? "Invalid objects" : "Valid objects"}</span>
          ${releaseVersion ? `<span class="badge info">Release ${escapeHtml(releaseVersion)}</span>` : ""}
        </p>
      </div>
    `;
  }

  function timelineStep(title, detail) {
    return `
      <div class="timeline-step">
        <strong>${escapeHtml(title)}</strong>
        <span>${escapeHtml(detail)}</span>
      </div>
    `;
  }

  function metricPanel(value, detail, label) {
    return `
      <div class="panel">
        <div class="metric">
          <strong>${escapeHtml(String(value))}</strong>
          <span>${escapeHtml(label)}</span>
        </div>
        <p class="muted">${escapeHtml(detail)}</p>
      </div>
    `;
  }

  function miniMetric(label, value) {
    return `
      <div class="metric">
        <strong>${escapeHtml(String(value))}</strong>
        <span>${escapeHtml(label)}</span>
      </div>
    `;
  }

  function renderEnvironment(panelName, label, env, error) {
    const panel = els.panels[panelName];

    if (error) {
      panel.innerHTML = `<div class="empty-state">${escapeHtml(error)}</div>`;
      return;
    }

    if (!env) {
      panel.innerHTML = `<div class="empty-state">${label} API URL is not configured.</div>`;
      return;
    }

    const objects = items(env.objects);
    const tables = items(env.tables).filter((row) => row.objectGroup === "APPLICATION");
    const changelog = items(env.changelog);
    const summary = getSummary(env);

    panel.innerHTML = `
      <div class="stack">
        <div class="grid three">
          ${metricPanel(getObjectTypeCount(summary, "TABLE"), "Application and metadata tables", "Tables")}
          ${metricPanel(getObjectTypeCount(summary, "VIEW"), "Current schema views", "Views")}
          ${metricPanel(getObjectTypeCount(summary, "INDEX"), "Current schema indexes", "Indexes")}
        </div>
        <div class="panel">
          <h2>${escapeHtml(label)} Objects</h2>
          ${renderObjectsTable(objects)}
        </div>
        <div class="panel">
          <h2>${escapeHtml(label)} Table Columns</h2>
          ${renderColumnsTable(tables)}
        </div>
        <div class="panel">
          <h2>${escapeHtml(label)} SQLcl Project Changelog</h2>
          ${renderChangelogTable(changelog)}
        </div>
      </div>
    `;
  }

  function renderCompare() {
    const diff = buildCompareModel();

    if (state.errors.dev || state.errors.prod || !state.dev || !state.prod) {
      els.panels.compare.innerHTML = `<div class="empty-state">DEV and PROD API data are required for comparison.</div>`;
      return;
    }

    els.panels.compare.innerHTML = `
      <div class="stack">
        <div class="grid three">
          ${metricPanel(diff.devOnlyTables.length, "Tables present only in development", "DEV-only tables")}
          ${metricPanel(diff.prodOnlyTables.length, "Tables present only in production", "PROD-only tables")}
          ${metricPanel(diff.columnDifferences.length, "Column-level schema differences", "Column differences")}
        </div>
        <div class="panel">
          <h2>Application Table Drift</h2>
          ${renderNameListTable([
            ...diff.devOnlyTables.map((name) => ({ scope: "DEV only", name })),
            ...diff.prodOnlyTables.map((name) => ({ scope: "PROD only", name }))
          ], "Table")}
        </div>
        <div class="panel">
          <h2>Application Column Drift</h2>
          ${renderColumnDiffTable(diff.columnDifferences)}
        </div>
      </div>
    `;
  }

  function renderHistory() {
    if (state.errors.prod || !state.prod) {
      els.panels.history.innerHTML = `<div class="empty-state">PROD API data are required for deploy history.</div>`;
      return;
    }

    const projectControl = items(state.prod.projectControl);

    els.panels.history.innerHTML = `
      <div class="stack">
        <div class="panel">
          <h2>Production Deploy History</h2>
          ${renderProjectControlTable(projectControl)}
        </div>
      </div>
    `;
  }

  function renderObjectsTable(rows) {
    if (rows.length === 0) return empty("No objects returned.");
    return table([
      "Type", "Name", "Status", "Group", "Last DDL"
    ], rows.map((row) => [
      row.objectType,
      row.objectName,
      statusBadge(row.status),
      row.objectGroup,
      row.lastDdlTime
    ]));
  }

  function renderColumnsTable(rows) {
    if (rows.length === 0) return empty("No table columns returned.");
    return table([
      "Table", "Column", "Type", "Nullable", "PK", "FK"
    ], rows.map((row) => [
      row.tableName,
      row.columnName,
      row.dataTypeDisplay,
      row.nullable,
      row.isPrimaryKey,
      row.isForeignKey
    ]));
  }

  function renderChangelogTable(rows) {
    if (rows.length === 0) return empty("No SQLcl Project or Liquibase changelog entries found.");
    return table([
      "Order", "ID", "Author", "File", "Executed", "Type"
    ], rows.map((row) => [
      row.orderExecuted,
      row.id,
      row.author,
      row.filename,
      row.dateExecuted,
      row.execType
    ]));
  }

  function renderProjectControlTable(rows) {
    if (rows.length === 0) return empty("No production deployment has been recorded in PROJECT_CONTROL.");
    return table([
      "Version", "Status", "Artifact", "Deployed At", "Actor", "Run", "SHA"
    ], rows.map((row) => [
      row.releaseVersion,
      statusBadge(row.deployStatus),
      row.artifactName,
      row.deployedAt,
      row.deployedBy,
      row.githubRunId,
      row.githubSha
    ]));
  }

  function renderNameListTable(rows, label) {
    if (rows.length === 0) return empty(`No ${label.toLowerCase()} drift detected.`);
    return table(["Scope", label], rows.map((row) => [row.scope, row.name]));
  }

  function renderColumnDiffTable(rows) {
    if (rows.length === 0) return empty("No column drift detected.");
    return table([
      "Scope", "Table", "Column", "DEV", "PROD"
    ], rows.map((row) => [
      row.scope,
      row.tableName,
      row.columnName,
      row.dev || "",
      row.prod || ""
    ]));
  }

  function table(headers, rows) {
    return `
      <div class="table-wrap">
        <table>
          <thead>
            <tr>${headers.map((header) => `<th>${escapeHtml(header)}</th>`).join("")}</tr>
          </thead>
          <tbody>
            ${rows.map((row) => `
              <tr>${row.map((cell) => `<td>${cell && String(cell).startsWith("<span") ? cell : escapeHtml(cell)}</td>`).join("")}</tr>
            `).join("")}
          </tbody>
        </table>
      </div>
    `;
  }

  function empty(text) {
    return `<div class="empty-state">${escapeHtml(text)}</div>`;
  }

  function statusBadge(status) {
    const value = String(status || "UNKNOWN").toUpperCase();
    let css = "info";
    if (value === "VALID" || value === "SUCCESS") css = "ok";
    if (value === "INVALID" || value === "FAILED" || value === "ERROR") css = "bad";
    if (value === "WARNING") css = "warn";
    return `<span class="badge ${css}">${escapeHtml(value)}</span>`;
  }

  function buildCompareModel() {
    const devTables = applicationColumns(state.dev);
    const prodTables = applicationColumns(state.prod);
    const devTableNames = unique(devTables.map((row) => row.tableName));
    const prodTableNames = unique(prodTables.map((row) => row.tableName));
    const devOnlyTables = difference(devTableNames, prodTableNames);
    const prodOnlyTables = difference(prodTableNames, devTableNames);
    const devColumns = columnMap(devTables);
    const prodColumns = columnMap(prodTables);
    const allColumnKeys = unique([...Object.keys(devColumns), ...Object.keys(prodColumns)]).sort();

    const columnDifferences = allColumnKeys.reduce((result, key) => {
      const dev = devColumns[key];
      const prod = prodColumns[key];

      if (!dev) {
        result.push({
          scope: "PROD only",
          tableName: prod.tableName,
          columnName: prod.columnName,
          dev: "",
          prod: columnSignature(prod)
        });
      } else if (!prod) {
        result.push({
          scope: "DEV only",
          tableName: dev.tableName,
          columnName: dev.columnName,
          dev: columnSignature(dev),
          prod: ""
        });
      } else if (columnSignature(dev) !== columnSignature(prod)) {
        result.push({
          scope: "Changed",
          tableName: dev.tableName,
          columnName: dev.columnName,
          dev: columnSignature(dev),
          prod: columnSignature(prod)
        });
      }

      return result;
    }, []);

    return {
      devOnlyTables,
      prodOnlyTables,
      columnDifferences,
      totalDifferences: devOnlyTables.length + prodOnlyTables.length + columnDifferences.length
    };
  }

  function applicationColumns(env) {
    return items(env && env.tables).filter((row) => row.objectGroup === "APPLICATION");
  }

  function columnMap(rows) {
    return rows.reduce((map, row) => {
      map[`${row.tableName}.${row.columnName}`] = row;
      return map;
    }, {});
  }

  function columnSignature(row) {
    return `${row.dataTypeDisplay}; nullable=${row.nullable}; pk=${row.isPrimaryKey}; fk=${row.isForeignKey}`;
  }

  function unique(values) {
    return Array.from(new Set(values.filter(Boolean))).sort();
  }

  function difference(left, right) {
    const rightSet = new Set(right);
    return left.filter((value) => !rightSet.has(value));
  }

  function getSummary(env) {
    return (env && env.summary) || {};
  }

  function items(payload) {
    if (!payload) return [];
    if (Array.isArray(payload)) return payload;
    if (Array.isArray(payload.items)) return payload.items;
    return [];
  }

  function countObjects(summary) {
    return items(summary.objectCounts).reduce((total, row) => total + Number(row.totalCount || 0), 0);
  }

  function getObjectTypeCount(summary, type) {
    const row = items(summary.objectCounts).find((item) => item.objectType === type);
    return Number(row && row.totalCount || 0);
  }

  function latestReleaseVersion(env) {
    const rows = items(env && env.projectControl);
    return rows.length > 0 ? rows[0].releaseVersion : "";
  }

  function formatDateTime(date) {
    return new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium",
      timeStyle: "medium"
    }).format(date);
  }

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }
})();
