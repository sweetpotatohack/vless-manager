(function () {
  const grid = document.getElementById("node-metrics-grid");
  if (!grid) return;

  function level(pct) {
    if (pct == null || Number.isNaN(pct)) return "none";
    if (pct >= 90) return "bad";
    if (pct >= 75) return "warn";
    return "ok";
  }

  function fmt(pct) {
    if (pct == null || Number.isNaN(pct)) return "—";
    return pct.toFixed(1) + "%";
  }

  function barRow(label, pct) {
    const lv = level(pct);
    const w = pct == null ? 0 : Math.min(100, Math.max(0, pct));
    return (
      '<div class="metric-row">' +
      '<div class="metric-row-head"><span>' +
      label +
      '</span><span class="metric-pct">' +
      fmt(pct) +
      "</span></div>" +
      '<div class="metric-bar"><div class="metric-bar-fill lv-' +
      lv +
      '" style="width:' +
      w +
      '%"></div></div></div>'
    );
  }

  function renderCard(n) {
    const stale = n.stale ? '<span class="badge badge-warn">устарело</span>' : "";
    const off =
      n.agent_status && n.agent_status !== "online" && n.role !== "master"
        ? '<span class="badge badge-bad">' + n.agent_status + "</span>"
        : "";
    return (
      '<article class="node-monitor" data-node-id="' +
      n.id +
      '">' +
      '<header class="node-monitor-head">' +
      "<div><strong>" +
      escapeHtml(n.name) +
      "</strong> " +
      off +
      stale +
      "</div>" +
      '<div class="node-monitor-meta">' +
      escapeHtml(n.country) +
      " · " +
      escapeHtml(n.role) +
      "</div></header>" +
      barRow("CPU", n.cpu) +
      barRow("RAM", n.mem) +
      barRow("Диск", n.disk) +
      "</article>"
    );
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  async function refresh() {
    try {
      const r = await fetch("/api/v1/dashboard/node-metrics", { credentials: "same-origin" });
      if (!r.ok) return;
      const data = await r.json();
      grid.innerHTML = (data.nodes || []).map(renderCard).join("");
    } catch (_e) {
      /* ignore */
    }
  }

  setInterval(refresh, 30000);
})();
