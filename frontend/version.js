(() => {
  const VERSION = "0.29.0-esa.3";
  const queryMode = new URLSearchParams(window.location.search).get("mode");
  const demoMode = queryMode === "demo" || (
    queryMode !== "live"
    && (window.location.hostname.endsWith("github.io") || window.location.port === "4173")
  );

  async function clearBrokenOfflineCacheOnce() {
    const cleanupKey = `esa-cache-cleanup-${VERSION}`;
    if (window.sessionStorage.getItem(cleanupKey) === "done") return;

    try {
      if ("serviceWorker" in navigator) {
        const registrations = await navigator.serviceWorker.getRegistrations();
        await Promise.all(registrations.map((registration) => registration.unregister()));
      }
      if ("caches" in window) {
        const keys = await caches.keys();
        await Promise.all(
          keys
            .filter((key) => key.startsWith("esa-") || key.startsWith("schaefchen-"))
            .map((key) => caches.delete(key))
        );
      }
    } catch (error) {
      console.warn("ESA-Cache konnte nicht vollständig bereinigt werden.", error);
    } finally {
      window.sessionStorage.setItem(cleanupKey, "done");
    }
  }

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

  function applyEsaUi() {
    applyBranding();
    applyModuleVisibility();
  }

  clearBrokenOfflineCacheOnce().finally(() => {
    const configScript = document.createElement("script");
    configScript.src = `./esa-config.js?v=${encodeURIComponent(VERSION)}`;
    configScript.onload = applyEsaUi;
    configScript.onerror = applyBranding;
    document.head.append(configScript);
  });
})();
