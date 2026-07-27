(() => {
  const VERSION = "0.29.0-esa.4";
  const queryMode = new URLSearchParams(window.location.search).get("mode");
  const demoMode = queryMode === "demo" || (
    queryMode !== "live"
    && (window.location.hostname.endsWith("github.io") || window.location.port === "4173")
  );

  function hideElement(element) {
    if (!element) return;
    element.hidden = true;
    element.setAttribute("aria-hidden", "true");
  }

  function applyBranding() {
    document.title = "ESA";
    const description = document.querySelector('meta[name="description"]');
    if (description) description.content = "ESA – Zeiterfassung und Einsatzplanung.";

    document.querySelectorAll(".brand strong, .brand h1").forEach((element) => {
      if (element.textContent.trim() === "Schäfchen") element.textContent = "ESA";
    });

    const footer = document.querySelector("#login-footer");
    if (footer) footer.textContent = `ESA · Version ${VERSION} ${demoMode ? "Demo" : "Online"}`;
  }

  function applyModuleVisibility() {
    const config = window.ESA_CONFIG;
    if (!config) return;

    if (!config.modules.dailySiteReport || !config.modules.installationReport) {
      hideElement(document.querySelector("#mobile-report-card"));
      hideElement(document.querySelector("#site-report-panel"));
      hideElement(document.querySelector("#site-report-list"));
      hideElement(document.querySelector("#site-dashboard-reports-panel"));
      hideElement(document.querySelector("#employee-site-reports"));
    }

    if (!config.modules.materials) {
      hideElement(document.querySelector("#site-material-form"));
      hideElement(document.querySelector("#employee-site-materials"));
    }
  }

  function openPreviewFallback() {
    const login = document.querySelector("#login-view");
    const dashboard = document.querySelector("#dashboard-view");
    if (!login || !dashboard) return;
    login.hidden = true;
    dashboard.hidden = false;
    dashboard.removeAttribute("aria-hidden");
    window.scrollTo({ top: 0, behavior: "instant" });
  }

  function closePreviewFallback() {
    const login = document.querySelector("#login-view");
    const dashboard = document.querySelector("#dashboard-view");
    if (!login || !dashboard) return;
    dashboard.hidden = true;
    login.hidden = false;
    login.removeAttribute("aria-hidden");
    window.scrollTo({ top: 0, behavior: "instant" });
  }

  function toggleWorkdayFallback() {
    const button = document.querySelector("#primary-action");
    const label = document.querySelector("#primary-action-label");
    const title = document.querySelector("#workday-title");
    const since = document.querySelector("#status-since");
    if (!button || !label || !title) return;

    const active = button.dataset.esaActive === "true";
    button.dataset.esaActive = active ? "false" : "true";
    label.textContent = active ? "Arbeitstag starten" : "Arbeitstag beenden";
    title.textContent = active ? "Noch nicht gestartet" : "Arbeitstag läuft";
    if (since) since.textContent = active ? "Bereit zum Start" : `Gestartet um ${new Date().toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" })}`;
  }

  function installFallbackControls() {
    document.addEventListener("click", (event) => {
      const target = event.target instanceof Element ? event.target.closest("button, a") : null;
      if (!target) return;
      if (target.id === "open-preview") {
        event.preventDefault();
        openPreviewFallback();
      } else if (target.id === "close-preview") {
        event.preventDefault();
        closePreviewFallback();
      } else if (target.id === "primary-action" && !target.dataset.esaHandled) {
        event.preventDefault();
        toggleWorkdayFallback();
      }
    }, true);
  }

  function applyEsaUi() {
    applyBranding();
    applyModuleVisibility();
  }

  installFallbackControls();

  const configScript = document.createElement("script");
  configScript.src = `./esa-config.js?v=${encodeURIComponent(VERSION)}`;
  configScript.onload = applyEsaUi;
  configScript.onerror = applyBranding;
  document.head.append(configScript);
})();
