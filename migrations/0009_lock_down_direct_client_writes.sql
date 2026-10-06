begin;

-- Remove legacy client-side write policies. Financial/profile mutations must
-- flow through controlled RPCs or trusted server-side functions.
drop policy if exists transactions_insert on public.transaction;
drop policy if exists transactions_update_admin on public.transaction;
drop policy if exists audit_insert_admin on public.transaction_audit;
drop policy if exists investments_insert on public.user_investment;
drop policy if exists investments_update_admin on public.user_investment;
drop policy if exists profiles_insert_own on public.user_profile;
drop policy if exists profiles_update on public.user_profile;

-- Remove duplicate legacy read policies where the hardened policy already
-- provides the intended access boundary.
drop policy if exists transactions_select on public.transaction;
drop policy if exists investments_select on public.user_investment;
drop policy if exists profiles_select on public.user_profile;
drop policy if exists admins_select_self on public.admin_user;
drop policy if exists investment_catalog_read on public.investment_plan_catalog;
drop policy if exists audit_select on public.transaction_audit;

-- Authenticated clients should read only through RLS. They must not receive
-- direct table write privileges for protected application data.
revoke insert, update, delete on table public.user_profile from anon, authenticated;
revoke insert, update, delete on table public.admin_user from anon, authenticated;
revoke insert, update, delete on table public.transaction from anon, authenticated;
revoke insert, update, delete on table public.transaction_audit from anon, authenticated;
revoke insert, update, delete on table public.investment_plan_catalog from anon, authenticated;
revoke insert, update, delete on table public.user_investment from anon, authenticated;

commit;
