const view = document.getElementById("view");
const title = document.getElementById("pageTitle");
const sub = document.getElementById("pageSub");
const healthPill = document.getElementById("healthPill");
const sidebar = document.getElementById("sidebar");
document.getElementById("menuBtn").onclick = () => sidebar.classList.toggle("open");

const titles = {
  dashboard: ["Overview", "Unusual inventory loss across the network."],
  alerts: ["Alerts", "Evidence-based exceptions, scored and labelled by rule."],
  investigations: ["Investigations", "Traceable case files linked to alerts."],
  counts: ["Cycle counts", "Derived expected qty vs physical counts."],
  movements: ["Movements", "Immutable receipts, sales, transfers, adjustments and returns."],
  stores: ["Stores & SKUs", "Master data, risk tiers and assortment."],
  exceptions: ["Exceptions", "Required negative scenarios and integrity breaks."],
  ledger: ["Stock ledger", "Replay the stock equation for any store/SKU."],
  evaluation: ["Evaluation", "Held-out ground truth is used only on this screen."],
  data: ["Data lab", "Generate starter/full datasets with seed 20261022."],
  alert: ["Alert detail", "Evidence, linked investigation and recent movements."],
};

async function api(path, opts) {
  const res = await fetch(path, opts);
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

function money(n) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 }).format(n || 0);
}
function num(n) { return new Intl.NumberFormat("en-US").format(n || 0); }
function sev(s) { return `<span class="sev-${s}">${s}</span>`; }
function table(headers, rows) {
  return `<div style="overflow:auto"><table><thead><tr>${headers.map(h=>`<th>${h}</th>`).join("")}</tr></thead>
    <tbody>${rows.map(r=>`<tr>${r.map(c=>`<td>${c ?? ""}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`;
}

let charts = [];
function killCharts() { charts.forEach(c => c.destroy()); charts = []; }

async function dashboard() {
  const d = await api("/api/summary");
  const k = d.kpis;
  view.innerHTML = `
    <div class="grid kpis">
      ${[
        ["Open alerts", num(k.open_alerts), "Need operator review"],
        ["Shrink value", money(k.shrink_value), "Negative count variance $"],
        ["Movements", num(k.movements), "Event history, never overwritten"],
        ["Stock equation", k.stock_equation_pass_pct + "%", "Counts vs derived expected qty"],
      ].map(([l,v,s]) => `<article class="card"><div class="kpi-value">${v}</div><div class="kpi-label">${l}</div><p class="muted">${s}</p></article>`).join("")}
    </div>
    <div class="grid two" style="margin-top:16px">
      <article class="card"><h3>Alert mix</h3><canvas id="typeChart"></canvas></article>
      <article class="card"><h3>Alerts by region</h3><canvas id="regionChart"></canvas></article>
    </div>
    <article class="card" style="margin-top:16px">
      <h3>Highest scoring alerts</h3>
      ${table(["Alert","Type","Severity","Score","Store","SKU","Status"],
        d.top_alerts.map(a => [`<span class="mono">${a.alert_id}</span>`, a.alert_type, sev(a.severity), a.score, a.store_id, a.sku_id || "—", a.status]))}
    </article>`;
  charts.push(new Chart(document.getElementById("typeChart"), {
    type: "bar",
    data: { labels: d.alerts_by_type.map(x => x.alert_type), datasets: [{ data: d.alerts_by_type.map(x => x.n), backgroundColor: "#3ee0b2" }] },
    options: { plugins: { legend: { display: false } }, scales: { x: { ticks: { color: "#8aa0b8" } }, y: { ticks: { color: "#8aa0b8" } } } }
  }));
  charts.push(new Chart(document.getElementById("regionChart"), {
    type: "doughnut",
    data: { labels: d.alerts_by_region.map(x => x.region), datasets: [{ data: d.alerts_by_region.map(x => x.alerts), backgroundColor: ["#3ee0b2","#7cb8ff","#f5b942","#ff6b81","#9b8cff"] }] },
    options: { plugins: { legend: { labels: { color: "#eaf2fb" } } } }
  }));
}

async function alerts() {
  const rows = await api("/api/alerts");
  view.innerHTML = `<article class="card"><h3>${rows.length} alerts</h3><div class="list">
    ${rows.map(a => `<a class="item" href="#/alert/${a.alert_id}">
      <strong>${a.alert_id}</strong> · ${a.alert_type} · ${sev(a.severity)} · score ${a.score}
      <div class="muted">${a.store_id} ${a.sku_id || ""} · ${a.status}</div></a>`).join("")}
  </div></article>`;
}

async function alertDetail(id) {
  const a = await api(`/api/alerts/${id}`);
  view.innerHTML = `<article class="card">
    <h2>${a.alert_id}</h2>
    <p>${a.alert_type} · ${sev(a.severity)} · score ${a.score} · ${a.status}</p>
    <p class="muted">${a.store_id} / ${a.sku_id || "network"} · ${a.created_at}</p>
    <h3>Evidence</h3>
    <pre>${JSON.stringify(a.evidence, null, 2)}</pre>
    <h3>Linked investigations</h3>
    ${a.investigations.map(i => `<div class="item"><span class="mono">${i.investigation_id}</span> · ${i.outcome} · ${i.notes}</div>`).join("") || "<p class='muted'>None yet</p>"}
    <h3>Recent movements</h3>
    ${table(["ID","Type","Qty","When","Reason"], a.recent_movements.map(m => [m.movement_id, m.movement_type, m.qty, m.occurred_at, m.reason_code || ""])) }
  </article>`;
}

async function investigations() {
  const rows = await api("/api/investigations");
  view.innerHTML = `<article class="card">${table(["ID","Opened","Outcome","Status","Alerts","Notes"],
    rows.map(r => [r.investigation_id, r.opened_at, r.outcome, r.status, r.alert_ids || "", r.notes]))}</article>`;
}

async function counts() {
  const rows = await api("/api/counts");
  view.innerHTML = `<article class="card">${table(["Count","Store","SKU","Expected","Counted","Variance","Value","Status"],
    rows.map(r => [r.count_id, r.store_id, r.sku_id, r.expected_qty, r.counted_qty, r.variance_qty, money(r.variance_value), r.status]))}
    <p class="muted">expected_qty is replayed from movements at snapshot_as_of. It is never independently sampled.</p></article>`;
}

async function movements() {
  const rows = await api("/api/movements?limit=80");
  view.innerHTML = `<article class="card">${table(["Movement","Store","SKU","Type","Qty","When","Reason","Shift"],
    rows.map(r => [r.movement_id, r.store_id, r.sku_id, r.movement_type, r.qty, r.occurred_at, r.reason_code || "", r.shift_id || ""]))}</article>`;
}

async function stores() {
  const [s, k] = await Promise.all([api("/api/stores"), api("/api/skus")]);
  view.innerHTML = `<div class="split">
    <article class="card"><h3>Stores</h3>${table(["Store","Name","Format","Region","Risk","Alerts","Shrink $"],
      s.map(r => [r.store_id, r.name, r.format, r.region, r.shrink_risk_tier, r.alert_count, money(r.shrink_value)]))}</article>
    <article class="card"><h3>SKUs</h3>${table(["SKU","Name","Category","Theft risk","Alerts"],
      k.map(r => [r.sku_id, r.name, r.category, r.high_theft_risk ? "yes" : "no", r.alert_count]))}</article>
  </div>`;
}

async function exceptions() {
  const e = await api("/api/exceptions");
  view.innerHTML = `
    <article class="card"><h3>Movement refers to wrong store</h3>
      ${table(["Movement","Movement store","Shift store","SKU","Qty"], e.wrong_store_movement.map(r => [r.movement_id, r.movement_store, r.shift_store, r.sku_id, r.qty]))}</article>
    <article class="card" style="margin-top:16px"><h3>Adjustment lacks reason</h3>
      ${table(["Movement","Store","SKU","Qty","When"], e.adjustment_missing_reason.map(r => [r.movement_id, r.store_id, r.sku_id, r.qty, r.occurred_at]))}</article>
    <article class="card" style="margin-top:16px"><h3>Transfer missing inbound (double-counted shrink risk)</h3>
      ${table(["Out movement","Origin","Destination","SKU","Qty"], e.unpaired_transfers.map(r => [r.movement_id, r.origin, r.destination, r.sku_id, r.qty]))}</article>`;
}

async function ledger() {
  view.innerHTML = `<article class="card">
    <div class="filters">
      <input id="sid" placeholder="STORE-000001" value="STORE-000001" />
      <input id="kid" placeholder="SKU-000001" value="SKU-000001" />
      <button class="primary" id="go">Replay stock equation</button>
    </div>
    <div id="out" class="muted">Pick a store and SKU.</div>
  </article>`;
  document.getElementById("go").onclick = async () => {
    const sid = document.getElementById("sid").value.trim();
    const kid = document.getElementById("kid").value.trim();
    try {
      const d = await api(`/api/reconciliation?store_id=${encodeURIComponent(sid)}&sku_id=${encodeURIComponent(kid)}`);
      document.getElementById("out").innerHTML = `<p>Closing on-hand <strong>${d.closing_on_hand}</strong></p>
        ${table(["When","Type","Qty","On hand after","Reason"], d.ledger.map(r => [r.occurred_at, r.movement_type, r.qty, r.on_hand_after, r.reason_code || ""]))}
        <h3>Counts</h3>
        ${table(["Count","Expected","Counted","Variance"], d.counts.map(r => [r.count_id, r.expected_qty, r.counted_qty, r.variance_qty]))}`;
    } catch (err) { document.getElementById("out").innerHTML = `<p class="toast">${err.message}</p>`; }
  };
}

async function evaluation() {
  const e = await api("/api/evaluation");
  view.innerHTML = `<article class="card">
    <p class="muted">Ground truth lives in data/*/labels and is not joined into feature endpoints.</p>
    <div class="grid kpis">
      <div class="card"><div class="kpi-value">${e.pattern_recall}</div><div class="kpi-label">Pattern recall</div></div>
      <div class="card"><div class="kpi-value">${e.pattern_precision_proxy ?? "—"}</div><div class="kpi-label">Precision proxy</div></div>
      <div class="card"><div class="kpi-value">${num(e.alert_rows)}</div><div class="kpi-label">Detector alerts</div></div>
      <div class="card"><div class="kpi-value">${num(e.planted_benign_rows)}</div><div class="kpi-label">Benign labelled rows</div></div>
    </div>
    <p>Caught: ${e.issue_types_caught.join(", ") || "none"}</p>
    <p>Missed: ${e.issue_types_missed.join(", ") || "none"}</p>
    <p>Benign explanations: ${e.benign_explanations_represented.join(", ")}</p>
  </article>`;
}

async function dataLab() {
  let validation = null;
  try { validation = await api("/api/validation"); } catch {}
  view.innerHTML = `<article class="card">
    <p>Fixed seed <span class="mono">20261022</span>. Starter and full share the same generator.</p>
    <div class="filters">
      <select id="scale"><option value="starter">starter (fast demo)</option><option value="full">full (100 stores / 1M movements)</option></select>
      <button class="primary" id="gen">Generate dataset</button>
    </div>
    <pre id="log">${validation ? JSON.stringify(validation, null, 2) : "No validation file yet."}</pre>
  </article>`;
  document.getElementById("gen").onclick = async () => {
    const scale = document.getElementById("scale").value;
    document.getElementById("log").textContent = "Generating " + scale + "… this can take a while for full.";
    try {
      const r = await api(`/api/generate?scale=${scale}`, { method: "POST" });
      document.getElementById("log").textContent = JSON.stringify(r, null, 2);
    } catch (err) { document.getElementById("log").textContent = err.message; }
  };
}

const routes = { dashboard, alerts, investigations, counts, movements, stores, exceptions, ledger, evaluation, data: dataLab };

async function render() {
  killCharts();
  const hash = (location.hash.replace("#/", "") || "dashboard").split("/");
  const name = hash[0];
  sidebar.classList.remove("open");
  document.querySelectorAll("nav a").forEach(a => a.classList.toggle("active", a.dataset.route === name));
  const meta = titles[name] || titles.dashboard;
  title.textContent = meta[0];
  sub.textContent = meta[1];
  try {
    if (name === "alert") await alertDetail(hash[1]);
    else await (routes[name] || dashboard)();
  } catch (err) {
    view.innerHTML = `<article class="card"><p class="toast">${err.message}</p>
      <p>If no dataset exists, open Data lab and generate the starter set.</p></article>`;
  }
}

async function boot() {
  try {
    const h = await api("/api/health");
    healthPill.textContent = h.dataset ? "dataset ready" : "no dataset";
  } catch { healthPill.textContent = "api offline"; }
  render();
}
window.addEventListener("hashchange", render);
boot();
