begin;

-- These legacy balance-adjustment RPCs are not called by the current client.
-- Keep them unavailable through the authenticated PostgREST API. Existing
-- service_role grants are preserved for controlled server-side maintenance.
-- The active admin console continues to use permission-checked transaction
-- and investment RPCs; no financial rows or balances are changed by this DDL.
revoke all on function public.admin_fund_user(uuid,numeric,text)
  from public, anon, authenticated;
revoke all on function public.admin_adjust_balance(uuid,numeric,text)
  from public, anon, authenticated;

commit;
