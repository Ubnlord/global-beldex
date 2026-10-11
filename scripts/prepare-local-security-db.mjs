import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const sourceMigrations = path.join(root, "migrations");
const testRoot = path.join(root, ".security-test");
const supabaseRoot = path.join(testRoot, "supabase");
const targetMigrations = path.join(supabaseRoot, "migrations");
const targetTests = path.join(supabaseRoot, "tests");
const targetFunctions = path.join(supabaseRoot, "functions");

fs.rmSync(testRoot, { recursive: true, force: true });
fs.mkdirSync(targetMigrations, { recursive: true });
fs.mkdirSync(targetTests, { recursive: true });
fs.mkdirSync(targetFunctions, { recursive: true });

const files = fs.readdirSync(sourceMigrations)
  .filter((name) => /^\d+_.+\.sql$/.test(name))
  .sort((a, b) => {
    const na = Number(a.match(/^\d+/)?.[0] ?? 0);
    const nb = Number(b.match(/^\d+/)?.[0] ?? 0);
    return na - nb || a.localeCompare(b);
  });

if (files.length === 0) {
  throw new Error("No repository migrations found in migrations/");
}

files.forEach((name, index) => {
  const suffix = name.replace(/^\d+_/, "");
  const migrationName = `202610060000${String(index + 1).padStart(2, "0")}_${suffix}`;
  fs.copyFileSync(path.join(sourceMigrations, name), path.join(targetMigrations, migrationName));
});

// The root migrations establish the base production schema. Apply the newer
// currency-aware Supabase migrations afterward in their canonical timestamp
// order so the local database suite actually tests the code intended for PR #41.
const sourceSupabaseMigrations = path.join(root, "supabase", "migrations");
const supabaseMigrations = fs.readdirSync(sourceSupabaseMigrations)
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort((a, b) => a.localeCompare(b));
if (supabaseMigrations.length === 0) {
  throw new Error("No timestamped Supabase migrations found in supabase/migrations/");
}
for (const name of supabaseMigrations) {
  fs.copyFileSync(path.join(sourceSupabaseMigrations, name), path.join(targetMigrations, name));
}

// Copy every database regression suite, not just the original safeguards file.
const sourceTests = path.join(root, "supabase", "tests");
const testFiles = fs.readdirSync(sourceTests).filter((name) => name.endsWith(".test.sql")).sort();
if (!testFiles.includes("financial_safeguards.test.sql")) {
  throw new Error("Missing supabase/tests/financial_safeguards.test.sql");
}
for (const name of testFiles) {
  fs.copyFileSync(path.join(sourceTests, name), path.join(targetTests, name));
}

const functionSource = path.join(root, "supabase/functions/swap-assets");
const functionTarget = path.join(targetFunctions, "swap-assets");
fs.cpSync(functionSource, functionTarget, { recursive: true });

console.log(`Prepared reproducible local Supabase fixture with ${files.length} root migrations, ${supabaseMigrations.length} Supabase migrations, and ${testFiles.length} pgTAP suites.`);
console.log("Source of truth: migrations/ (repository), not production schema.");
