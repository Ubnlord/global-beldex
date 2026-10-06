import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const safeguards = fs.readFileSync(path.join(root, "migrations/0015_admin_audit_financial_safeguards.sql"), "utf8");
const auditLock = fs.readFileSync(path.join(root, "migrations/0016_lock_transaction_audit_to_admins.sql"), "utf8");
const suite = fs.readFileSync(path.join(root, "supabase/tests/financial_safeguards.test.sql"), "utf8");

test("permanent financial safeguard suite is present and non-destructive", () => {
  for (const needle of [
    "p_amount <= 0",
    "p_delta = 0",
    "reason is required",
    "blocked user cannot receive funding",
    "insufficient available balance",
    "alter table public.transaction_audit enable row level security",
  ]) {
    assert.ok(safeguards.includes(needle), "missing safeguard contract: " + needle);
  }

  assert.match(
    auditLock,
    /drop policy if exists transaction_audit_select_own_or_admin on public\.transaction_audit;/i,
  );
  assert.match(suite, /select plan\(60\);/);
  assert.doesNotMatch(suite, /create_financial_transaction\s*\(/i);
  assert.doesNotMatch(suite, /createUser|deleteUser|SUPABASE_SERVICE_ROLE_KEY/i);
});
