begin;

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
      v_total := v_total + v_profit;

      update public.user_profile
      set available_balance = available_balance + v_profit + v_principal_return,
          locked_balance = case when v_done then greatest(0, locked_balance - v_inv.principal) else locked_balance end,
          updated_at = now()
      where user_id = v_uid;

      update public.user_investment
      set credited_profit = credited_profit + v_profit,
          last_accrual_at = least(v_inv.started_at + make_interval(days => v_inv.duration_days), v_now),
          status = case when v_done then 'completed' else 'active' end,
          completed_at = case when v_done then v_now else completed_at end,
          updated_at = now()
      where id = v_inv.id;

      insert into public.transaction(user_id,type,amount,status,approval_status,method,note)
      values(v_uid,'bonus',v_profit,'completed','approved',
        case when v_done then 'Plan maturity' else 'Daily interest' end,
        'Server-side investment profit');

      if v_done then
        insert into public.transaction(user_id,type,amount,status,approval_status,method,note)
        values(v_uid,'bonus',v_inv.principal,'completed','approved',
          'Plan maturity','Investment principal returned');
      end if;
    end if;
  end loop;
  return v_total;
end;
$function$;

create or replace function public.run_daily_investment_accrual()
returns numeric
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user record;
  v_total numeric := 0;
  v_user_total numeric;
begin
  if current_user <> 'postgres' then raise exception 'Cron execution only'; end if;

  for v_user in
    select distinct ui.user_id
    from public.user_investment ui
    join public.user_profile up on up.user_id = ui.user_id
    where ui.status = 'active' and ui.daily_accrual_enabled = true and up.blocked = false
  loop
    begin
      v_user_total := public.accrue_user_investments(v_user.user_id);
      v_total := v_total + coalesce(v_user_total, 0);
    exception when others then
      raise warning 'Daily accrual failed for user %: %', v_user.user_id, sqlerrm;
    end;
  end loop;
  return v_total;
end;
$function$;

revoke all on function public.run_daily_investment_accrual() from public, anon, authenticated, service_role;

create extension if not exists pg_cron;

select cron.unschedule(jobid)
from cron.job
where jobname = 'global-beldex-daily-investment-accrual';

select cron.schedule(
  'global-beldex-daily-investment-accrual',
  '0 0 * * *',
  $$select public.run_daily_investment_accrual();$$
);

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
    select t.user_id, coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='deposit' and t.status='completed' group by t.user_id
  ),
  withdrawal_totals as (
    select t.user_id, coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='withdraw' and t.status='completed' group by t.user_id
  ),
  referral_totals as (
    select t.user_id, coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='referral' and t.status='completed' group by t.user_id
  ),
  investment_profit_totals as (
    select t.user_id, coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='bonus' and t.status='completed' and t.note='Server-side investment profit'
    group by t.user_id
  ),
  investment_totals as (
    select ui.user_id,
      coalesce(sum(ui.principal) filter(where ui.status='active'),0) active_principal,
      coalesce(sum(ui.credited_profit),0) credited_profit
    from public.user_investment ui group by ui.user_id
  )
  select p.user_id,p.available_balance,p.locked_balance,
    coalesce(i.active_principal,0),p.locked_balance-coalesce(i.active_principal,0),
    p.total_deposits,coalesce(d.amount,0),p.total_deposits-coalesce(d.amount,0),
    p.total_withdrawals,coalesce(w.amount,0),p.total_withdrawals-coalesce(w.amount,0),
    p.referral_earnings,coalesce(r.amount,0),p.referral_earnings-coalesce(r.amount,0),
    coalesce(i.credited_profit,0),coalesce(ip.amount,0),
    coalesce(i.credited_profit,0)-coalesce(ip.amount,0),
    p.available_balance<0 or p.locked_balance<0 or p.bdx_balance<0
  from public.user_profile p
  left join deposit_totals d on d.user_id=p.user_id
  left join withdrawal_totals w on w.user_id=p.user_id
  left join referral_totals r on r.user_id=p.user_id
  left join investment_profit_totals ip on ip.user_id=p.user_id
  left join investment_totals i on i.user_id=p.user_id
  order by p.created_at;
end;
$function$;

revoke all on function public.admin_financial_reconciliation() from public, anon;
grant execute on function public.admin_financial_reconciliation() to authenticated;

commit;