-- 0017: reconcile live audit lockdown and fix admin investment management.
--
-- The live database already contains the intended audit restrictions from
-- manually applied hardening. This migration makes that state reproducible
-- and fixes two correctness issues in admin_manage_investment.

begin;

drop policy if exists transaction_audit_select_own_or_admin on public.transaction_audit;
drop policy if exists transaction_audit_select on public.transaction_audit;
create policy transaction_audit_select
  on public.transaction_audit
  for select to authenticated
  using (public.is_admin());

drop policy if exists admin_action_audit_select on public.admin_action_audit;
create policy admin_action_audit_select
  on public.admin_action_audit
  for select to authenticated
  using (public.is_admin());

revoke insert, update, delete, truncate on public.transaction_audit from anon, authenticated;
revoke insert, update, delete, truncate on public.admin_action_audit from anon, authenticated;

create index if not exists admin_action_audit_admin_id_idx
  on public.admin_action_audit(admin_id);

alter table public.admin_user
  drop constraint if exists admin_user_user_id_unique;

create or replace function public.admin_manage_investment(
  p_investment_id uuid,
  p_daily_rate numeric,
  p_status text,
  p_reason text
)
returns public.user_investment
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_inv public.user_investment;
  v_profile public.user_profile;
  v_admin uuid := auth.uid();
  v_old_status text;
begin
  if not public.admin_has_permission('manage_users') then
    raise exception 'not authorized';
  end if;

  if p_daily_rate is null or p_daily_rate < 0 then
    raise exception 'invalid daily rate';
  end if;

  if p_status not in ('active','completed','cancelled') then
    raise exception 'invalid investment status';
  end if;

  if nullif(btrim(coalesce(p_reason,'')), '') is null then
    raise exception 'reason is required';
  end if;

  select * into v_inv
    from public.user_investment
   where id = p_investment_id
   for update;

  if not found then raise exception 'investment not found'; end if;
  v_old_status := v_inv.status;

  select * into v_profile
    from public.user_profile
   where user_id = v_inv.user_id
   for update;

  if not found then raise exception 'user profile not found'; end if;
  if v_profile.blocked then
    raise exception 'blocked user cannot have investment managed';
  end if;

  if v_old_status = 'active' and p_status in ('completed','cancelled') then
    update public.user_profile
       set locked_balance = greatest(0, locked_balance - v_inv.principal),
           available_balance = available_balance + v_inv.principal,
           updated_at = now()
     where user_id = v_inv.user_id;
  elsif v_old_status in ('completed','cancelled') and p_status = 'active' then
    if v_profile.available_balance < v_inv.principal then
      raise exception 'insufficient available balance';
    end if;

    update public.user_profile
       set available_balance = available_balance - v_inv.principal,
           locked_balance = locked_balance + v_inv.principal,
           updated_at = now()
     where user_id = v_inv.user_id;
  end if;

  update public.user_investment
     set daily_rate = p_daily_rate,
         status = p_status,
         completed_at = case
           when p_status in ('completed','cancelled') then coalesce(completed_at, now())
           else null
         end,
         updated_at = now()
   where id = p_investment_id
  returning * into v_inv;

  insert into public.admin_action_audit
    (admin_id, user_id, action, target_id, old_values, new_values, reason, created_at)
  values
    (v_admin, v_inv.user_id, 'manage_investment', v_inv.id,
     jsonb_build_object('status', v_old_status),
     jsonb_build_object('status', v_inv.status, 'daily_rate', v_inv.daily_rate),
     btrim(p_reason), now());

  return v_inv;
end;
$function$;

revoke execute on function public.admin_manage_investment(uuid,numeric,text,text) from anon, public;
grant execute on function public.admin_manage_investment(uuid,numeric,text,text) to authenticated, service_role;

commit;
