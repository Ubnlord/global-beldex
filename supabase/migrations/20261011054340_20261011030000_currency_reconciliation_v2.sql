begin;

-- Keep the legacy profile totals USD-denominated for the existing admin/client
-- interface. BDX totals are stored separately; never add unlike currencies.
alter table public.user_profile
  add column if not exists total_deposits_bdx numeric(38,18) not null default 0,
  add column if not exists total_withdrawals_bdx numeric(38,18) not null default 0;

comment on column public.user_profile.total_deposits is
  'Legacy USD-denominated completed deposits total; never combine with BDX.';
comment on column public.user_profile.total_withdrawals is
  'Legacy USD-denominated completed withdrawals total; never combine with BDX.';
comment on column public.user_profile.total_deposits_bdx is
  'Completed BDX deposits total, denominated in BDX.';
comment on column public.user_profile.total_withdrawals_bdx is
  'Completed BDX withdrawals total, denominated in BDX.';

-- Keep old total_deposits/total_withdrawals as USD for compatibility. New BDX
-- settlements update only the BDX-specific columns.
create or replace function public.admin_settle_transaction(p_transaction_id uuid,p_reason text default null)
returns public.transaction
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_tx public.transaction;
  v_currency text;
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then
    raise exception 'Permission denied';
  end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;

  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.type not in ('deposit','withdraw') then raise exception 'Only deposit and withdrawal can be settled'; end if;
  if v_tx.status='completed' then raise exception 'Transaction already completed'; end if;
  if v_tx.approval_status<>'approved' then raise exception 'Transaction must be approved first'; end if;

  v_currency := coalesce(v_tx.currency,'USD');
  if v_currency not in ('USD','BDX') then raise exception 'Unsupported transaction currency'; end if;

  if v_tx.type='deposit' then
    if v_currency='BDX' then
      update public.user_profile
      set bdx_balance=bdx_balance+v_tx.amount,
          total_deposits_bdx=total_deposits_bdx+v_tx.amount,
          updated_at=now()
      where user_id=v_tx.user_id;
    else
      update public.user_profile
      set available_balance=available_balance+v_tx.amount,
          total_deposits=total_deposits+v_tx.amount,
          updated_at=now()
      where user_id=v_tx.user_id;
    end if;
  else
    if v_currency='BDX' then
      update public.user_profile
      set total_withdrawals_bdx=total_withdrawals_bdx+v_tx.amount,updated_at=now()
      where user_id=v_tx.user_id;
    else
      update public.user_profile
      set total_withdrawals=total_withdrawals+v_tx.amount,updated_at=now()
      where user_id=v_tx.user_id;
    end if;
  end if;

  update public.transaction set status='completed',settled_at=now(),updated_at=now()
  where id=p_transaction_id returning * into v_tx;
  insert into public.transaction_audit(transaction_id,admin_id,action,old_values,new_values,reason)
  values(v_tx.id,v_admin.id,'settled',jsonb_build_object('status','pending'),
    jsonb_build_object('status',v_tx.status,'currency',v_currency),p_reason);
  return v_tx;
end;
$function$;

revoke all on function public.admin_settle_transaction(uuid,text) from public,anon;
grant execute on function public.admin_settle_transaction(uuid,text) to authenticated;

-- Extended reconciliation RPC. The existing RPC and its result columns remain
-- intact for older clients; the current admin console can consume this richer
-- result to show separate USD and BDX deltas.
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
language plpgsql security definer
set search_path = ''
as $function$
begin
  if not public.is_admin() then raise exception 'Permission denied'; end if;
  return query
  with d_usd as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='deposit' and t.status='completed' and coalesce(t.currency,'USD')='USD' group by t.user_id
  ), w_usd as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='withdraw' and t.status='completed' and coalesce(t.currency,'USD')='USD' group by t.user_id
  ), d_bdx as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='deposit' and t.status='completed' and t.currency='BDX' group by t.user_id
  ), w_bdx as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='withdraw' and t.status='completed' and t.currency='BDX' group by t.user_id
  ), r as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='referral' and t.status='completed' and coalesce(t.currency,'USD')='USD' group by t.user_id
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
  select p.user_id,p.available_balance,p.locked_balance,
    coalesce(inv.active_usd,0),p.locked_balance-coalesce(inv.active_usd,0),
    p.total_deposits,coalesce(d_usd.amount,0),p.total_deposits-coalesce(d_usd.amount,0),
    p.total_withdrawals,coalesce(w_usd.amount,0),p.total_withdrawals-coalesce(w_usd.amount,0),
    p.referral_earnings,coalesce(r.amount,0),p.referral_earnings-coalesce(r.amount,0),
    coalesce(inv.profit_usd,0),coalesce(ip_usd.amount,0),coalesce(inv.profit_usd,0)-coalesce(ip_usd.amount,0),
    p.bdx_balance,p.locked_bdx_balance,coalesce(inv.active_bdx,0),p.locked_bdx_balance-coalesce(inv.active_bdx,0),
    p.total_deposits_bdx,coalesce(d_bdx.amount,0),p.total_deposits_bdx-coalesce(d_bdx.amount,0),
    p.total_withdrawals_bdx,coalesce(w_bdx.amount,0),p.total_withdrawals_bdx-coalesce(w_bdx.amount,0),
    coalesce(inv.profit_bdx,0),coalesce(ip_bdx.amount,0),coalesce(inv.profit_bdx,0)-coalesce(ip_bdx.amount,0),
    p.available_balance<0 or p.locked_balance<0 or p.bdx_balance<0 or p.locked_bdx_balance<0
  from public.user_profile p
  left join d_usd on d_usd.user_id=p.user_id left join w_usd on w_usd.user_id=p.user_id
  left join d_bdx on d_bdx.user_id=p.user_id left join w_bdx on w_bdx.user_id=p.user_id
  left join r on r.user_id=p.user_id left join ip_usd on ip_usd.user_id=p.user_id
  left join ip_bdx on ip_bdx.user_id=p.user_id left join inv on inv.user_id=p.user_id
  order by p.created_at;
end;
$function$;

revoke all on function public.admin_financial_reconciliation_v2() from public,anon;
grant execute on function public.admin_financial_reconciliation_v2() to authenticated;

commit;
