#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { printLocalGateSummary, runLocalGates } from "./preprod-local-gates.mjs";

const gates = [
  "supabase/verify_phase2_people_memberships_schema_summary_dev_2026-05-15.sql",
  "supabase/verify_phase2_consistency_summary_dev_2026-05-10.sql",
  "supabase/verify_phase3_attendance_prayer_person_snapshot_summary_dev_2026-05-15.sql",
  "supabase/verify_attendance_roster_snapshot_integrity_dev_2026-05-15.sql",
  "supabase/verify_app_config_rls_dev_2026-05-15.sql",
  "supabase/verify_phase2d_edge_notification_targets_dev_2026-05-09.sql",
];

const args = process.argv.slice(2);
const getFlagValue = (flag) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
};

const dbUrlFile = getFlagValue("--db-url-file");

if (dbUrlFile && !existsSync(dbUrlFile)) {
  console.error(`DB URL file not found: ${dbUrlFile}`);
  console.error("Create it with: read -s GRACENOTE_VERIFY_DB_URL && printf '%s' \"$GRACENOTE_VERIFY_DB_URL\" > <path> && unset GRACENOTE_VERIFY_DB_URL");
  process.exit(2);
}

const summary = [];
let hasFailure = false;

const localGateSummary = runLocalGates();
printLocalGateSummary(localGateSummary);
if (localGateSummary.hasFailure) {
  hasFailure = true;
}

const rawDbUrl = process.env.GRACENOTE_VERIFY_DB_URL
  || (dbUrlFile ? readFileSync(dbUrlFile, "utf8").trim() : "");

if (!rawDbUrl) {
  console.error("Provide GRACENOTE_VERIFY_DB_URL or --db-url-file <path>.");
  process.exit(2);
}

const runGate = (file) => {
  const absoluteFile = resolve(file);
  if (!existsSync(absoluteFile)) {
    throw new Error(`Missing gate SQL: ${file}`);
  }

  const sql = readFileSync(absoluteFile, "utf8");

  const result = spawnSync("docker", [
    "run",
    "--rm",
    "-i",
    "postgres:16",
    "psql",
    rawDbUrl,
    "-q",
    "-t",
    "-A",
    "-F",
    "\t",
    "-v",
    "ON_ERROR_STOP=1",
  ], {
    cwd: process.cwd(),
    encoding: "utf8",
    input: sql,
    stdio: ["pipe", "pipe", "pipe"],
  });

  if (result.status !== 0) {
    throw new Error([
      `Gate command failed: ${file}`,
      result.stderr.trim(),
      result.stdout.trim(),
    ].filter(Boolean).join("\n"));
  }

  const rows = result.stdout
    .trim()
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [checkName, count] = line.split("\t");
      return {
        check_name: checkName,
        count: Number(count ?? 0),
      };
    });

  const failures = rows.filter((row) => row.count !== 0);
  return { file, rows, failures };
};

for (const gate of gates) {
  try {
    const result = runGate(gate);
    summary.push(result);
    if (result.failures.length > 0) {
      hasFailure = true;
    }
  } catch (error) {
    hasFailure = true;
    summary.push({ file: gate, error: error instanceof Error ? error.message : String(error) });
  }
}

for (const result of summary) {
  console.log(`\n## ${result.file}`);
  if (result.error) {
    console.log(`FAILED: ${result.error}`);
    continue;
  }

  for (const row of result.rows) {
    console.log(`- ${row.check_name}: ${row.count}`);
  }

  console.log(result.failures.length === 0 ? "PASS" : "FAILED");
}

process.exit(hasFailure ? 1 : 0);
