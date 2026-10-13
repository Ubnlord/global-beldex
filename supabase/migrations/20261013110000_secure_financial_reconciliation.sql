begin;

-- Financial reconciliation exposes account-level balances and ledger discrepancies.
-- Require both administrator status and the dedicated financial-reconciliation permission.
-- Keep the existing return contract and currency-separated calculations unchanged.

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
  if not public.is_admin()
     or not public.admin_has_permission('view_financial_reconciliation') then
    raise exception 'Permission denied';
  end if;

  return query
  with d as (
    select t.user_id, sum(t.amount) amount
    from public.transaction t
    where t.type='deposit' and t.status='completed'
      and coalesce(t.currency,'USD')='USD'
    group by t.user_id
  ),
  w as (
    select t.user_id, sum(t.amount) amount
    from public.transaction t
    where t.type='withdraw' and t.status='completed'
      and coalesce(t.currency,'USD')='USD'
    group by t.user_id
  ),
  r as (
    select t.user_id, sum(t.amount) amount
    from public.transaction t
    where t.type='referral' and t.status='completed'
      and coalesce(t.currency,'USD')='USD'
    group by t.user_id
  ),
  ip as (
    select t.user_id, sum(t.amount) amount
    from public.transaction t
    where t.type='bonus' and t.status='completed'
      and t.note='Server-side investment profit'
      and coalesce(t.currency,'USD')='USD'
    group by t.user_id
  ),
  inv as (
    select ui.user_id,
      coalesce(sum(ui.principal) filter (
        where ui.status='active' and coalesce(ui.currency,'USD')='USD'
      ),0) active_principal,
      coalesce(sum(ui.credited_profit) filter (
        where coalesce(ui.currency,'USD')='USD'
      ),0) profit
    from public.user_investment ui
    group by ui.user_id
  )
  select p.user_id, p.available_balance, p.locked_balance,
    coalesce(inv.active_principal,0),
    p.locked_balance-coalesce(inv.active_principal,0),
    p.total_deposits, coalesce(d.amount,0),
    p.total_deposits-coalesce(d.amount,0),
    p.total_withdrawals, coalesce(w.amount,0),
    p.total_withdrawals-coalesce(w.amount,0),
    p.referral_earnings, coalesce(r.amount,0),
    p.referral_earnings-coalesce(r.amount,0),
    coalesce(inv.profit,0), coalesce(ip.amount,0),
    coalesce(inv.profit,0)-coalesce(ip.amount,0),
    p.available_balance<0 or p.locked_balance<0
      or p.bdx_balance<0 or p.locked_bdx_balance<0
  from public.user_profile p
  left join d on d.user_id=p.user_id
  left join w on w.user_id=p.user_id
  left join r on r.user_id=p.user_id
  left join ip on ip.user_id=p.user_id
  left join inv on inv.user_id=p.user_id
  order by p.created_at;
end;
$function$;

