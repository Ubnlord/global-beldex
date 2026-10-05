-- Global Beldex admin user controls and investment regulation.
-- Adds application-level blocking, auditable investment accrual controls,
-- and secure admin user search.

alter table public.user_profile
  add column if not exists blocked boolean not null default false,
  add column if not exists blocked_reason text,
  add column if not exists blocked_at timestamptz;

alter table public.user_investment
  add column if not exists daily_accrual_enabled boolean not null default true;

create index if not exists user_profile_blocked_idx
  on public.user_profile(blocked);

create index if not exists user_investment_accrual_enabled_idx
  on public.user_investment(status,daily_accrual_enabled,last_accrual_at);

create table if not exists public.admin_action_audit (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.admin_user(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_id uuid,
  old_values jsonb,
  new_values jsonb,
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists admin_action_audit_user_id_idx
  on public.admin_action_audit(user_id,created_at desc);

create index if not exists admin_action_audit_created_at_idx
  on public.admin_action_audit(created_at desc);

alter table public.admin_action_audit enable row level security;

drop policy if exists admin_action_audit_select on public.admin_action_audit;
create policy admin_action_audit_select
  on public.admin_action_audit
  for select to authenticated
  using (public.is_admin());

create or replace function public.admin_search_users(
  p_query text default '',
  p_limit integer default 50
)
returns table (
  user_id uuid,
  email text,
  username text,
  fullname text,
  phone text,
  country text,
  kyc_status text,
  available_balance numeric,
  locked_balance numeric,
  total_deposits numeric,
  total_withdrawals numeric,
  referral_earnings numeric,
  blocked boolean,
  blocked_reason text,
  blocked_at timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_query text := lower(trim(coalesce(p_query,'')));
  v_limit integer := greatest(1, least(coalesce(p_limit,50),100));
begin
  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  return query
  select
    p.user_id,
    u.email::text,
    p.username,
    p.fullname,
    p.phone,
    p.country,
    p.kyc_status,
    p.available_balance,
    p.locked_balance,
    p.total_deposits,
    p.total_withdrawals,
    p.referral_earnings,
    p.blocked,
    p.blocked_reason,
    p.blocked_at,
    p.created_at
  from public.user_profile p
  join auth.users u on u.id = p.user_id
  where v_query = ''
     or lower(coalesce(u.email,'')) like '%' || v_query || '%'
     or lower(coalesce(p.username,'')) like '%' || v_query || '%'
     or lower(coalesce(p.fullname,'')) like '%' || v_query || '%'
     or lower(coalesce(p.country,'')) like '%' || v_query || '%'
     or p.user_id::text like '%' || v_query || '%'
  order by p.created_at desc
  limit v_limit;
end;
$$;

create or replace function public.admin_set_user_block(
  p_user_id uuid,
  p_blocked boolean,
  p_reason text default null
)
returns public.user_profile
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_admin public.admin_user;
  v_old public.user_profile;
  v_new public.user_profile;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
begin
  select * into v_admin from public.admin_user where user_id = auth.uid();

  if v_admin.id is null then
    raise exception 'Admin access required';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'Administrators cannot block their own account';
  end if;

  select * into v_old
  from public.user_profile
  where user_id = p_user_id
  for update;

  if v_old.user_id is null then
    raise exception 'User profile not found';
  end if;

  update public.user_profile
  set blocked = p_blocked,
      blocked_reason = case when p_blocked then v_reason else null end,
      blocked_at = case when p_blocked then now() else null end,
      updated_at = now()
  where user_id = p_user_id
  returning * into v_new;

  insert into public.admin_action_audit(
    admin_id,user_id,action,target_id,old_values,new_values,reason
  )
  values(
    v_admin.id,p_user_id,
    case when p_blocked then 'user_blocked' else 'user_unblocked' end,
    p_user_id,
    jsonb_build_object('blocked',v_old.blocked,'blocked_reason',v_old.blocked_reason),
    jsonb_build_object('blocked',v_new.blocked,'blocked_reason',v_new.blocked_reason),
    v_reason
  );

  return v_new;
end;
$$;

create or replace function public.admin_update_investment(
  p_investment_id uuid,
  p_daily_rate numeric default null,
  p_daily_accrual_enabled boolean default null
)
returns public.user_investment
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_admin public.admin_user;
  v_old public.user_investment;
  v_new public.user_investment;
begin
  select * into v_admin from public.admin_user where user_id = auth.uid();

  if v_admin.id is null then
    raise exception 'Admin access required';
  end if;

  select * into v_old
  from public.user_investment
  where id = p_investment_id
  for update;

  if v_old.id is null then
    raise exception 'Investment not found';
  end if;

  if p_daily_rate is not null and p_daily_rate < 0 then
    raise exception 'Daily rate cannot be negative';
  end if;

  update public.user_investment
  set daily_rate = coalesce(p_daily_rate,daily_rate),
      daily_accrual_enabled = coalesce(p_daily_accrual_enabled,daily_accrual_enabled),
      updated_at = now()
  where id = p_investment_id
  returning * into v_new;

  insert into public.admin_action_audit(
    admin_id,user_id,action,target_id,old_values,new_values,reason
  )
  values(
    v_admin.id,v_old.user_id,'investment_updated',p_investment_id,
    jsonb_build_object(
      'daily_rate',v_old.daily_rate,
      'daily_accrual_enabled',v_old.daily_accrual_enabled
    ),
    jsonb_build_object(
      'daily_rate',v_new.daily_rate,
      'daily_accrual_enabled',v_new.daily_accrual_enabled
    ),
    'Administrator updated investment accrual settings'
  );

  return v_new;
end;
$$;

create or replace function public.accrue_user_investments(p_user_id uuid default auth.uid())
returns numeric
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := coalesce(p_user_id,auth.uid());
  v_inv public.user_investment;
  v_now timestamptz := now();
  v_elapsed_days integer;
  v_previous_days integer;
  v_days integer;
  v_profit numeric;
  v_total numeric := 0;
  v_done boolean;
  v_admin boolean := public.is_admin();
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  if v_uid <> auth.uid() and not v_admin then raise exception 'Forbidden'; end if;

  if exists (
    select 1 from public.user_profile
    where user_id = v_uid and blocked = true
  ) then
    raise exception 'User account is blocked';
  end if;

  for v_inv in
    select * from public.user_investment
    where user_id = v_uid and status = 'active' and daily_accrual_enabled = true
    order by created_at
    for update
  loop
    v_elapsed_days := least(v_inv.duration_days,greatest(0,floor(extract(epoch from(v_now-v_inv.started_at))/86400)::integer));
    v_previous_days := least(v_inv.duration_days,greatest(0,floor(extract(epoch from(v_inv.last_accrual_at-v_inv.started_at))/86400)::integer));
    v_days := greatest(0,v_elapsed_days-v_previous_days);

    if v_days > 0 then
      v_profit := v_inv.principal*v_inv.daily_rate*v_days;
      v_total := v_total+v_profit;
      v_done := v_elapsed_days >= v_inv.duration_days;

      update public.user_profile
      set available_balance=available_balance+v_profit,
          locked_balance=case when v_done then greatest(0,locked_balance-v_inv.principal) else locked_balance end,
          updated_at=now()
      where user_id=v_uid;

      update public.user_investment
      set credited_profit=credited_profit+v_profit,
          last_accrual_at=least(v_inv.started_at+make_interval(days=>v_inv.duration_days),v_now),
          status=case when v_done then 'completed' else 'active' end,
          completed_at=case when v_done then v_now else completed_at end,
          updated_at=now()
      where id=v_inv.id;

      insert into public.transaction(user_id,type,amount,status,approval_status,method,note)
      values(
        v_uid,'bonus',v_profit,'completed','approved',
        case when v_done then 'Plan maturity' else 'Daily interest' end,
        'Server-side investment profit'
      );
    end if;
  end loop;

  return v_total;
end;
$$;

grant execute on function public.admin_search_users(text,integer) to authenticated;
grant execute on function public.admin_set_user_block(uuid,boolean,text) to authenticated;
grant execute on function public.admin_update_investment(uuid,numeric,boolean) to authenticated;

revoke execute on function public.admin_search_users(text,integer) from public, anon;
revoke execute on function public.admin_set_user_block(uuid,boolean,text) from public, anon;
revoke execute on function public.admin_update_investment(uuid,numeric,boolean) from public, anon;
