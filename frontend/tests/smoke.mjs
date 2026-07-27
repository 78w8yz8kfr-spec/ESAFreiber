import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const testDirectory = dirname(fileURLToPath(import.meta.url));
const frontendDirectory = resolve(testDirectory, "..");
const readFrontendFile = (path) => readFile(resolve(frontendDirectory, path), "utf8");

const requiredTextFiles = [
  "index.html",
  "styles.css",
  "app.js",
  "sw.js",
  "version.js",
  "refresh.html",
  "refresh.js",
  "manifest.webmanifest",
  "esa-config.js"
];

const contents = await Promise.all(requiredTextFiles.map(readFrontendFile));
for (let index = 0; index < requiredTextFiles.length; index += 1) {
  assert.ok(contents[index].trim().length > 0, `${requiredTextFiles[index]} ist leer`);
}

const manifest = JSON.parse(contents[7]);
assert.equal(manifest.name, "ESA");
assert.equal(manifest.short_name, "ESA");
assert.equal(manifest.display, "standalone");
assert.equal(manifest.start_url, "./");
assert.ok(Array.isArray(manifest.icons) && manifest.icons.length > 0);

assert.match(contents[4], /document\.title = "ESA"/);
assert.match(contents[8], /appName: "ESA"/);
assert.match(contents[8], /repositoryName: "ESAFreiber"/);
assert.match(contents[3], /esa-online-/);

console.log("ESA-PWA-Smoke-Test erfolgreich.");
