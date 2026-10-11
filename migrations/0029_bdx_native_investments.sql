begin;

-- BDX-native investment accounting. Existing investments and transactions stay
-- USD-denominated by default; only new purchases explicitly use BDX.
alter table public.user_profile
  add column if not exists locked_bdx_balance numeric(38,18) not null default 0;

alter table public.user_investment
  add column if not exists currency text not null default 'USD'
    check (currency in ('USD','BDX'));

alter table public.transaction
  add column if not exists currency text not null default 'USD'
    check (currency in ('USD','BDX'));

-- New purchases are denominated and debited in BDX. The plan catalog's min/max
-- amounts already represent BDX amounts. Never convert these to USD here.
create or replace function public.buy_investment_plan(p_plan_id text,p_amount numeric)
returns public.user_investment
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
  v_plan public.investment_plan_catalog;
  v_profile public.user_profile;
  v_inv public.user_investment;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  perform public.assert_user_can_transact(v_uid);
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be greater than zero'; end if;

  select * into v_plan
  from public.investment_plan_catalog
  where id = p_plan_id and active;
  if v_plan.id is null then raise exception 'Investment plan not found'; end if;
  if p_amount < v_plan.min_amount then raise exception 'Minimum investment is % BDX',v_plan.min_amount; end if;
  if v_plan.max_amount is not null and p_amount > v_plan.max_amount then
    raise exception 'Maximum investment is % BDX',v_plan.max_amount;
  end if;

  select * into v_profile from public.user_profile where user_id = v_uid for update;
  if v_profile.user_id is null then raise exception 'Profile not found'; end if;
  if v_profile.bdx_balance < p_amount then raise exception 'Insufficient BDX balance'; end if;

  update public.user_profile
  set bdx_balance = bdx_balance - p_amount,
      locked_bdx_balance = locked_bdx_balance + p_amount,
      updated_at = now()
  where user_id = v_uid;

  insert into public.user_investment(user_id,plan_id,principal,daily_rate,duration_days,currency)
  values(v_uid,v_plan.id,p_amount,v_plan.daily_rate,v_plan.duration_days,'BDX')
  returning * into v_inv;

  insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
  values(v_uid,'plan',p_amount,'BDX','completed','approved',v_plan.name,'BDX-denominated investment purchase');
  return v_inv;
end;
$function$;

revoke all on function public.buy_investment_plan(text,numeric) from public, anon;
grant execute on function public.buy_investment_plan(text,numeric) to authenticated;

-- Accrue by each investment's recorded currency. Row locks plus last_accrual_at
-- make retries safe; maturity principal is returned in the same currency once.
create or replace function public.accrue_user_investments(p_user_id uuid default auth.uid())
returns numeric
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_uid uuid := coalesce(p_user_id, auth.uid());
  v_inv public.user_investment;
  v_now timestamptz := now();
  v_elapsed_days integer;
  v_previous_days integer;
  v_days integer;
  v_profit numeric;
  v_principal_return numeric;
  v_total numeric := 0;
  v_done boolean;
  v_admin boolean := public.is_admin();
  v_scheduled boolean := auth.uid() is null;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  if v_uid <> auth.uid() then
    if not v_scheduled and (not v_admin or not public.admin_has_permission('manage_users')) then
      raise exception 'Permission denied';
    end if;
  end if;
  perform public.assert_user_can_transact(v_uid);

  for v_inv in
    select * from public.user_investment
    where user_id = v_uid and status = 'active' and daily_accrual_enabled = true
    order by created_at
    for update
  loop
    v_elapsed_days := least(v_inv.duration_days,
      greatest(0, floor(extract(epoch from (v_now - v_inv.started_at))/86400)::integer));
    v_previous_days := least(v_inv.duration_days,
      greatest(0, floor(extract(epoch from (v_inv.last_accrual_at - v_inv.started_at))/86400)::integer));
    v_days := greatest(0, v_elapsed_days - v_previous_days);

    if v_days > 0 then
      v_profit := v_inv.principal * v_inv.daily_rate * v_days;
      v_done := v_elapsed_days >= v_inv.duration_days;
      v_principal_return := case when v_done then v_inv.principal else 0 end;
      -- Preserve the legacy numeric return value as USD-only; BDX profit is
      -- credited and ledgered in BDX but must not be summed with USD.
      if coalesce(v_inv.currency,'USD') = 'USD' then
        v_total := v_total + v_profit;
      end if;

      if v_inv.currency = 'BDX' then
        update public.user_profile
        set bdx_balance = bdx_balance + v_profit + v_principal_return,
            locked_bdx_balance = case when v_done then greatest(0,locked_bdx_balance-v_inv.principal) else locked_bdx_balance end,
            updated_at = now()
        where user_id = v_uid;
      else
        update public.user_profile
        set available_balance = available_balance + v_profit + v_principal_return,
            locked_balance = case when v_done then greatest(0,locked_balance-v_inv.principal) else locked_balance end,
            updated_at = now()
        where user_id = v_uid;
      end if;

      update public.user_investment
      set credited_profit = credited_profit + v_profit,
          last_accrual_at = least(v_inv.started_at + make_interval(days => v_inv.duration_days), v_now),
          status = case when v_done then 'completed' else 'active' end,
          completed_at = case when v_done then v_now else completed_at end,
          updated_at = now()
      where id = v_inv.id;

      insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
      values(v_uid,'bonus',v_profit,v_inv.currency,'completed','approved',
        case when v_done then 'Plan maturity' else 'Daily interest' end,
        'Server-side investment profit');

      if v_done then
        insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
        values(v_uid,'bonus',v_inv.principal,v_inv.currency,'completed','approved',
          'Plan maturity','Investment principal returned');
      end if;
    end if;
  end loop;
  return v_total;
