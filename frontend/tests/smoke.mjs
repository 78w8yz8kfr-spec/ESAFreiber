import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const testDirectory = dirname(fileURLToPath(import.meta.url));
const frontendDirectory = resolve(testDirectory, "..");
const readFrontendFile = (path) => readFile(resolve(frontendDirectory, path), "utf8");

const [html, app, worker, versionScript, refreshHtml, refreshScript, manifestSource, esaConfig] = await Promise.all([
  readFrontendFile("index.html"),
  readFrontendFile("app.js"),
  readFrontendFile("sw.js"),
  readFrontendFile("version.js"),
  readFrontendFile("refresh.html"),
  readFrontendFile("refresh.js"),
  readFrontendFile("manifest.webmanifest"),
  readFrontendFile("esa-config.js")
]);

const manifest = JSON.parse(manifestSource);

assert.match(html, /id="login-view"/);
assert.match(html, /id="dashboard-view"/);
assert.match(html, /id="timesheet-section"/);
assert.match(html, /id="assignment-planning-shell"/);
assert.match(html, /id="site-planning-shell"/);
assert.match(html, /id="employee-form"/);
assert.match(html, /version\.js\?v=0\.29\.0/);

assert.match(app, /navigator\.serviceWorker\.register/);
assert.match(app, /\.\/api\/v1\/session/);
assert.match(app, /\.\/api\/v1\/admin\/employees/);
assert.match(app, /\.\/api\/v1\/admin\/assignments/);
assert.match(app, /\.\/api\/v1\/admin\/construction-sites/);
assert.match(app, /\.\/api\/v1\/work-weeks\//);

assert.match(versionScript, /document\.title = "ESA"/);
assert.match(versionScript, /esa-config\.js/);
assert.match(versionScript, /MutationObserver/);

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
assert.ok(Array.isArray(manifest.icons) && manifest.icons.length > 0);

assert.match(worker, /esa-online-v29-1/);
assert.match(worker, /esa-config\.js\?v=0\.29\.0-esa\.1/);
assert.match(worker, /event\.request\.mode === "navigate"/);
assert.match(worker, /cache: "no-store"/);

assert.match(refreshHtml, /ESA wird aktualisiert/);
assert.match(refreshScript, /serviceWorker\.getRegistrations/);
assert.match(refreshScript, /schaefchen-/);
assert.match(refreshScript, /esa-/);
assert.doesNotMatch(refreshScript, /localStorage|indexedDB/);

console.log("ESA-PWA-Smoke-Test erfolgreich.");
