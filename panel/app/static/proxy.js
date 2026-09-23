(function () {
  const sel = document.getElementById("node-select");
  const countryLabel = document.getElementById("country-label");
  const ipLabel = document.getElementById("ip-label");
  if (!sel || !countryLabel || !ipLabel) return;

  function syncNode() {
    const o = sel.selectedOptions[0];
    if (!o || !o.value) {
      countryLabel.textContent = "—";
      ipLabel.textContent = "—";
      return;
    }
    const country = (o.dataset.country || "").trim();
    const ip = (o.dataset.ip || "").trim();
    countryLabel.textContent = country || "—";
    ipLabel.textContent = ip || "—";
  }

  sel.addEventListener("change", syncNode);

  const realOptions = Array.from(sel.options).filter((o) => o.value);
  if (realOptions.length === 1) {
    sel.value = realOptions[0].value;
  }
  syncNode();

  const form = document.getElementById("proxy-form");
  form?.addEventListener("submit", () => {
    const hint = document.getElementById("wait-hint");
    const btn = document.getElementById("submit-btn");
    if (hint) hint.style.display = "block";
    if (btn) {
      btn.disabled = true;
      btn.textContent = "Генерация…";
    }
  });
})();
