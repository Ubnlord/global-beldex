begin;

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = pg_catalog, public, pg_temp
as $function$
  select exists (select 1 from public.admin_user where user_id = auth.uid());
$function$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

alter table public.user_profile enable row level security;
alter table public.admin_user enable row level security;
alter table public.transaction enable row level security;
alter table public.transaction_audit enable row level security;

drop policy if exists user_profile_select_own_or_admin on public.user_profile;
create policy user_profile_select_own_or_admin on public.user_profile for select to authenticated using ((select auth.uid()) = user_id or public.is_admin());

drop policy if exists admin_user_select_own_or_admin on public.admin_user;
create policy admin_user_select_own_or_admin on public.admin_user for select to authenticated using ((select auth.uid()) = user_id or public.is_admin());

drop policy if exists transactions_select_own_or_admin on public.transaction;
create policy transactions_select_own_or_admin on public.transaction for select to authenticated using ((select auth.uid()) = user_id or public.is_admin());

drop policy if exists transaction_audit_select_own_or_admin on public.transaction_audit;
create policy transaction_audit_select_own_or_admin on public.transaction_audit for select to authenticated using (public.is_admin() or exists (select 1 from public.transaction t where t.id = transaction_id and t.user_id = auth.uid()));

revoke insert, update, delete, truncate, references, trigger on table public.user_profile, public.admin_user, public.transaction, public.transaction_audit from anon, authenticated;
commit;
