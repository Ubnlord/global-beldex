import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const migration = fs.readFileSync(path.join(root, "migrations/0008_security_hardening_v1.sql"), "utf8");
const directWriteLockdown = fs.readFileSync(path.join(root, "migrations/0009_lock_down_direct_client_writes.sql"), "utf8");

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

test("security hardening migration keeps critical authorization controls", () => {
  for (const needle of mustContain) assert.ok(migration.includes(needle), `Missing security control: ${needle}`);
  assert.equal((migration.match(/grant execute on function public\.swap_assets\(/g) || []).length, 1);
});
