begin;

-- Currency-aware deposit/withdrawal requests. Legacy calls default to USD;
-- the updated client sends the explicit denomination. Withdrawal funds are
-- reserved at request time and released on rejection in the same wallet.
create or replace function public.create_financial_transaction(
  p_type text,
  p_amount numeric,
  p_method text default null,
  p_note text default null,
  p_request_id uuid default null,
  p_currency text
)
returns public.transaction
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
  v_tx public.transaction;
  v_currency text := upper(coalesce(p_currency,'USD'));
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  if p_type not in ('deposit','withdraw') then raise exception 'Invalid transaction type'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be greater than zero'; end if;
  if v_currency not in ('BDX','USD') then raise exception 'Unsupported currency'; end if;
  perform public.assert_user_can_transact(v_uid);

  if p_request_id is not null then
    select * into v_tx from public.transaction where user_id=v_uid and request_id=p_request_id limit 1;
    if found then
      if v_tx.type <> p_type or v_tx.amount <> p_amount or coalesce(v_tx.currency,'USD') <> v_currency then
        raise exception 'Request ID was already used for a different transaction';
      end if;
      return v_tx;
    end if;
  end if;

  if p_type='withdraw' then
    if v_currency='BDX' then
      update public.user_profile set bdx_balance=bdx_balance-p_amount,updated_at=now()
      where user_id=v_uid and bdx_balance>=p_amount;
    else
      update public.user_profile set available_balance=available_balance-p_amount,updated_at=now()
      where user_id=v_uid and available_balance>=p_amount;
    end if;
    if not found then raise exception 'Insufficient % balance',v_currency; end if;
  end if;

  insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note,request_id)
  values(v_uid,p_type,p_amount,v_currency,'pending','awaiting',p_method,p_note,p_request_id)
  returning * into v_tx;
  return v_tx;
exception when unique_violation then
  if p_request_id is not null then
    select * into v_tx from public.transaction where user_id=v_uid and request_id=p_request_id limit 1;
    if found and v_tx.type=p_type and v_tx.amount=p_amount and coalesce(v_tx.currency,'USD')=v_currency then return v_tx; end if;
  end if;
  raise;
end;
$function$;

revoke all on function public.create_financial_transaction(text,numeric,text,text,uuid,text) from public,anon;
grant execute on function public.create_financial_transaction(text,numeric,text,text,uuid,text) to authenticated;

create or replace function public.admin_reject_transaction(p_transaction_id uuid,p_reason text)
returns public.transaction
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare v_admin public.admin_user; v_tx public.transaction; v_currency text;
begin
  if not public.is_admin() or not public.admin_has_permission('reject_transactions') then raise exception 'Permission denied'; end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'Rejection reason is required'; end if;
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.approval_status<>'awaiting' then raise exception 'Transaction is not awaiting approval'; end if;

  v_currency := coalesce(v_tx.currency,'USD');
  if v_tx.type='withdraw' then
    if v_currency='BDX' then
      update public.user_profile set bdx_balance=bdx_balance+v_tx.amount,updated_at=now() where user_id=v_tx.user_id;
    else
      update public.user_profile set available_balance=available_balance+v_tx.amount,updated_at=now() where user_id=v_tx.user_id;
    end if;
  end if;

  update public.transaction set approval_status='rejected',status='failed',approved_by=v_admin.id,
    approval_reason=p_reason,approved_at=now(),updated_at=now() where id=p_transaction_id returning * into v_tx;
  insert into public.transaction_audit(transaction_id,admin_id,action,old_values,new_values,reason)
  values(v_tx.id,v_admin.id,'rejected',jsonb_build_object('approval_status','awaiting'),
    jsonb_build_object('approval_status',v_tx.approval_status,'status',v_tx.status,'currency',v_currency),p_reason);
  return v_tx;
end;
$function$;

