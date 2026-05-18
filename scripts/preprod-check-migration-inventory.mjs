#!/usr/bin/env node

import { existsSync, readdirSync, readFileSync } from "node:fs";

const manifestPath = "docs/superpowers/plans/2026-05-03-gracenote-phase2-prod-rollout-manifest.md";
const migrationDir = "supabase/migrations";
const prodCandidateStart = "20260430010000";

const manifest = readFileSync(manifestPath, "utf8");
const migrationRows = [...manifest.matchAll(/^\|\s*(\d+)\s*\|\s*`(supabase\/migrations\/[^`]+\.sql)`/gm)]
  .map((match) => ({
    order: Number(match[1]),
    path: match[2],
    filename: match[2].split("/").pop(),
  }));

const migrationFiles = readdirSync(migrationDir)
  .filter((filename) => filename.endsWith(".sql"))
  .sort();

const prodCandidateFiles = migrationFiles
  .filter((filename) => filename.slice(0, 14) >= prodCandidateStart)
  .map((filename) => `${migrationDir}/${filename}`);

const problems = [];

if (migrationRows.length === 0) {
  problems.push("No migration rows were parsed from manifest.");
}

let previousOrder = 0;
for (let index = 0; index < migrationRows.length; index += 1) {
  const row = migrationRows[index];
  if (row.order <= previousOrder) {
    problems.push(`Manifest order is not increasing: row ${row.path} has order ${row.order} after ${previousOrder}.`);
  }
  previousOrder = row.order;

  if (!existsSync(row.path)) {
    problems.push(`Manifest migration file is missing: ${row.path}`);
  }
}

const manifestMigrationPaths = new Set(migrationRows.map((row) => row.path));
for (const path of prodCandidateFiles) {
  if (!manifestMigrationPaths.has(path)) {
    problems.push(`Migration file not listed in prod candidate order: ${path}`);
  }
}

const manifestFilenames = migrationRows.map((row) => row.filename);
const sortedManifestFilenames = [...manifestFilenames].sort();
if (manifestFilenames.join("\n") !== sortedManifestFilenames.join("\n")) {
  problems.push("Manifest migration order is not chronological by filename.");
}

console.log(`Manifest migrations: ${migrationRows.length}`);
console.log(`Prod candidate files from ${prodCandidateStart}: ${prodCandidateFiles.length}`);

if (problems.length > 0) {
  console.log("\nFAILED");
  for (const problem of problems) {
    console.log(`- ${problem}`);
  }
  process.exit(1);
}

console.log("PASS");
