import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const testDirectory = dirname(fileURLToPath(import.meta.url));
const frontendDirectory = resolve(testDirectory, "..");
const repositoryDirectory = resolve(frontendDirectory, "..");
const readFrontendFile = (path) => readFile(resolve(frontendDirectory, path), "utf8");

const [
  html,
  styles,
  app,
  worker,
  refreshHtml,
  refreshScript,
  manifestSource,
  esaConfig,
  mark,
  companyLogo,
  uiSpecification,
  siteTemplate
] = await Promise.all([
  readFrontendFile("index.html"),
  readFrontendFile("styles.css"),
  readFrontendFile("app.js"),
  readFrontendFile("sw.js"),
  readFrontendFile("refresh.html"),
  readFrontendFile("refresh.js"),
  readFrontendFile("manifest.webmanifest"),
  readFrontendFile("esa-config.js"),
  readFrontendFile("assets/mark.svg"),
  readFile(resolve(frontendDirectory, "assets/company-logos/schaaf-elektro.webp")),
  readFile(resolve(repositoryDirectory, "docs/PHASE1_UI_SPEC.md"), "utf8"),
  readFile(resolve(frontendDirectory, "assets/baustellen-import-vorlage.xlsx"))
]);

const manifest = JSON.parse(manifestSource);

assert.match(html, /lang="de"/);
assert.match(html, /<title>ESA<\/title>/);
assert.match(html, /ESA – Zeiterfassung, Baustellen- und Mitarbeiterplanung/);
assert.match(html, /id="login-view"/);
assert.match(html, /id="dashboard-view"/);
assert.match(html, /id="timesheet-section"/);
assert.match(html, /id="week-timesheet-list"/);
assert.match(html, /id="admin-section"/);
assert.match(html, /id="assignment-planning-shell"/);
assert.match(html, /id="site-planning-shell"/);
assert.match(html, /id="employee-form"/);
assert.match(html, /id="employee-edit-form"/);
assert.match(html, /id="assignment-import-panel"/);
assert.match(html, /id="site-import-panel"/);
assert.match(html, /baustellen-import-vorlage\.xlsx/);
assert.match(html, /esa-config\.js\?v=0\.29\.0/);
assert.match(html, /styles\.css\?v=0\.29\.0/);
assert.match(html, /app\.js\?v=0\.29\.0/);
assert.match(html, /version\.js\?v=0\.29\.0/);
assert.doesNotMatch(html, /https?:\/\//, "Die PWA darf keine externen Laufzeitressourcen laden");

assert.match(styles, /env\(safe-area-inset-bottom\)/);
assert.match(styles, /:focus-visible/);
assert.match(styles, /--brand: #e30613/);
assert.match(styles, /--ink: #111111/);
assert.doesNotMatch(styles, /#173c34|#b9e65a|#7da82a/i);

assert.match(app, /navigator\.serviceWorker\.register/);
assert.match(app, /\.\/api\/v1\/session/);
assert.match(app, /\.\/api\/v1\/admin\/employees/);
assert.match(app, /\.\/api\/v1\/admin\/assignments/);
assert.match(app, /\.\/api\/v1\/admin\/construction-sites/);
assert.match(app, /\.\/api\/v1\/work-weeks\//);
assert.match(app, /work-days\/\$\{encodeURIComponent\(workDate\)\}\/submit/);
assert.match(app, /renderWorkDayReviews/);
assert.match(app, /Stundenzettel einreichen/);
assert.doesNotMatch(app, /geolocation/i);

assert.match(esaConfig, /appName: "ESA"/);
assert.match(esaConfig, /repositoryName: "ESAFreiber"/);
assert.match(esaConfig, /timeTracking: true/);
assert.match(esaConfig, /constructionSites: true/);
assert.match(esaConfig, /constructionSitePlanning: true/);
assert.match(esaConfig, /employees: true/);
assert.match(esaConfig, /excelExport: true/);
assert.match(esaConfig, /vde: false/);
assert.match(esaConfig, /inspectionProtocols: false/);
assert.match(esaConfig, /apprentices: false/);
assert.match(esaConfig, /fleet: false/);
assert.match(esaConfig, /materials: false/);
assert.match(esaConfig, /dailySiteReport: false/);
assert.match(esaConfig, /installationReport: false/);

assert.equal(manifest.name, "ESA");
assert.equal(manifest.short_name, "ESA");
assert.equal(manifest.display, "standalone");
assert.equal(manifest.start_url, "./");
assert.equal(manifest.theme_color, "#e30613");
assert.ok(manifest.icons.length > 0);

assert.match(mark, /fill="#111111"/);
assert.match(mark, /fill="#e30613"/);
assert.equal(companyLogo.subarray(0, 4).toString("ascii"), "RIFF");
assert.equal(companyLogo.subarray(8, 12).toString("ascii"), "WEBP");
assert.equal(siteTemplate[0], 0x50);
assert.equal(siteTemplate[1], 0x4b);

for (const asset of [
  "./index.html",
  "./manifest.webmanifest",
  "./esa-config.js?v=0.29.0",
  "./assets/mark.svg",
  "./assets/company-logos/schaaf-elektro.webp",
  "./assets/baustellen-import-vorlage.xlsx"
]) {
  assert.ok(worker.includes(`"${asset}"`), `${asset} fehlt im App-Shell-Cache`);
}
assert.match(worker, /const CACHE_NAME = "esa-online-v29"/);
assert.ok(worker.includes('"./styles.css?v=0.29.0"'));
assert.ok(worker.includes('"./app.js?v=0.29.0"'));
assert.ok(worker.includes('"./version.js?v=0.29.0"'));
assert.match(worker, /requestUrl\.pathname\.startsWith\("\/api\/"\)/);
assert.match(worker, /event\.request\.mode === "navigate"/);
assert.match(worker, /cache: "no-store"/);

assert.match(refreshHtml, /ESA wird aktualisiert/);
assert.match(refreshScript, /serviceWorker\.getRegistrations/);
assert.match(refreshScript, /key\.startsWith\("schaefchen-"\)/);
assert.match(refreshScript, /key\.startsWith\("esa-"\)/);
assert.doesNotMatch(refreshScript, /localStorage|indexedDB/);

assert.match(uiSpecification, /keine echte\s+Serveranmeldung/i);
assert.match(uiSpecification, /keine GPS-Abfrage/i);

console.log("ESA-PWA-Smoke-Test erfolgreich.");
