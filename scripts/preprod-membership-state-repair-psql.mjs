#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const auditSql = "supabase/preprod_data_audit_summary_2026-05-15.sql";
const repairSql = "supabase/preprod_membership_state_auto_repair_2026-05-22.sql";
const knownProdProjectRefs = [
  "eejqiddsdovrabcsxznu",
];

const args = process.argv.slice(2);
const getFlagValue = (flag) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
};

const dbUrlFile = getFlagValue("--db-url-file");
const shouldApply = args.includes("--apply-auto-repair");
const allowKnownProd = args.includes("--allow-known-prod");

if (!shouldApply) {
  console.error("Refusing to mutate data without --apply-auto-repair.");
  console.error("Expected usage: node scripts/preprod-membership-state-repair-psql.mjs --db-url-file <path> --apply-auto-repair");
  process.exit(2);
}

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

if (!allowKnownProd && knownProdProjectRefs.some((projectRef) => rawDbUrl.includes(projectRef))) {
  console.error("Refusing to run membership state repair against the known production project ref.");
  console.error("Run against a dev/staging/prod-clone DB first. Do not pass --allow-known-prod unless this is an approved production maintenance window.");
  process.exit(2);
}

const runSql = (label, file) => {
  const absoluteFile = resolve(file);
  if (!existsSync(absoluteFile)) {
    console.error(`Missing SQL: ${file}`);
    process.exit(2);
  }

  console.log(`\n## ${label}: ${file}`);
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

  console.log(result.stdout.trim() || "(0 rows)");
};

runSql("before membership audit", auditSql);
runSql("apply deterministic membership state repair", repairSql);
runSql("after membership audit", auditSql);
