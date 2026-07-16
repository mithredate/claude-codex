#!/usr/bin/env node
// Build a self-contained complexity dashboard by injecting a scorecard JSON
// into the bundled HTML template. Deterministic — no chart code is generated.
//
//   node build-dashboard.mjs --data scorecard.json --out dashboard.html [--template path]
//
// The scorecard contract lives in ../references/dashboard.md. The output is
// Artifact-CSP-safe (inline CSS/JS/SVG) and meant to be published with the
// Artifact tool, favicon 📊.

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));

function arg(flag, fallback) {
  const i = process.argv.indexOf(flag);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const dataPath = arg("--data");
const outPath = arg("--out");
const templatePath = arg("--template", resolve(here, "dashboard-template.html"));

if (!dataPath || !outPath) {
  console.error("usage: build-dashboard.mjs --data <scorecard.json> --out <dashboard.html> [--template <file>]");
  process.exit(2);
}

let data;
try {
  data = JSON.parse(readFileSync(resolve(dataPath), "utf8"));
} catch (err) {
  console.error(`✘ Could not read/parse --data ${dataPath}: ${err.message}`);
  process.exit(1);
}

// --- validate the contract enough to fail loud, not silent ---
const problems = [];
if (!Array.isArray(data.dimensions) || data.dimensions.length < 3) problems.push("`dimensions` must be an array of 3+ names");
if (!Array.isArray(data.features) || data.features.length < 1) problems.push("`features` must be a non-empty array");
if (data.features?.length > 6) problems.push("`features` supports at most 6 entries (colour palette)");
for (const [i, f] of (data.features ?? []).entries()) {
  if (!f.name) problems.push(`features[${i}] missing \`name\``);
  if (!Array.isArray(f.scores) || f.scores.length !== data.dimensions?.length)
    problems.push(`features[${i}].scores must have ${data.dimensions?.length} numbers (one per dimension)`);
  else for (const s of f.scores) if (typeof s !== "number" || s < 0 || s > 10) problems.push(`features[${i}].scores has an out-of-range value (${s}); expected 0–10`);
}
if (problems.length) {
  console.error("✘ Invalid scorecard:\n  - " + problems.join("\n  - "));
  process.exit(1);
}

if (!Array.isArray(data.methodology) || data.methodology.length === 0) {
  console.warn("⚠ No `methodology` entries — the dashboard's methodology table will show em-dashes. Every score should be sourced.");
}

const template = readFileSync(templatePath, "utf8");
const title = String(data.title ?? "Feature complexity").replace(/[<>]/g, "");
const html = template
  .replaceAll("__TITLE__", title)
  .replace("__SCORECARD_DATA__", JSON.stringify(data));

writeFileSync(resolve(outPath), html, "utf8");
console.log(`✓ Wrote ${outPath} (${data.features.length} features × ${data.dimensions.length} dimensions). Publish it with the Artifact tool, favicon 📊.`);
