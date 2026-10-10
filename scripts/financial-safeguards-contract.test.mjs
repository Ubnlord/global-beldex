import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const safeguards = fs.readFileSync(path.join(root, "migrations/0015_admin_audit_financial_safeguards.sql"), "utf8");
const auditLock = fs.readFileSync(path.join(root, "migrations/0016_lock_transaction_audit_to_admins.sql"), "utf8");
const suite = fs.readFileSync(path.join(root, "supabase/tests/financial_safeguards.test.sql"), "utf8");
const withdrawalMigration = fs.readFileSync(path.join(root, "migrations/0019_withdrawal_address_validation.sql"), "utf8");
const withdrawalValidator = fs.readFileSync(path.join(root, "src/lib/financial/withdrawal-address.ts"), "utf8");
const operationsHardening = fs.readFileSync(path.join(root, "migrations/0020_post_release_operations_hardening.sql"), "utf8");
const adminAuditIdentity = fs.readFileSync(path.join(root, "migrations/0022_admin_audit_identity_hardening.sql"), "utf8");
const adminRoute = fs.readFileSync(path.join(root, "src/routes/admin.tsx"), "utf8");
const adminShell = fs.readFileSync(path.join(root, "src/components/admin/admin-shell.tsx"), "utf8");

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
  assert.match(suite, /select plan\(66\);/);
  assert.match(suite, /withdrawal RPC enforces the \$300 minimum/i);
  assert.match(withdrawalMigration, /p_method not in \('Bitcoin', 'Ethereum', 'Beldex'\)/i);
  assert.match(withdrawalMigration, /Invalid Ethereum destination address/);
  assert.match(withdrawalMigration, /Invalid Bitcoin destination address/);
  assert.match(withdrawalMigration, /Invalid Beldex destination address/);
  assert.match(withdrawalValidator, /0x\[0-9a-fA-F\]\{40\}/);
  assert.match(withdrawalValidator, /Invalid Bitcoin destination address/);
  assert.match(withdrawalValidator, /Invalid Beldex destination address/);
  assert.doesNotMatch(suite, /createUser|deleteUser|SUPABASE_SERVICE_ROLE_KEY/i);
  assert.match(operationsHardening, /Investment principal returned/);
  assert.match(operationsHardening, /global-beldex-daily-investment-accrual/);
  assert.match(operationsHardening, /0 0 \\* \\* \\*/);
  assert.match(operationsHardening, /admin_financial_reconciliation/);
  assert.match(operationsHardening, /p\.total_deposits,coalesce\(d\.amount,0\),p\.total_deposits-coalesce\(d\.amount,0\)/);
  assert.match(operationsHardening, /p\.total_withdrawals,coalesce\(w\.amount,0\),p\.total_withdrawals-coalesce\(w\.amount,0\)/);
  assert.match(operationsHardening, /p\.locked_balance-coalesce\(i\.active_principal,0\)/);
  assert.match(adminAuditIdentity, /select id\s+into v_admin_id\s+from public\.admin_user\s+where user_id = auth\.uid\(\)/i);
  assert.match(adminAuditIdentity, /alter column admin_id drop not null/i);
  for (const section of ["Transactions", "Users", "Investments", "KYC", "Reconciliation", "Audit log", "Operations"]) {
    assert.match(adminRoute, new RegExp(section));
    assert.match(adminShell, new RegExp(section === "Audit log" ? "Audit Log" : section));
  }
  for (const rpc of ["admin_approve_transaction", "admin_reject_transaction", "admin_settle_transaction", "admin_set_user_block", "admin_update_investment", "accrue_user_investments", "admin_approve_deposit", "admin_reject_deposit", "admin_approve_withdrawal", "admin_reject_withdrawal"]) {
    assert.match(adminRoute, new RegExp(rpc));
  }
  assert.match(adminRoute, /approve_transactions/);
  assert.match(adminRoute, /reject_transactions/);
  assert.match(adminRoute, /view_transactions/);
  assert.match(adminRoute, /view_audit_log/);
  assert.match(adminRoute, /admin_financial_reconciliation/);
  assert.match(adminRoute, /never writes balances, investments or transaction states directly/);
});
