import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const migration = fs.readFileSync(path.join(root, "migrations/0008_security_hardening_v1.sql"), "utf8");
const directWriteLockdown = fs.readFileSync(path.join(root, "migrations/0009_lock_down_direct_client_writes.sql"), "utf8");
const databaseDefense = fs.readFileSync(path.join(root, "migrations/0011_database_api_defense_in_depth.sql"), "utf8");
const authorizationTightening = fs.readFileSync(path.join(root, "migrations/0012_tighten_authorization_helpers.sql"), "utf8");
const anonymousAuditLockdown = fs.readFileSync(path.join(root, "migrations/0013_remove_anon_audit_access.sql"), "utf8");
const adminFinancialControls = fs.readFileSync(path.join(root, "migrations/0014_admin_financial_controls.sql"), "utf8");
const legacyBalanceRpcLockdown = fs.readFileSync(path.join(root, "migrations/0023_revoke_unused_legacy_balance_rpcs.sql"), "utf8");

const mustContain = [
  "revoke all on function public.admin_has_permission(text) from public, anon, authenticated;",
  "and p_permission = any(coalesce(a.permissions, '{}'::text[]))",
  "revoke all on function public.assert_user_can_transact(uuid) from public, anon, authenticated;",
  "grant execute on function public.create_financial_transaction(text,numeric,text,text,uuid) to authenticated;",
  "grant execute on function public.buy_investment_plan(text,numeric) to authenticated;",
  "grant execute on function public.accrue_user_investments(uuid) to authenticated;",
  "grant execute on function public.admin_set_user_block(uuid,boolean,text) to authenticated;",
  "grant execute on function public.admin_update_investment(uuid,numeric,boolean) to authenticated;",
  "grant execute on function public.admin_approve_transaction(uuid,text) to authenticated;",
  "grant execute on function public.admin_reject_transaction(uuid,text) to authenticated;",
  "grant execute on function public.admin_settle_transaction(uuid,text) to authenticated;",
  "revoke all on function public.swap_assets(uuid,text,text,numeric,numeric) from public, anon, authenticated;",
  "grant execute on function public.swap_assets(uuid,text,text,numeric,numeric) to service_role;",
  "create unique index if not exists transaction_user_request_id_uq",
  "perform public.assert_user_can_transact(v_uid);",
  "alter table public.user_profile enable row level security;",
  "alter table public.admin_user enable row level security;",
  "alter table public.transaction enable row level security;",
  "alter table public.transaction_audit enable row level security;",
  "alter table public.investment_plan_catalog enable row level security;",
  "alter table public.user_investment enable row level security;",
  "create policy user_profile_select_own_or_admin",
  "create policy transaction_select_own_or_admin",
  "create policy transaction_audit_select_own_or_admin",
];

test("database/API defense-in-depth migrations keep critical controls", () => {
  for (const needle of mustContain) assert.ok(migration.includes(needle), `Missing security control: ${needle}`);
  assert.equal((migration.match(/grant execute on function public\\.swap_assets\\(/g) || []).length, 1);

  for (const needle of [
    "revoke all on table public.books from anon, authenticated;",
    "revoke insert, update, delete, truncate, references, trigger on table public.admin_action_audit from anon, authenticated;",
    "check (available_balance >= 0)",
    "check (locked_balance >= 0)",
    "check (bdx_balance >= 0)",
    "check (amount > 0)",
    "check (principal > 0)",
    "check (daily_rate >= 0)",
    "check (duration_days > 0)",
    "check (credited_profit >= 0)",
  ]) assert.ok(databaseDefense.includes(needle), `Missing defense-in-depth control: ${needle}`);

  assert.match(authorizationTightening, /revoke all on function public\\.is_admin\\(\\) from public, anon, authenticated;/i);
  assert.match(authorizationTightening, /unique \\(user_id\\)/i);
  assert.match(anonymousAuditLockdown, /revoke select on table public\\.admin_action_audit from anon;/i);
});

test("unused legacy balance RPCs are not callable by client roles", () => {
  assert.match(legacyBalanceRpcLockdown, /revoke all on function public\\.admin_fund_user\\(uuid,numeric,text\\)\\s+from public, anon, authenticated;/i);
  assert.match(legacyBalanceRpcLockdown, /revoke all on function public\\.admin_adjust_balance\\(uuid,numeric,text\\)\\s+from public, anon, authenticated;/i);
  assert.doesNotMatch(legacyBalanceRpcLockdown, /grant execute on function public\\.(admin_fund_user|admin_adjust_balance).*to authenticated/i);
});
