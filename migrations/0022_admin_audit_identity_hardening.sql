begin;

-- Fix the admin audit actor identity used by financial admin RPCs.
-- admin_action_audit.admin_id references admin_user.id, while auth.uid()
-- is the administrator's auth.users.id. Resolve the internal admin row first.
--
-- The FK already uses ON DELETE SET NULL, so admin_id must be nullable to
-- preserve historical audit rows when an administrator is removed.

alter table public.admin_action_audit
  alter column admin_id drop not null;

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
  v_admin_id uuid;
  v_before numeric;
  v_reason text := nullif(btrim(coalesce(p_reason,'')), '');
begin
  select id
    into v_admin_id
  from public.admin_user
  where user_id = auth.uid();

  if v_admin_id is null or not public.admin_has_permission('approve_transactions') then
    raise exception 'not authorized';
  end if;

  if p_user_id is null or p_amount is null or p_amount <= 0 then
    raise exception 'invalid funding request';
  end if;

  if v_reason is null then
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
    (user_id,type,amount,status,method,note,approved_by,approval_status,approval_reason,approved_at,settled_at,created_at)
  values
    (p_user_id,'bonus',p_amount,'completed','admin',v_reason,v_admin_id,'approved',v_reason,now(),now(),now());

  insert into public.admin_action_audit
    (admin_id,user_id,action,target_id,old_values,new_values,reason,created_at)
  values
    (v_admin_id,p_user_id,'fund_user',p_user_id,
     jsonb_build_object('available_balance',v_before),
     jsonb_build_object('available_balance',v_profile.available_balance),
     v_reason,now());

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
  v_admin_id uuid;
  v_before numeric;
  v_type text;
  v_reason text := nullif(btrim(coalesce(p_reason,'')), '');
begin
  select id
    into v_admin_id
  from public.admin_user
  where user_id = auth.uid();

  if v_admin_id is null or not public.admin_has_permission('approve_transactions') then
    raise exception 'not authorized';
  end if;

  if p_user_id is null or p_delta is null or p_delta = 0 then
    raise exception 'invalid balance adjustment';
  end if;

  if v_reason is null then
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
  v_type := case when p_delta > 0 then 'bonus' else 'withdraw' end;

  update public.user_profile
  set available_balance = available_balance + p_delta,
      updated_at = now()
  where user_id = p_user_id
  returning * into v_profile;

  insert into public.transaction
    (user_id,type,amount,status,method,note,approved_by,approval_status,approval_reason,approved_at,settled_at,created_at)
  values
    (p_user_id,v_type,abs(p_delta),'completed','admin',v_reason,v_admin_id,'approved',v_reason,now(),now(),now());

  insert into public.admin_action_audit
    (admin_id,user_id,action,target_id,old_values,new_values,reason,created_at)
  values
    (v_admin_id,p_user_id,'adjust_balance',p_user_id,
     jsonb_build_object('available_balance',v_before),
     jsonb_build_object('available_balance',v_profile.available_balance),
     v_reason,now());

  return v_profile;
end;
$$;

revoke execute on function public.admin_fund_user(uuid,numeric,text) from public, anon;
revoke execute on function public.admin_adjust_balance(uuid,numeric,text) from public, anon;
grant execute on function public.admin_fund_user(uuid,numeric,text) to authenticated, service_role;
grant execute on function public.admin_adjust_balance(uuid,numeric,text) to authenticated, service_role;

commit;
