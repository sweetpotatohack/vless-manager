(function () {
  var layout = document.getElementById("app-layout");
  var toggle = document.getElementById("nav-toggle");
  var backdrop = document.getElementById("sidebar-backdrop");
  if (!layout || !toggle) return;

  function setOpen(open) {
    layout.classList.toggle("nav-open", open);
    toggle.setAttribute("aria-expanded", open ? "true" : "false");
    document.body.classList.toggle("nav-locked", open);
  }

  function closeNav() {
    setOpen(false);
  }

  toggle.addEventListener("click", function () {
    setOpen(!layout.classList.contains("nav-open"));
  });

  if (backdrop) {
    backdrop.addEventListener("click", closeNav);
  }

  layout.querySelectorAll(".nav a").forEach(function (link) {
    link.addEventListener("click", closeNav);
  });

  window.addEventListener("resize", function () {
    if (window.matchMedia("(min-width: 901px)").matches) closeNav();
  });

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") closeNav();
  });
})();
