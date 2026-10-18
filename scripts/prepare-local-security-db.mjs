import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const testRoot = path.join(root, ".security-test");
const supabaseRoot = path.join(testRoot, "supabase");
const targetMigrations = path.join(supabaseRoot, "migrations");
const targetTests = path.join(supabaseRoot, "tests");
const sourceMigrations = path.join(root, "supabase", "migrations");
const baselinePath = path.join(root, "supabase", "baselines", "20261012170510_production_schema_baseline.sql");
const baselineName = "20261012170510_production_schema_baseline.sql";
const sourceTests = path.join(root, "supabase", "tests");

// A fresh local fixture must start from a schema-only baseline extracted from
// the actual production schema. Never synthesize migration versions or replay
// the incompatible numbered migrations/ history alongside production history.
const migrationFiles = fs.readdirSync(sourceMigrations)
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort((a, b) => a.localeCompare(b));

if (!fs.existsSync(baselinePath)) {
  throw new Error(
    `Missing actual schema extraction: supabase/baselines/${baselineName}. Generate it from the production schema using the dedicated extraction workflow. Do not hand-build it or synthesize a new migration version.`
  );
}

const baselineSql = fs.readFileSync(baselinePath, "utf8");
const requiredSchemaMarkers = [
  "user_profile",
  "user_investment",
  "investment_plan_catalog",
  "admin_action_audit",
  "transaction_audit",
  "admin_fund_user",
  "admin_adjust_balance",
  "create_financial_transaction",
];
for (const marker of requiredSchemaMarkers) {
  if (!baselineSql.includes(marker)) {
    throw new Error(`Extracted production schema baseline is missing required schema marker: ${marker}`);
  }
}
if (/^COPY public\\./m.test(baselineSql)) {
  throw new Error("Production baseline unexpectedly contains table data; only a schema-only dump is allowed.");
}

const baseline = baselineName;
const baselineVersion = baseline.slice(0, 14);
// The baseline replaces the production migration history through the last
// verified production version. Only migrations strictly newer than that
// production version are replayed on top of it.
const laterMigrations = migrationFiles.filter((name) => name.slice(0, 14) > baselineVersion);
const selectedMigrations = [baseline, ...laterMigrations];

const versions = new Set();
for (const name of selectedMigrations) {
  const version = name.slice(0, 14);
  if (versions.has(version)) {
    throw new Error(`Duplicate migration version in baseline fixture: ${version}`);
  }
  versions.add(version);
}

if (laterMigrations.length === 0) {
  throw new Error("No proposed migrations newer than the extracted production baseline were found.");
}

fs.rmSync(testRoot, { recursive: true, force: true });
fs.mkdirSync(targetMigrations, { recursive: true });
fs.mkdirSync(targetTests, { recursive: true });

for (const name of selectedMigrations) {
  const sourcePath = name === baseline
    ? baselinePath
    : path.join(sourceMigrations, name);
  fs.copyFileSync(sourcePath, path.join(targetMigrations, name));
}

const testFiles = fs.readdirSync(sourceTests)
  .filter((name) => name.endsWith(".test.sql"))
  .sort();

if (!testFiles.includes("financial_safeguards.test.sql")) {
  throw new Error("Missing supabase/tests/financial_safeguards.test.sql");
}

for (const name of testFiles) {
  fs.copyFileSync(path.join(sourceTests, name), path.join(targetTests, name));
}

console.log(
  `Prepared isolated Supabase fixture from 1 extracted production schema baseline, ${laterMigrations.length} later migrations, and ${testFiles.length} pgTAP suites.`
);
console.log(`Baseline: ${baseline}`);
console.log("Baseline replaces production history through 20261012170510; older migration files and numbered migrations/ were intentionally excluded.");