end;
$function$;

revoke all on function public.accrue_user_investments(uuid) from public, anon;
grant execute on function public.accrue_user_investments(uuid) to authenticated;


-- Keep the existing USD reconciliation scoped to legacy USD-denominated
-- investments; BDX investments have their own locked wallet and must not be
-- mixed into USD totals.
create or replace function public.admin_financial_reconciliation()
returns table(
  user_id uuid,
  available_balance numeric,
  locked_balance numeric,
  expected_locked_balance numeric,
  locked_delta numeric,
  total_deposits numeric,
  recorded_deposits numeric,
  deposits_delta numeric,
  total_withdrawals numeric,
  recorded_withdrawals numeric,
  withdrawals_delta numeric,
  referral_earnings numeric,
  recorded_referrals numeric,
  referral_delta numeric,
  credited_investment_profit numeric,
  recorded_investment_profit numeric,
  investment_profit_delta numeric,
  negative_balance boolean
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not public.is_admin() then raise exception 'Permission denied'; end if;
  return query
  with deposit_totals as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='deposit' and t.status='completed' and t.currency='USD' group by t.user_id
  ),
  withdrawal_totals as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='withdraw' and t.status='completed' and t.currency='USD' group by t.user_id
  ),
  referral_totals as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='referral' and t.status='completed' group by t.user_id
  ),
  investment_profit_totals as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='bonus' and t.status='completed' and t.note='Server-side investment profit' and t.currency='USD'
    group by t.user_id
  ),
  investment_totals as (
    select ui.user_id,
      coalesce(sum(ui.principal) filter(where ui.status='active' and ui.currency='USD'),0) active_principal,
      coalesce(sum(ui.credited_profit) filter(where ui.currency='USD'),0) credited_profit
    from public.user_investment ui group by ui.user_id
  )
  select p.user_id,p.available_balance,p.locked_balance,
    coalesce(i.active_principal,0),p.locked_balance-coalesce(i.active_principal,0),
    p.total_deposits,coalesce(d.amount,0),p.total_deposits-coalesce(d.amount,0),
    p.total_withdrawals,coalesce(w.amount,0),p.total_withdrawals-coalesce(w.amount,0),
    p.referral_earnings,coalesce(r.amount,0),p.referral_earnings-coalesce(r.amount,0),
    coalesce(i.credited_profit,0),coalesce(ip.amount,0),coalesce(i.credited_profit,0)-coalesce(ip.amount,0),
    p.available_balance<0 or p.locked_balance<0 or p.bdx_balance<0 or p.locked_bdx_balance<0
  from public.user_profile p
  left join deposit_totals d on d.user_id=p.user_id
  left join withdrawal_totals w on w.user_id=p.user_id
  left join referral_totals r on r.user_id=p.user_id
  left join investment_profit_totals ip on ip.user_id=p.user_id
  left join investment_totals i on i.user_id=p.user_id
  order by p.created_at;
end;
$function$;


-- Currency-aware admin search exposes both wallet balances without combining
-- BDX with USD-equivalent accounting.
create or replace function public.admin_search_users_bdx(
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
  bdx_balance numeric,
  locked_bdx_balance numeric,
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
as $function$
declare
  v_query text := lower(trim(coalesce(p_query,'')));
  v_limit integer := greatest(1,least(coalesce(p_limit,50),100));
begin
  if not public.is_admin() or not public.admin_has_permission('manage_users') then
    raise exception 'Permission denied';
  end if;
  return query
  select p.user_id,u.email::text,p.username,p.fullname,p.phone,p.country,p.kyc_status,
    p.available_balance,p.locked_balance,p.bdx_balance,p.locked_bdx_balance,
    p.total_deposits,p.total_withdrawals,p.referral_earnings,p.blocked,p.blocked_reason,p.blocked_at,p.created_at
  from public.user_profile p
  join auth.users u on u.id=p.user_id
  where v_query=''
    or lower(coalesce(u.email,'')) like '%'||v_query||'%'
    or lower(coalesce(p.username,'')) like '%'||v_query||'%'
    or lower(coalesce(p.fullname,'')) like '%'||v_query||'%'
    or lower(coalesce(p.country,'')) like '%'||v_query||'%'
    or p.user_id::text like '%'||v_query||'%'
  order by p.created_at desc
  limit v_limit;
end;
$function$;
revoke all on function public.admin_search_users_bdx(text,integer) from public,anon;
grant execute on function public.admin_search_users_bdx(text,integer) to authenticated;

commit;
