begin;

-- Defense-in-depth for administrator financial actions.
-- The browser supplies the authenticated user's UUID; resolve profiles by user_id.
-- Audit rows use the live admin_action_audit column names (admin_id/user_id).

create or replace function public.admin_fund_user(
  p_user_id uuid,
  p_amount numeric,
  p_reason text
)
returns public.user_profile
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_profile public.user_profile;
  v_admin uuid := auth.uid();
  v_before numeric;
begin
  if not public.admin_has_permission('approve_transactions') then
    raise exception 'not authorized';
  end if;

  if p_user_id is null or p_amount is null or p_amount <= 0 then
    raise exception 'invalid funding request';
  end if;

  if nullif(btrim(coalesce(p_reason,'')), '') is null then
    raise exception 'reason is required';
  end if;

  select * into v_profile
  from public.user_profile
  where user_id = p_user_id
  for update;

  if not found then
    raise exception 'user profile not found';
  end if;

  if v_profile.blocked then
    raise exception 'blocked user cannot receive funding';
  end if;

  v_before := v_profile.available_balance;

  update public.user_profile
  set available_balance = available_balance + p_amount,
      updated_at = now()
  where user_id = p_user_id
  returning * into v_profile;

  insert into public.transaction
    (user_id,type,amount,status,method,note,created_at)
  values
    (p_user_id,'bonus',p_amount,'completed','admin',btrim(p_reason),now());

  insert into public.admin_action_audit
    (admin_id,user_id,action,target_id,old_values,new_values,reason,created_at)
  values
    (v_admin,p_user_id,'fund_user',p_user_id,
     jsonb_build_object('available_balance',v_before),
     jsonb_build_object('available_balance',v_profile.available_balance),
     btrim(p_reason),now());

  return v_profile;
end;
$$;

create or replace function public.admin_adjust_balance(
  p_user_id uuid,
  p_delta numeric,
  p_reason text
)
returns public.user_profile
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_profile public.user_profile;
  v_admin uuid := auth.uid();
  v_before numeric;
  v_type text;
begin
  if not public.admin_has_permission('approve_transactions') then
    raise exception 'not authorized';
  end if;

  if p_user_id is null or p_delta is null or p_delta = 0 then
    raise exception 'invalid balance adjustment';
  end if;

  if nullif(btrim(coalesce(p_reason,'')), '') is null then
    raise exception 'reason is required';
  end if;

  select * into v_profile
  from public.user_profile
  where user_id = p_user_id
  for update;

  if not found then
    raise exception 'user profile not found';
  end if;

  if v_profile.blocked then
    raise exception 'blocked user cannot have balance adjusted';
  end if;

  if p_delta < 0 and v_profile.available_balance + p_delta < 0 then
    raise exception 'insufficient available balance';
  end if;

  v_before := v_profile.available_balance;

  update public.user_profile
  set available_balance = available_balance + p_delta,
      updated_at = now()
  where user_id = p_user_id
  returning * into v_profile;

  v_type := case when p_delta > 0 then 'bonus' else 'withdraw' end;

  insert into public.transaction
    (user_id,type,amount,status,method,note,created_at)
  values
    (p_user_id,v_type,abs(p_delta),'completed','admin',btrim(p_reason),now());

  insert into public.admin_action_audit
    (admin_id,user_id,action,target_id,old_values,new_values,reason,created_at)
  values
    (v_admin,p_user_id,'adjust_balance',p_user_id,
     jsonb_build_object('available_balance',v_before),
     jsonb_build_object('available_balance',v_profile.available_balance),
     btrim(p_reason),now());

  return v_profile;
end;
$$;

-- Transaction audit contains financial administration history and must be
-- readable only by authenticated administrators.
alter table public.transaction_audit enable row level security;
drop policy if exists transaction_audit_select on public.transaction_audit;
create policy transaction_audit_select
on public.transaction_audit
for select to authenticated
using ((select public.is_admin()));

revoke insert, update, delete, truncate, references, trigger
on table public.transaction_audit
from anon, authenticated;

grant select on table public.transaction_audit to authenticated;
revoke select on table public.transaction_audit from anon;

-- Keep the financial admin RPC surface closed to anonymous callers.
revoke execute on function public.admin_fund_user(uuid,numeric,text) from public, anon;
revoke execute on function public.admin_adjust_balance(uuid,numeric,text) from public, anon;
grant execute on function public.admin_fund_user(uuid,numeric,text) to authenticated, service_role;
grant execute on function public.admin_adjust_balance(uuid,numeric,text) to authenticated, service_role;

commit;
