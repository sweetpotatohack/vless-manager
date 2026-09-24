(function () {
  const grid = document.getElementById("node-metrics-grid");
  const updatedEl = document.getElementById("metrics-updated");
  const liveDot = document.getElementById("metrics-live-dot");
  if (!grid) return;

  const history = {};
  const HISTORY_LEN = 36;

  function level(pct) {
    if (pct == null || Number.isNaN(pct)) return "none";
    if (pct >= 90) return "bad";
    if (pct >= 75) return "warn";
    return "ok";
  }

  function pushHistory(id, key, val) {
    if (!history[id]) history[id] = { cpu: [], mem: [], disk: [] };
    const arr = history[id][key];
    if (val == null || Number.isNaN(val)) return;
    arr.push(val);
    while (arr.length > HISTORY_LEN) arr.shift();
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function fmtPct(pct) {
    if (pct == null || Number.isNaN(pct)) return "—";
    return pct.toFixed(1);
  }

  function sparkSvg(id, key) {
    const arr = (history[id] && history[id][key]) || [];
    const w = 120;
    const h = 28;
    if (arr.length < 2) {
      return (
        '<svg class="spark" viewBox="0 0 ' +
        w +
        " " +
        h +
        '" preserveAspectRatio="none"><path class="spark-idle" d="M0,' +
        (h / 2) +
        " L" +
        w +
        "," +
        (h / 2) +
        '"/></svg>'
      );
    }
    const step = w / (HISTORY_LEN - 1);
    const start = HISTORY_LEN - arr.length;
    let d = "";
    arr.forEach(function (v, i) {
      const x = (start + i) * step;
      const y = h - (Math.min(100, Math.max(0, v)) / 100) * (h - 4) - 2;
      d += (i === 0 ? "M" : " L") + x.toFixed(1) + "," + y.toFixed(1);
    });
    return (
      '<svg class="spark lv-' +
      level(arr[arr.length - 1]) +
      '" viewBox="0 0 ' +
      w +
      " " +
      h +
      '" preserveAspectRatio="none"><path d="' +
      d +
      '"/></svg>'
    );
  }

  function blocks(pct) {
    const n = 12;
    const filled = pct == null ? 0 : Math.round((Math.min(100, Math.max(0, pct)) / 100) * n);
    let html = '<div class="seg-bar">';
    for (let i = 0; i < n; i++) {
      const on = i < filled;
      const lv = level(pct);
      html += '<span class="seg' + (on ? " on lv-" + lv : "") + '"></span>';
    }
    html += "</div>";
    return html;
  }

  function ring(label, pct, sub) {
    const lv = level(pct);
    const off = pct == null ? 100 : 100 - Math.min(100, Math.max(0, pct));
    const subHtml = sub ? '<span class="ring-sub">' + escapeHtml(sub) + "</span>" : "";
    return (
      '<div class="ring-wrap lv-' +
      lv +
      '">' +
      '<svg class="ring" viewBox="0 0 42 42">' +
      '<circle class="ring-track" cx="21" cy="21" r="15.9" />' +
      '<circle class="ring-fill" cx="21" cy="21" r="15.9" stroke-dasharray="100 100" stroke-dashoffset="' +
      off +
      '" />' +
      "</svg>" +
      '<div class="ring-center">' +
      '<span class="ring-val">' +
      fmtPct(pct) +
      "</span>" +
      '<span class="ring-unit">%</span></div>' +
      '<div class="ring-label">' +
      escapeHtml(label) +
      "</div>" +
      subHtml +
      "</div>"
    );
  }

  function statusBadges(n) {
    let b = "";
    if (n.role === "agent" && n.agent_status && n.agent_status !== "online") {
      b += '<span class="badge badge-bad">' + escapeHtml(n.agent_status) + "</span> ";
    }
    if (n.missing) {
      b += '<span class="badge badge-muted">нет данных</span> ';
    } else if (n.stale) {
      b += '<span class="badge badge-warn">устарело</span> ';
    } else {
      b += '<span class="badge badge-ok">live</span> ';
    }
    return b;
  }

  function renderNode(n) {
    pushHistory(n.id, "cpu", n.cpu);
    pushHistory(n.id, "mem", n.mem);
    pushHistory(n.id, "disk", n.disk);

    const load =
      n.load_1 != null ? '<span class="load-tag">load ' + n.load_1.toFixed(2) + "</span>" : "";

    return (
      '<article class="node-monitor" data-node-id="' +
      n.id +
      '">' +
      '<header class="node-monitor-head">' +
      '<div class="node-title-row">' +
      "<strong>" +
      escapeHtml(n.name) +
      "</strong> " +
      statusBadges(n) +
      load +
      "</div>" +
      '<div class="node-monitor-meta">' +
      escapeHtml(n.country) +
      " · " +
      escapeHtml(n.role) +
      "</div></header>" +
      '<div class="rings-row">' +
      ring("CPU", n.cpu, null) +
      ring("RAM", n.mem, n.mem_label) +
      ring("DISK", n.disk, n.disk_label) +
      "</div>" +
      '<div class="spark-panel">' +
      '<div class="spark-row"><span>CPU</span>' +
      sparkSvg(n.id, "cpu") +
      blocks(n.cpu) +
      "</div>" +
      '<div class="spark-row"><span>RAM</span>' +
      sparkSvg(n.id, "mem") +
      blocks(n.mem) +
      "</div>" +
      '<div class="spark-row"><span>DISK</span>' +
      sparkSvg(n.id, "disk") +
      blocks(n.disk) +
      "</div>" +
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
          "обновлено " + t.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
      }
    } catch (_e) {
      setLive(false);
    }
  }

  refresh();
  setInterval(refresh, 5000);
})();
