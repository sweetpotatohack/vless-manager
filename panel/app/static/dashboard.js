(function () {
  const grid = document.getElementById("node-metrics-grid");
  const updatedEl = document.getElementById("metrics-updated");
  const liveDot = document.getElementById("metrics-live-dot");
  if (!grid) return;

  const ARC_LEN = 75.4;

  function level(pct) {
    if (pct == null || Number.isNaN(pct)) return "none";
    if (pct >= 90) return "bad";
    if (pct >= 75) return "warn";
    return "ok";
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function fmtPct(pct) {
    if (pct == null || Number.isNaN(pct)) return "—";
    return pct.toFixed(1) + "%";
  }

  /** Zabbix-style half gauge (fixed 88×48 px) */
  function gauge(label, pct) {
    const lv = level(pct);
    const p = pct == null ? 0 : Math.min(100, Math.max(0, pct));
    const off = ARC_LEN * (1 - p / 100);
    return (
      '<div class="z-gauge lv-' +
      lv +
      '" title="' +
      escapeHtml(label) +
      ": " +
      fmtPct(pct) +
      '">' +
      '<svg viewBox="0 0 64 40" width="88" height="48" aria-hidden="true">' +
      '<path class="z-gauge-track" d="M6 34 A26 26 0 0 1 58 34" pathLength="' +
      ARC_LEN +
      '" />' +
      '<path class="z-gauge-fill" d="M6 34 A26 26 0 0 1 58 34" pathLength="' +
      ARC_LEN +
      '" stroke-dasharray="' +
      ARC_LEN +
      '" stroke-dashoffset="' +
      off.toFixed(2) +
      '" />' +
      "</svg>" +
      '<div class="z-gauge-val">' +
      fmtPct(pct) +
      "</div>" +
      '<div class="z-gauge-lbl">' +
      escapeHtml(label) +
      "</div></div>"
    );
  }

  function renderNode(n) {
    let dot = "z-dot-off";
    if (!n.missing && !n.stale) dot = "z-dot-live";
    else if (n.stale) dot = "z-dot-warn";

    return (
      '<article class="node-tile" data-node-id="' +
      n.id +
      '">' +
      '<div class="node-tile-head">' +
      '<span class="z-dot ' +
      dot +
      '"></span>' +
      "<strong>" +
      escapeHtml(n.name) +
      "</strong>" +
      '<span class="node-tile-meta">' +
      escapeHtml(n.country) +
      " · " +
      escapeHtml(n.role) +
      "</span></div>" +
      '<div class="node-tile-gauges">' +
      gauge("CPU", n.cpu) +
      gauge("RAM", n.mem) +
      gauge("DISK", n.disk) +
      "</div></article>"
    );
  }

  function setLive(ok) {
    if (!liveDot) return;
    liveDot.classList.toggle("ok", ok);
    liveDot.classList.toggle("err", !ok);
  }

  async function refresh() {
    try {
      const r = await fetch("/api/v1/dashboard/node-metrics", {
        credentials: "same-origin",
        cache: "no-store",
      });
      if (!r.ok) {
        setLive(false);
        return;
      }
      const data = await r.json();
      const nodes = data.nodes || [];
      if (!nodes.length) {
        grid.innerHTML = '<p class="metrics-placeholder">Нет активных нод</p>';
        return;
      }
      grid.innerHTML = nodes.map(renderNode).join("");
      setLive(true);
      if (updatedEl) {
        const t = new Date();
        updatedEl.textContent =
          "обновлено " +
          t.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
      }
    } catch (_e) {
      setLive(false);
    }
  }

  refresh();
  setInterval(refresh, 5000);
})();
