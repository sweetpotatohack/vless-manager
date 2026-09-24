(function () {
  const grid = document.getElementById("node-metrics-grid");
  const updatedEl = document.getElementById("metrics-updated");
  const liveDot = document.getElementById("metrics-live-dot");
  if (!grid) return;

  const COLORS = {
    ok: "#22d3ee",
    warn: "#fbbf24",
    bad: "#f87171",
    none: "#475569",
  };

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

  /** Полукруг на CSS (без SVG — не ломается от масштаба) */
  function gauge(label, pct) {
    const lv = level(pct);
    const p = pct == null ? 0 : Math.min(100, Math.max(0, pct));
    const color = COLORS[lv];
    return (
      '<div class="arc-gauge lv-' +
      lv +
      '" style="--pct:' +
      p +
      ";--gauge-color:" +
      color +
      '">' +
      '<div class="arc-gauge-shell" aria-hidden="true">' +
      '<div class="arc-gauge-fill"></div>' +
      '<div class="arc-gauge-track"></div>' +
      "</div>" +
      '<div class="arc-gauge-val">' +
      fmtPct(pct) +
      "</div>" +
      '<div class="arc-gauge-lbl">' +
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
      '<header class="node-tile-head">' +
      '<div class="node-tile-title">' +
      '<span class="z-dot ' +
      dot +
      '" title="Статус метрик"></span>' +
      "<strong>" +
      escapeHtml(n.name) +
      "</strong></div>" +
      '<div class="node-tile-meta">' +
      escapeHtml(n.country) +
      " · " +
      escapeHtml(n.role) +
      "</div></header>" +
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
