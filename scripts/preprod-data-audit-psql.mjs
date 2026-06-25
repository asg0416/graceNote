#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const auditFiles = [
  "supabase/preprod_data_audit_summary_2026-05-15.sql",
  "supabase/preprod_identity_link_audit_2026-05-22.sql",
  "supabase/preprod_auto_repair_candidates_2026-05-15.sql",
  "supabase/preprod_manual_review_candidates_2026-05-15.sql",
  "supabase/preprod_identity_link_candidates_2026-05-22.sql",
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

const rawDbUrl = process.env.GRACENOTE_VERIFY_DB_URL
  || (dbUrlFile ? readFileSync(dbUrlFile, "utf8").trim() : "");

if (!rawDbUrl) {
  console.error("Provide GRACENOTE_VERIFY_DB_URL or --db-url-file <path>.");
  process.exit(2);
}

let hasBlockingFailure = false;

for (const file of auditFiles) {
  const absoluteFile = resolve(file);
  if (!existsSync(absoluteFile)) {
    console.error(`Missing audit SQL: ${file}`);
    process.exit(2);
  }

  console.log(`\n## ${file}`);
  const result = spawnSync("docker", [
    "run",
    "--rm",
    "-i",
    "postgres:16",
    "psql",
    rawDbUrl,
    "-v",
    "ON_ERROR_STOP=1",
    "-P",
    "pager=off",
  ], {
    cwd: process.cwd(),
    encoding: "utf8",
    input: readFileSync(absoluteFile, "utf8"),
    stdio: ["pipe", "pipe", "pipe"],
  });

  if (result.status !== 0) {
    console.error(result.stderr.trim());
    console.log(result.stdout.trim());
    process.exit(result.status ?? 1);
  }

  const stdout = result.stdout.trim();
  console.log(stdout || "(0 rows)");

  if (
    file.endsWith("preprod_data_audit_summary_2026-05-15.sql")
    || file.endsWith("preprod_identity_link_audit_2026-05-22.sql")
  ) {
    const blockingIssuePattern = /^\s*blocking_gate\s+\|\s+[^|]+\|\s+([1-9][0-9]*)\s*$/gm;
    if (blockingIssuePattern.test(stdout)) {
      hasBlockingFailure = true;
    }
  }
}

if (hasBlockingFailure) {
  console.error("\nFAILED: blocking_gate issue_count is nonzero.");
  process.exit(1);
}

console.log("\nPASS: no blocking_gate issues.");
