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

const testFile = path.join(root, "supabase/tests/financial_safeguards.test.sql");
if (!fs.existsSync(testFile)) {
  throw new Error("Missing supabase/tests/financial_safeguards.test.sql");
}
fs.copyFileSync(testFile, path.join(targetTests, "financial_safeguards.test.sql"));

const functionSource = path.join(root, "supabase/functions/swap-assets");
const functionTarget = path.join(targetFunctions, "swap-assets");
fs.cpSync(functionSource, functionTarget, { recursive: true });

console.log(`Prepared reproducible local Supabase fixture with ${files.length} repository migrations.`);
console.log("Source of truth: migrations/ (repository), not production schema.");