create or replace function public.admin_financial_reconciliation_v2()
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
  bdx_balance numeric,
  locked_bdx_balance numeric,
  expected_locked_bdx_balance numeric,
  locked_bdx_delta numeric,
  total_deposits_bdx numeric,
  recorded_deposits_bdx numeric,
  deposits_bdx_delta numeric,
  total_withdrawals_bdx numeric,
  recorded_withdrawals_bdx numeric,
  withdrawals_bdx_delta numeric,
  credited_investment_profit_bdx numeric,
  recorded_investment_profit_bdx numeric,
  investment_profit_bdx_delta numeric,
  negative_balance boolean
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not public.is_admin()
     or not public.admin_has_permission('view_financial_reconciliation') then
    raise exception 'Permission denied';
  end if;

  return query
  with d_usd as (
    select t.user_id, coalesce(sum(t.amount),0) amount
    from public.transaction t
    where t.type='deposit' and t.status='completed'
      and coalesce(t.currency,'USD')='USD'
    group by t.user_id
  ),
  w_usd as (
    select t.user_id, coalesce(sum(t.amount),0) amount
    from public.transaction t
    where t.type='withdraw' and t.status='completed'
      and coalesce(t.currency,'USD')='USD'
    group by t.user_id
  ),
  d_bdx as (
    select t.user_id, coalesce(sum(t.amount),0) amount
    from public.transaction t
    where t.type='deposit' and t.status='completed' and t.currency='BDX'
    group by t.user_id
  ),
  w_bdx as (
    select t.user_id, coalesce(sum(t.amount),0) amount
    from public.transaction t
    where t.type='withdraw' and t.status='completed' and t.currency='BDX'
    group by t.user_id
  ),
  r as (
    select t.user_id, coalesce(sum(t.amount),0) amount
    from public.transaction t
    where t.type='referral' and t.status='completed'
      and coalesce(t.currency,'USD')='USD'
    group by t.user_id
  ),
  ip_usd as (
    select t.user_id, coalesce(sum(t.amount),0) amount
    from public.transaction t
    where t.type='bonus' and t.status='completed'
      and t.note='Server-side investment profit'
      and coalesce(t.currency,'USD')='USD'
    group by t.user_id
  ),
  ip_bdx as (
    select t.user_id, coalesce(sum(t.amount),0) amount
    from public.transaction t
    where t.type='bonus' and t.status='completed'
      and t.note='Server-side investment profit' and t.currency='BDX'
    group by t.user_id
  ),
  inv as (
    select ui.user_id,
      coalesce(sum(ui.principal) filter (
        where ui.status='active' and coalesce(ui.currency,'USD')='USD'
      ),0) active_usd,
      coalesce(sum(ui.credited_profit) filter (
        where coalesce(ui.currency,'USD')='USD'
      ),0) profit_usd,
      coalesce(sum(ui.principal) filter (
        where ui.status='active' and ui.currency='BDX'
      ),0) active_bdx,
      coalesce(sum(ui.credited_profit) filter (
        where ui.currency='BDX'
      ),0) profit_bdx
    from public.user_investment ui
    group by ui.user_id
  )
  select p.user_id, p.available_balance, p.locked_balance,
    coalesce(inv.active_usd,0),
    p.locked_balance-coalesce(inv.active_usd,0),
    p.total_deposits, coalesce(d_usd.amount,0),
    p.total_deposits-coalesce(d_usd.amount,0),
    p.total_withdrawals, coalesce(w_usd.amount,0),
    p.total_withdrawals-coalesce(w_usd.amount,0),
    p.referral_earnings, coalesce(r.amount,0),
    p.referral_earnings-coalesce(r.amount,0),
    coalesce(inv.profit_usd,0), coalesce(ip_usd.amount,0),
    coalesce(inv.profit_usd,0)-coalesce(ip_usd.amount,0),
    p.bdx_balance, p.locked_bdx_balance, coalesce(inv.active_bdx,0),
    p.locked_bdx_balance-coalesce(inv.active_bdx,0),
    p.total_deposits_bdx, coalesce(d_bdx.amount,0),
    p.total_deposits_bdx-coalesce(d_bdx.amount,0),
    p.total_withdrawals_bdx, coalesce(w_bdx.amount,0),
    p.total_withdrawals_bdx-coalesce(w_bdx.amount,0),
    coalesce(inv.profit_bdx,0), coalesce(ip_bdx.amount,0),
    coalesce(inv.profit_bdx,0)-coalesce(ip_bdx.amount,0),
    p.available_balance<0 or p.locked_balance<0
      or p.bdx_balance<0 or p.locked_bdx_balance<0
  from public.user_profile p
  left join d_usd on d_usd.user_id=p.user_id
  left join w_usd on w_usd.user_id=p.user_id
  left join d_bdx on d_bdx.user_id=p.user_id
  left join w_bdx on w_bdx.user_id=p.user_id
  left join r on r.user_id=p.user_id
  left join ip_usd on ip_usd.user_id=p.user_id
  left join ip_bdx on ip_bdx.user_id=p.user_id
  left join inv on inv.user_id=p.user_id
  order by p.created_at;
end;
$function$;

revoke all on function public.admin_financial_reconciliation() from public, anon;
revoke all on function public.admin_financial_reconciliation_v2() from public, anon;
grant execute on function public.admin_financial_reconciliation() to authenticated;
grant execute on function public.admin_financial_reconciliation_v2() to authenticated;

commit;
