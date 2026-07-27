(() => {
  const VERSION = "0.29.0-esa.1";
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
    }

    const disabledTerms = [];
    if (!config.modules.vde) disabledTerms.push("vde");
    if (!config.modules.inspectionProtocols) disabledTerms.push("prüfprotokoll", "prüfungen");
    if (!config.modules.apprentices) disabledTerms.push("azubi", "berichtsheft", "ausbildung");
    if (!config.modules.fleet) disabledTerms.push("fuhrpark", "fahrzeuge");
    if (!config.modules.materials) disabledTerms.push("material");
    if (!config.modules.customerPortal) disabledTerms.push("kundenportal");
    if (!config.modules.dailySiteReport) disabledTerms.push("bautagesbericht");
    if (!config.modules.installationReport) disabledTerms.push("montagebericht");

    document.querySelectorAll("button, a, [role='button'], nav li, .menu-card, .admin-card").forEach((element) => {
      const label = `${element.textContent || ""} ${element.getAttribute("aria-label") || ""}`.toLowerCase();
      if (disabledTerms.some((term) => label.includes(term))) hideElement(element);
    });
  }

  function applyEsaUi() {
    applyBranding();
    applyModuleVisibility();
  }

  const configScript = document.createElement("script");
  configScript.src = `./esa-config.js?v=${encodeURIComponent(VERSION)}`;
  configScript.onload = () => {
    applyEsaUi();
    const observer = new MutationObserver(applyEsaUi);
    observer.observe(document.body, { childList: true, subtree: true });
  };
  configScript.onerror = applyBranding;
  document.head.append(configScript);
})();