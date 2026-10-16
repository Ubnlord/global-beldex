begin;

-- Dedicated BDX admin adjustment RPC. The existing admin_adjust_balance and
-- admin_fund_user remain USD-only; this function never changes USD columns.
create or replace function public.admin_adjust_bdx_balance(
  p_user_id uuid,
  p_delta numeric,
  p_reason text,
  p_reference text default null
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_old public.user_profile;
  v_new public.user_profile;
  v_tx public.transaction;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
  v_reference text := nullif(trim(coalesce(p_reference,'')),'');
  v_request_id uuid;
  v_key text;
  v_note text;
  v_type text;
  v_amount numeric;
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then
    raise exception 'Permission denied';
  end if;
  if p_user_id is null then raise exception 'User is required'; end if;
  if p_delta is null or p_delta=0 then raise exception 'Adjustment cannot be zero'; end if;
  if v_reason is null then raise exception 'Reason is required'; end if;
  if v_reference is null then raise exception 'Reference is required for idempotency'; end if;

  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;

  v_type := case when p_delta>0 then 'bonus' else 'withdraw' end;
  v_amount := abs(p_delta);
  v_note := v_reason||' | Ref: '||v_reference;
  v_key := md5(p_user_id::text||':'||v_reference);
  v_request_id := (
    substr(v_key,1,8)||'-'||substr(v_key,9,4)||'-'||substr(v_key,13,4)||'-'||
    substr(v_key,17,4)||'-'||substr(v_key,21,12)
  )::uuid;

  -- Serialize adjustments for this user before checking the idempotency key.
  select * into v_old from public.user_profile where user_id=p_user_id for update;
  if v_old.user_id is null then raise exception 'User profile not found'; end if;

  select * into v_tx from public.transaction
   where user_id=p_user_id and request_id=v_request_id
   limit 1 for update;
  if found then
    if v_tx.type<>v_type or v_tx.amount<>v_amount or coalesce(v_tx.currency,'USD')<>'BDX'
      or coalesce(v_tx.method,'')<>'Admin BDX adjustment' or coalesce(v_tx.note,'')<>v_note
    then
      raise exception 'Reference was already used for a different BDX adjustment';
    end if;
    return v_tx;
  end if;

  if coalesce(v_old.blocked,false) then raise exception 'User account is blocked'; end if;
  if v_old.bdx_balance+p_delta<0 then raise exception 'Adjustment would make BDX balance negative'; end if;

  update public.user_profile
     set bdx_balance=bdx_balance+p_delta,updated_at=now()
   where user_id=p_user_id
   returning * into v_new;

  insert into public.transaction(
    user_id,type,amount,currency,status,approval_status,method,note,
    request_id,approved_by,approval_reason,approved_at,settled_at
  )
  values(
    p_user_id,v_type,v_amount,'BDX','completed','approved','Admin BDX adjustment',
    v_note,v_request_id,v_admin.id,v_reason,now(),now()
  )
  returning * into v_tx;

  insert into public.admin_action_audit(
    admin_id,user_id,action,target_id,old_values,new_values,reason
  )
  values(
    v_admin.id,p_user_id,'bdx_balance_adjusted',v_tx.id,
    jsonb_build_object('bdx_balance',v_old.bdx_balance),
    jsonb_build_object('bdx_balance',v_new.bdx_balance,'delta',p_delta,'currency','BDX','reference',v_reference),
    v_reason
  );
  return v_tx;
end;
$function$;

revoke all on function public.admin_adjust_bdx_balance(uuid,numeric,text,text) from public,anon;
grant execute on function public.admin_adjust_bdx_balance(uuid,numeric,text,text) to authenticated;

-- Investment administration must release/re-lock principal in the investment's
-- recorded currency. Completed/cancelled investments cannot be reactivated:
-- doing so could re-credit principal or accrue an old interval twice.
create or replace function public.admin_manage_investment(
  p_investment_id uuid,
  p_daily_rate numeric default null,
  p_daily_accrual_enabled boolean default null,
  p_status text default null,
  p_reason text default null
)
returns public.user_investment
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_old public.user_investment;
  v_new public.user_investment;
  v_profile public.user_profile;
  v_status text := nullif(lower(trim(coalesce(p_status,''))), '');
  v_reason text := nullif(trim(coalesce(p_reason,'')), '');
  v_currency text;
begin
  if not public.is_admin() or not public.admin_has_permission('manage_users') then
    raise exception 'Permission denied';
  end if;
  if p_investment_id is null then raise exception 'Investment is required'; end if;
  if p_daily_rate is not null and p_daily_rate<0 then raise exception 'Daily rate cannot be negative'; end if;
  if v_status is not null and v_status not in ('active','completed','cancelled') then
    raise exception 'Invalid investment status';
  end if;
  if v_status in ('completed','cancelled') and v_reason is null then
    raise exception 'Reason is required when changing investment status';
  end if;

  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  select * into v_old from public.user_investment where id=p_investment_id for update;
  if v_old.id is null then raise exception 'Investment not found'; end if;
  select * into v_profile from public.user_profile where user_id=v_old.user_id for update;
  if v_profile.user_id is null then raise exception 'User profile not found'; end if;
  v_currency := coalesce(v_old.currency,'USD');

  if v_status='active' and v_old.status in ('completed','cancelled') then
    raise exception 'Completed or cancelled investments cannot be reactivated';
  end if;

  if v_status in ('completed','cancelled') and v_old.status='active' then
    if v_currency='BDX' then
      if v_profile.locked_bdx_balance<v_old.principal then
        raise exception 'Locked BDX balance does not cover investment principal';
      end if;
      update public.user_profile
         set locked_bdx_balance=locked_bdx_balance-v_old.principal,
             bdx_balance=bdx_balance+v_old.principal,
             updated_at=now()
       where user_id=v_old.user_id;
    else
      if v_profile.locked_balance<v_old.principal then
        raise exception 'Locked USD balance does not cover investment principal';
      end if;
      update public.user_profile
         set locked_balance=locked_balance-v_old.principal,
             available_balance=available_balance+v_old.principal,
             updated_at=now()
       where user_id=v_old.user_id;
    end if;

    insert into public.transaction(
      user_id,type,amount,currency,status,approval_status,method,note,
      approved_by,approval_reason,approved_at,settled_at
    )
    values(
      v_old.user_id,'bonus',v_old.principal,v_currency,'completed','approved',
      'Admin investment principal release',
      'Investment principal returned by admin: '||v_reason,
      v_admin.id,v_reason,now(),now()
    );
  end if;

  update public.user_investment
     set daily_rate=coalesce(p_daily_rate,daily_rate),
         daily_accrual_enabled=coalesce(p_daily_accrual_enabled,daily_accrual_enabled),
         status=coalesce(v_status,status),
         completed_at=case
           when v_status in ('completed','cancelled') then coalesce(completed_at,now())
           when v_status='active' then null
           else completed_at
         end,
         updated_at=now()
   where id=p_investment_id
   returning * into v_new;

  insert into public.admin_action_audit(
    admin_id,user_id,action,target_id,old_values,new_values,reason
  )
  values(
    v_admin.id,v_old.user_id,'investment_managed',p_investment_id,
    jsonb_build_object('daily_rate',v_old.daily_rate,'daily_accrual_enabled',v_old.daily_accrual_enabled,
      'status',v_old.status,'principal',v_old.principal,'currency',v_currency),
    jsonb_build_object('daily_rate',v_new.daily_rate,'daily_accrual_enabled',v_new.daily_accrual_enabled,
      'status',v_new.status,'principal',v_new.principal,'currency',v_currency),
    coalesce(v_reason,'Administrator updated investment')
  );
  return v_new;
end;
$function$;

revoke all on function public.admin_manage_investment(uuid,numeric,boolean,text,text) from public,anon;
grant execute on function public.admin_manage_investment(uuid,numeric,boolean,text,text) to authenticated;

-- Keep the historical four-argument RPC signature as a safe compatibility
-- wrapper. It delegates to the currency-aware implementation above and contains
-- no independent balance mutation logic.
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
begin
  return public.admin_manage_investment(
    p_investment_id,p_daily_rate,null::boolean,p_status,p_reason
  );
end;
$function$;

revoke all on function public.admin_manage_investment(uuid,numeric,text,text) from public,anon;
grant execute on function public.admin_manage_investment(uuid,numeric,text,text) to authenticated,service_role;

-- Read-only reconciliation v3 reports BDX referrals separately and excludes
-- administrative balance adjustments from user withdrawal totals.
create or replace function public.admin_financial_reconciliation_v3()
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
  referral_earnings_bdx numeric,
  recorded_referrals_bdx numeric,
  referral_bdx_delta numeric,
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
  if not public.is_admin() or not public.admin_has_permission('view_transactions') then
    raise exception 'Permission denied';
  end if;
  return query
  with d_usd as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='deposit' and t.status='completed' and coalesce(t.currency,'USD')='USD' group by t.user_id
  ), w_usd as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='withdraw' and t.status='completed' and coalesce(t.currency,'USD')='USD'
      and coalesce(t.method,'')<>'Admin adjustment' group by t.user_id
  ), d_bdx as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='deposit' and t.status='completed' and t.currency='BDX' group by t.user_id
  ), w_bdx as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='withdraw' and t.status='completed' and t.currency='BDX'
      and coalesce(t.method,'')<>'Admin BDX adjustment' group by t.user_id
  ), r_usd as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='referral' and t.status='completed' and coalesce(t.currency,'USD')='USD' group by t.user_id
  ), r_bdx as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='referral' and t.status='completed' and t.currency='BDX' group by t.user_id
  ), ip_usd as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='bonus' and t.status='completed' and t.note='Server-side investment profit'
      and coalesce(t.currency,'USD')='USD' group by t.user_id
  ), ip_bdx as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='bonus' and t.status='completed' and t.note='Server-side investment profit'
      and t.currency='BDX' group by t.user_id
  ), inv as (
    select ui.user_id,
      coalesce(sum(ui.principal) filter(where ui.status='active' and coalesce(ui.currency,'USD')='USD'),0) active_usd,
      coalesce(sum(ui.credited_profit) filter(where coalesce(ui.currency,'USD')='USD'),0) profit_usd,
      coalesce(sum(ui.principal) filter(where ui.status='active' and ui.currency='BDX'),0) active_bdx,
      coalesce(sum(ui.credited_profit) filter(where ui.currency='BDX'),0) profit_bdx
    from public.user_investment ui group by ui.user_id
  )
  select
    p.user_id,p.available_balance,p.locked_balance,
    coalesce(inv.active_usd,0),p.locked_balance-coalesce(inv.active_usd,0),
    p.total_deposits,coalesce(d_usd.amount,0),p.total_deposits-coalesce(d_usd.amount,0),
    p.total_withdrawals,coalesce(w_usd.amount,0),p.total_withdrawals-coalesce(w_usd.amount,0),
    p.referral_earnings,coalesce(r_usd.amount,0),p.referral_earnings-coalesce(r_usd.amount,0),
    coalesce(inv.profit_usd,0),coalesce(ip_usd.amount,0),coalesce(inv.profit_usd,0)-coalesce(ip_usd.amount,0),
    p.bdx_balance,p.locked_bdx_balance,coalesce(inv.active_bdx,0),p.locked_bdx_balance-coalesce(inv.active_bdx,0),
    p.total_deposits_bdx,coalesce(d_bdx.amount,0),p.total_deposits_bdx-coalesce(d_bdx.amount,0),
    p.total_withdrawals_bdx,coalesce(w_bdx.amount,0),p.total_withdrawals_bdx-coalesce(w_bdx.amount,0),
    p.referral_earnings_bdx,coalesce(r_bdx.amount,0),p.referral_earnings_bdx-coalesce(r_bdx.amount,0),
    coalesce(inv.profit_bdx,0),coalesce(ip_bdx.amount,0),coalesce(inv.profit_bdx,0)-coalesce(ip_bdx.amount,0),
    p.available_balance<0 or p.locked_balance<0 or p.bdx_balance<0 or p.locked_bdx_balance<0
  from public.user_profile p
  left join d_usd on d_usd.user_id=p.user_id
  left join w_usd on w_usd.user_id=p.user_id
  left join d_bdx on d_bdx.user_id=p.user_id
  left join w_bdx on w_bdx.user_id=p.user_id
  left join r_usd on r_usd.user_id=p.user_id
  left join r_bdx on r_bdx.user_id=p.user_id
  left join ip_usd on ip_usd.user_id=p.user_id
  left join ip_bdx on ip_bdx.user_id=p.user_id
  left join inv on inv.user_id=p.user_id
  order by p.created_at;
end;
$function$;

revoke all on function public.admin_financial_reconciliation_v3() from public,anon;
grant execute on function public.admin_financial_reconciliation_v3() to authenticated;

-- Legacy admin functions can credit or adjust USD balances/bonuses and are no
-- longer exposed. The console must use the reference-idempotent BDX RPC above.
drop function if exists public.admin_fund_user(uuid,numeric,text,text);
drop function if exists public.admin_fund_user(uuid,numeric,text);
drop function if exists public.admin_adjust_balance(uuid,numeric,text,text);
drop function if exists public.admin_adjust_balance(uuid,numeric,text);

commit;
