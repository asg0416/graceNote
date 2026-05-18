#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const gates = [
  "supabase/verify_phase2_people_memberships_schema_summary_dev_2026-05-15.sql",
  "supabase/verify_phase2_consistency_summary_dev_2026-05-10.sql",
  "supabase/verify_phase3_attendance_prayer_person_snapshot_summary_dev_2026-05-15.sql",
  "supabase/verify_attendance_roster_snapshot_integrity_dev_2026-05-15.sql",
  "supabase/verify_app_config_rls_dev_2026-05-15.sql",
  "supabase/verify_phase2d_edge_notification_targets_dev_2026-05-09.sql",
];

const args = process.argv.slice(2);
const hasFlag = (flag) => args.includes(flag);
const getFlagValue = (flag) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
};

const dbUrlFile = getFlagValue("--db-url-file");
const rawDbUrl = process.env.GRACENOTE_VERIFY_DB_URL
  || (dbUrlFile ? readFileSync(dbUrlFile, "utf8").trim() : "");
const useLocal = hasFlag("--local") || !rawDbUrl;

if (!useLocal && !rawDbUrl) {
  console.error("Provide GRACENOTE_VERIFY_DB_URL, --db-url-file <path>, or use --local.");
  process.exit(2);
}

const runGate = (file) => {
  const absoluteFile = resolve(file);
  if (!existsSync(absoluteFile)) {
    throw new Error(`Missing gate SQL: ${file}`);
  }

  const queryArgs = ["db", "query", "--output", "json", "--file", file];
  if (useLocal) {
    queryArgs.push("--local");
  } else {
    queryArgs.push("--db-url", rawDbUrl);
  }

  const result = spawnSync("supabase", queryArgs, {
    cwd: process.cwd(),
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });

  if (result.status !== 0) {
    throw new Error([
      `Gate command failed: ${file}`,
      result.stderr.trim(),
      result.stdout.trim(),
    ].filter(Boolean).join("\n"));
  }

  const stdout = result.stdout.trim();
  const jsonStart = stdout.indexOf("{");
  if (jsonStart === -1) {
    throw new Error(`Gate did not return JSON: ${file}\n${stdout}`);
  }

  const parsed = JSON.parse(stdout.slice(jsonStart));
  const rows = Array.isArray(parsed.rows) ? parsed.rows : [];
  const failures = rows.filter((row) => {
    const issueCount = Number(row.issue_count ?? 0);
    const mismatchCount = Number(row.mismatch_count ?? 0);
    return issueCount !== 0 || mismatchCount !== 0;
  });

  return { file, rows, failures };
};

const summary = [];
let hasFailure = false;

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
    const count = row.issue_count ?? row.mismatch_count ?? "";
    console.log(`- ${row.check_name}: ${count}`);
  }

  if (result.failures.length === 0) {
    console.log("PASS");
  } else {
    console.log("FAILED");
  }
}

process.exit(hasFailure ? 1 : 0);
