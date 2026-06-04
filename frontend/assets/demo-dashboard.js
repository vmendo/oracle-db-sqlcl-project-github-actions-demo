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
    refreshTimer: null,
    filters: {
      development: { objectType: "ALL", tableName: "" },
      production: { objectType: "ALL", tableName: "" }
    },
    deployAudit: {
      selectedKey: ""
    }
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
      history: document.getElementById("tab-history"),
      audit: document.getElementById("tab-audit")
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
    renderDeployAudit();
  }

  function envStatusText(name) {
    if (state.errors[name]) return "Error";
    if (state[name]) return "Connected";
    return "Not configured";
  }

  function renderOverview() {
    const devObjects = applicationObjects(state.dev);
    const prodObjects = applicationObjects(state.prod);
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
          ${metricPanel(devObjects.length, "Application schema objects", "DEV Objects")}
          ${metricPanel(prodObjects.length, "Application schema objects", "PROD Objects")}
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

    const objects = applicationObjects(env);
    const invalidCount = countInvalidObjects(objects);

    return `
      <div class="panel">
        <h2>${escapeHtml(label)}</h2>
        <div class="metric-row">
          ${miniMetric("Tables", countObjectTypeRows(objects, "TABLE"))}
          ${miniMetric("Views", countObjectTypeRows(objects, "VIEW"))}
          ${miniMetric("Indexes", countObjectTypeRows(objects, "INDEX"))}
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

    const objects = applicationObjects(env);
    const tables = applicationColumns(env);
    const changelog = items(env.changelog);
    const filter = normalizeEnvironmentFilter(panelName, objects, tables);
    const filteredObjects = filter.objectType === "ALL"
      ? objects
      : objects.filter((row) => row.objectType === filter.objectType);
    const selectedTableColumns = tables.filter((row) => row.tableName === filter.tableName);

    panel.innerHTML = `
      <div class="stack">
        <div class="grid three">
          ${metricPanel(countObjectTypeRows(objects, "TABLE"), "Application tables only", "Tables")}
          ${metricPanel(countObjectTypeRows(objects, "VIEW"), "Application views only", "Views")}
          ${metricPanel(countObjectTypeRows(objects, "INDEX"), "Application indexes only", "Indexes")}
        </div>
        <div class="panel">
          <div class="panel-heading">
            <h2>${escapeHtml(label)} Objects</h2>
            ${renderObjectTypeFilter(panelName, objects, filter.objectType)}
          </div>
          ${renderObjectsTable(filteredObjects)}
        </div>
        <div class="panel">
          <div class="panel-heading">
            <h2>${escapeHtml(label)} Table Columns</h2>
            ${renderTablePicker(panelName, tables, filter.tableName)}
          </div>
          ${renderSelectedTableSummary(filter.tableName, selectedTableColumns)}
          ${renderColumnsTable(selectedTableColumns)}
        </div>
        <div class="panel">
          <h2>${escapeHtml(label)} SQLcl Project Changelog</h2>
          ${renderChangelogTable(changelog)}
        </div>
      </div>
    `;

    panel.querySelector(`[data-object-filter="${panelName}"]`)?.addEventListener("change", (event) => {
      state.filters[panelName].objectType = event.target.value;
      renderEnvironment(panelName, label, env, error);
    });

    panel.querySelector(`[data-table-picker="${panelName}"]`)?.addEventListener("change", (event) => {
      state.filters[panelName].tableName = event.target.value;
      renderEnvironment(panelName, label, env, error);
    });
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

  function renderDeployAudit() {
    if (state.errors.prod || !state.prod) {
      els.panels.audit.innerHTML = `<div class="empty-state">PROD API data are required for deploy audit.</div>`;
      return;
    }

    const audit = buildDeployAuditModel();
    normalizeSelectedDeploy(audit.deploys);
    const selectedDeploy = audit.deploys.find((deploy) => deploy.key === state.deployAudit.selectedKey);
    const selectedChanges = selectedDeploy ? audit.changesByDeploy[selectedDeploy.key] || [] : [];

    els.panels.audit.innerHTML = `
      <div class="stack">
        <div class="grid three">
          ${metricPanel(audit.deploys.length, "Liquibase deploy groups in production", "Deploys")}
          ${metricPanel(audit.totalChanges, "Executed production changesets", "Changesets")}
          ${metricPanel(selectedChanges.length, selectedDeploy ? selectedDeploy.label : "No deploy selected", "Selected Changes")}
        </div>
        <div class="panel">
          <h2>Production Deploy Audit</h2>
          ${renderDeployAuditTable(audit.deploys)}
        </div>
        <div class="panel">
          <div class="panel-heading">
            <h2>Applied Changes</h2>
            ${selectedDeploy ? `<span class="badge info">${escapeHtml(selectedDeploy.label)}</span>` : ""}
          </div>
          ${selectedDeploy ? renderDeployChangeTable(selectedChanges) : empty("Select a deploy to inspect its Liquibase changesets.")}
        </div>
      </div>
    `;

    els.panels.audit.querySelectorAll("[data-deploy-key]").forEach((button) => {
      button.addEventListener("click", () => {
        state.deployAudit.selectedKey = button.dataset.deployKey;
        renderDeployAudit();
      });
    });
  }

  function renderObjectsTable(rows) {
    if (rows.length === 0) return empty("No objects returned.");
    return table([
      "Type", "Name", "Status", "Last DDL"
    ], rows.map((row) => [
      row.objectType,
      row.objectName,
      statusBadge(row.status),
      row.lastDdlTime
    ]));
  }

  function renderObjectTypeFilter(panelName, rows, selectedType) {
    const objectTypes = unique(rows.map((row) => row.objectType));
    return `
      <label class="filter-control">
        <span>Object type</span>
        <select data-object-filter="${escapeHtml(panelName)}">
          <option value="ALL"${selectedType === "ALL" ? " selected" : ""}>All application objects</option>
          ${objectTypes.map((type) => `
            <option value="${escapeHtml(type)}"${selectedType === type ? " selected" : ""}>${escapeHtml(titleCase(type))}</option>
          `).join("")}
        </select>
      </label>
    `;
  }

  function renderTablePicker(panelName, rows, selectedTable) {
    const tableNames = unique(rows.map((row) => row.tableName));
    if (tableNames.length === 0) return "";

    return `
      <label class="filter-control">
        <span>Table</span>
        <select data-table-picker="${escapeHtml(panelName)}">
          ${tableNames.map((tableName) => `
            <option value="${escapeHtml(tableName)}"${selectedTable === tableName ? " selected" : ""}>${escapeHtml(tableName)}</option>
          `).join("")}
        </select>
      </label>
    `;
  }

  function renderSelectedTableSummary(tableName, rows) {
    if (!tableName) return empty("No application table is available.");
    const primaryKeys = rows.filter((row) => row.isPrimaryKey === "Y").length;
    const foreignKeys = rows.filter((row) => row.isForeignKey === "Y").length;

    return `
      <div class="selection-summary">
        <strong>${escapeHtml(tableName)}</strong>
        <span>${escapeHtml(String(rows.length))} columns</span>
        <span>${escapeHtml(String(primaryKeys))} PK columns</span>
        <span>${escapeHtml(String(foreignKeys))} FK columns</span>
      </div>
    `;
  }

  function renderColumnsTable(rows) {
    if (rows.length === 0) return empty("No table columns returned.");
    return table([
      "Column", "Type", "Nullable", "PK", "FK"
    ], rows.map((row) => [
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

  function renderDeployAuditTable(rows) {
    if (rows.length === 0) return empty("No production Liquibase deploy history found.");

    return `
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Deploy</th>
              <th>Changes</th>
              <th>First Applied</th>
              <th>Last Applied</th>
              <th>Author</th>
              <th>Source</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            ${rows.map((deploy) => `
              <tr class="${deploy.key === state.deployAudit.selectedKey ? "is-selected" : ""}">
                <td>
                  <button class="table-action" type="button" data-deploy-key="${escapeHtml(deploy.key)}">
                    ${escapeHtml(deploy.label)}
                  </button>
                </td>
                <td>${escapeHtml(String(deploy.changeCount))}</td>
                <td>${escapeHtml(deploy.firstExecuted)}</td>
                <td>${escapeHtml(deploy.lastExecuted)}</td>
                <td>${escapeHtml(deploy.author)}</td>
                <td>${escapeHtml(deploy.source)}</td>
                <td>${statusBadge(deploy.status)}</td>
              </tr>
            `).join("")}
          </tbody>
        </table>
      </div>
    `;
  }

  function renderDeployChangeTable(rows) {
    if (rows.length === 0) return empty("No changesets found for the selected deploy.");

    return table([
      "Order", "Category", "Object", "File", "Executed", "Type"
    ], rows.map((row) => [
      row.orderExecuted,
      changeCategory(row.filename),
      changeObjectName(row.filename),
      row.filename,
      row.dateExecuted,
      row.execType
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

  function buildDeployAuditModel() {
    const changes = items(state.prod && state.prod.changelog)
      .filter((row) => row && row.filename)
      .slice()
      .sort((left, right) => Number(left.orderExecuted || 0) - Number(right.orderExecuted || 0));
    const projectControl = items(state.prod && state.prod.projectControl);
    const groups = changes.reduce((map, row) => {
      const key = deployKeyFromFilename(row.filename);
      if (!map[key]) map[key] = [];
      map[key].push(row);
      return map;
    }, {});
    const controlByRelease = projectControl.reduce((map, row) => {
      deployControlKeys(row).forEach((key) => {
        map[key] = row;
      });
      return map;
    }, {});
    const deploys = Object.entries(groups).map(([key, groupRows]) => {
      const control = controlByRelease[normalizeDeployKey(key)] || null;
      return {
        key,
        label: control && control.releaseVersion ? `Release ${control.releaseVersion}` : deployLabel(key),
        changeCount: groupRows.length,
        firstExecuted: groupRows[0] && groupRows[0].dateExecuted || "",
        lastExecuted: groupRows[groupRows.length - 1] && groupRows[groupRows.length - 1].dateExecuted || "",
        author: unique(groupRows.map((row) => row.author)).join(", "),
        source: control && control.artifactName ? control.artifactName : key,
        status: control && control.deployStatus ? control.deployStatus : groupStatus(groupRows)
      };
    }).sort((left, right) => String(right.lastExecuted).localeCompare(String(left.lastExecuted)));

    return {
      deploys,
      changesByDeploy: groups,
      totalChanges: changes.length
    };
  }

  function normalizeSelectedDeploy(deploys) {
    if (deploys.some((deploy) => deploy.key === state.deployAudit.selectedKey)) return;
    state.deployAudit.selectedKey = deploys[0] ? deploys[0].key : "";
  }

  function deployKeyFromFilename(filename) {
    const firstSegment = String(filename || "").split("/")[0];
    return firstSegment || "unknown";
  }

  function deployLabel(key) {
    const value = String(key || "unknown");
    if (value === "dev_base_release" || value === "base_release") return "Base Release";
    const versionMatch = value.match(/^dev_version(\d+)$/);
    if (versionMatch) {
      const digits = versionMatch[1];
      return digits.length > 1 ? `Version ${digits.charAt(0)}.${digits.slice(1)}` : `Version ${digits}`;
    }
    return titleCase(value.replace(/^dev_/, "").replace(/-/g, "_"));
  }

  function normalizeDeployKey(value) {
    return String(value || "")
      .toLowerCase()
      .replace(/\.zip$/, "")
      .replace(/[^a-z0-9]+/g, "");
  }

  function deployControlKeys(row) {
    const keys = new Set();
    [row.releaseVersion, row.releaseTag, row.artifactName].forEach((value) => {
      const normalized = normalizeDeployKey(value);
      if (normalized) keys.add(normalized);
      versionAliasKeys(value).forEach((key) => keys.add(key));
    });
    return Array.from(keys);
  }

  function versionAliasKeys(value) {
    const match = String(value || "").match(/(\d+(?:\.\d+)+)/);
    if (!match) return [];

    const parts = match[1].split(".");
    const aliases = new Set();
    const fullDigits = parts.join("");
    aliases.add(`devversion${fullDigits}`);
    aliases.add(`version${fullDigits}`);

    if (parts.length > 2 && parts[parts.length - 1] === "0") {
      const trimmedDigits = parts.slice(0, -1).join("");
      aliases.add(`devversion${trimmedDigits}`);
      aliases.add(`version${trimmedDigits}`);
    }

    return Array.from(aliases);
  }

  function groupStatus(rows) {
    return rows.some((row) => String(row.execType || "").toUpperCase() !== "EXECUTED") ? "WARNING" : "SUCCESS";
  }

  function changeCategory(filename) {
    const parts = String(filename || "").split("/");
    return titleCase(parts.length > 2 ? parts[2] : "change");
  }

  function changeObjectName(filename) {
    const fileName = String(filename || "").split("/").pop() || "";
    return fileName.replace(/\.sql$/i, "").toUpperCase();
  }

  function applicationColumns(env) {
    return items(env && env.tables).filter(isApplicationTableColumn);
  }

  function applicationObjects(env) {
    return items(env && env.objects).filter(isApplicationObject);
  }

  function isApplicationTableColumn(row) {
    const tableName = String(row && row.tableName || "");
    return row
      && row.objectGroup === "APPLICATION"
      && !isDemoMetadataName(tableName)
      && !isSystemGeneratedName(tableName);
  }

  function isApplicationObject(row) {
    const objectName = String(row && row.objectName || "");
    return row
      && row.objectGroup === "APPLICATION"
      && !isDemoMetadataName(objectName)
      && !isSystemGeneratedName(objectName);
  }

  function isDemoMetadataName(name) {
    const normalized = String(name || "").toUpperCase();
    return normalized.includes("PROJECT_CONTROL")
      || normalized.includes("DATABASECHANGELOG")
      || normalized.includes("DBTOOLS$")
      || normalized.startsWith("ORDS_")
      || normalized.startsWith("ORDS$");
  }

  function isSystemGeneratedName(name) {
    const normalized = String(name || "").toUpperCase();
    return normalized.startsWith("SYS_")
      || normalized.startsWith("SYS$")
      || normalized.startsWith("BIN$")
      || normalized.startsWith("MLOG$_")
      || normalized.startsWith("RUPD$_")
      || normalized.startsWith("AQ$");
  }

  function normalizeEnvironmentFilter(panelName, objects, tables) {
    const filter = state.filters[panelName] || { objectType: "ALL", tableName: "" };
    const objectTypes = unique(objects.map((row) => row.objectType));
    const tableNames = unique(tables.map((row) => row.tableName));

    if (filter.objectType !== "ALL" && !objectTypes.includes(filter.objectType)) {
      filter.objectType = "ALL";
    }

    if (!filter.tableName || !tableNames.includes(filter.tableName)) {
      filter.tableName = tableNames[0] || "";
    }

    state.filters[panelName] = filter;
    return filter;
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

  function items(payload) {
    if (!payload) return [];
    if (Array.isArray(payload)) return payload;
    if (Array.isArray(payload.items)) return payload.items;
    return [];
  }

  function countObjectTypeRows(rows, type) {
    return rows.filter((row) => row.objectType === type).length;
  }

  function countInvalidObjects(rows) {
    return rows.filter((row) => String(row.status || "").toUpperCase() !== "VALID").length;
  }

  function titleCase(value) {
    return String(value || "")
      .toLowerCase()
      .split("_")
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
      .join(" ");
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