create or replace function public.admin_settle_transaction(p_transaction_id uuid,p_reason text default null)
returns public.transaction
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare v_admin public.admin_user; v_tx public.transaction; v_currency text;
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then raise exception 'Permission denied'; end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.type not in ('deposit','withdraw') then raise exception 'Only deposit and withdrawal can be settled'; end if;
  if v_tx.status='completed' then raise exception 'Transaction already completed'; end if;
  if v_tx.approval_status<>'approved' then raise exception 'Transaction must be approved first'; end if;
  v_currency := coalesce(v_tx.currency,'USD');

  if v_tx.type='deposit' then
    if v_currency='BDX' then
      update public.user_profile set bdx_balance=bdx_balance+v_tx.amount,
        total_deposits=total_deposits+v_tx.amount,updated_at=now() where user_id=v_tx.user_id;
    else
      update public.user_profile set available_balance=available_balance+v_tx.amount,
        total_deposits=total_deposits+v_tx.amount,updated_at=now() where user_id=v_tx.user_id;
    end if;
  else
    update public.user_profile set total_withdrawals=total_withdrawals+v_tx.amount,updated_at=now() where user_id=v_tx.user_id;
  end if;

  update public.transaction set status='completed',settled_at=now(),updated_at=now()
  where id=p_transaction_id returning * into v_tx;
  insert into public.transaction_audit(transaction_id,admin_id,action,old_values,new_values,reason)
  values(v_tx.id,v_admin.id,'settled',jsonb_build_object('status','pending'),
    jsonb_build_object('status',v_tx.status,'currency',v_currency),p_reason);
  return v_tx;
end;
$function$;

revoke all on function public.admin_reject_transaction(uuid,text) from public,anon;
revoke all on function public.admin_settle_transaction(uuid,text) from public,anon;
grant execute on function public.admin_reject_transaction(uuid,text) to authenticated;
grant execute on function public.admin_settle_transaction(uuid,text) to authenticated;

-- Separate USD and BDX ledger totals. Existing rows remain USD by default.
create or replace function public.admin_financial_reconciliation()
returns table(
  user_id uuid, available_balance numeric, locked_balance numeric, expected_locked_balance numeric,
  locked_delta numeric, total_deposits numeric, recorded_deposits numeric, deposits_delta numeric,
  total_withdrawals numeric, recorded_withdrawals numeric, withdrawals_delta numeric,
  referral_earnings numeric, recorded_referrals numeric, referral_delta numeric,
  credited_investment_profit numeric, recorded_investment_profit numeric, investment_profit_delta numeric,
  negative_balance boolean
)
language plpgsql security definer set search_path = ''
as $function$
begin
  if not public.is_admin() then raise exception 'Permission denied'; end if;
  return query
  with d as (select t.user_id,sum(t.amount) amount from public.transaction t where t.type='deposit' and t.status='completed' and coalesce(t.currency,'USD')='USD' group by t.user_id),
  w as (select t.user_id,sum(t.amount) amount from public.transaction t where t.type='withdraw' and t.status='completed' and coalesce(t.currency,'USD')='USD' group by t.user_id),
  r as (select t.user_id,sum(t.amount) amount from public.transaction t where t.type='referral' and t.status='completed' group by t.user_id),
  ip as (select t.user_id,sum(t.amount) amount from public.transaction t where t.type='bonus' and t.status='completed' and t.note='Server-side investment profit' and coalesce(t.currency,'USD')='USD' group by t.user_id),
  inv as (select ui.user_id,
    coalesce(sum(ui.principal) filter(where ui.status='active' and coalesce(ui.currency,'USD')='USD'),0) active_principal,
    coalesce(sum(ui.credited_profit) filter(where coalesce(ui.currency,'USD')='USD'),0) profit
    from public.user_investment ui group by ui.user_id)
  select p.user_id,p.available_balance,p.locked_balance,coalesce(inv.active_principal,0),
    p.locked_balance-coalesce(inv.active_principal,0),p.total_deposits,coalesce(d.amount,0),p.total_deposits-coalesce(d.amount,0),
    p.total_withdrawals,coalesce(w.amount,0),p.total_withdrawals-coalesce(w.amount,0),
    p.referral_earnings,coalesce(r.amount,0),p.referral_earnings-coalesce(r.amount,0),
    coalesce(inv.profit,0),coalesce(ip.amount,0),coalesce(inv.profit,0)-coalesce(ip.amount,0),
    p.available_balance<0 or p.locked_balance<0 or p.bdx_balance<0 or p.locked_bdx_balance<0
  from public.user_profile p left join d on d.user_id=p.user_id left join w on w.user_id=p.user_id
  left join r on r.user_id=p.user_id left join ip on ip.user_id=p.user_id left join inv on inv.user_id=p.user_id
  order by p.created_at;
end;
$function$;

commit;
