import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const testRoot = path.join(root, ".security-test");
const supabaseRoot = path.join(testRoot, "supabase");
const targetMigrations = path.join(supabaseRoot, "migrations");
const targetTests = path.join(supabaseRoot, "tests");
const sourceMigrations = path.join(root, "supabase", "migrations");
const sourceTests = path.join(root, "supabase", "tests");

// A fresh local fixture must start from a schema-only baseline extracted from
// the actual production schema. Never synthesize migration versions or replay
// the incompatible numbered migrations/ history alongside production history.
const migrationFiles = fs.readdirSync(sourceMigrations)
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort((a, b) => a.localeCompare(b));

const baselines = migrationFiles.filter((name) =>
  /^\d{14}_production_schema_baseline\.sql$/.test(name)
);

if (baselines.length !== 1) {
  throw new Error(
    `Expected exactly one extracted production schema baseline in supabase/migrations/; found ${baselines.length}. Do not synthesize a baseline or renumber historical migrations. Generate it from an actual schema extraction first.`
  );
}

const baseline = baselines[0];
const baselineVersion = baseline.slice(0, 14);
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
  fs.copyFileSync(path.join(sourceMigrations, name), path.join(targetMigrations, name));
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
console.log("Historical production migrations and numbered migrations/ files were intentionally excluded.");
