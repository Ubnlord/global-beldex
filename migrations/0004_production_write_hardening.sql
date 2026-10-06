begin;

-- These RPCs are defined here so this hardening migration is self-contained
-- when the schema is rebuilt from the repository.
create or replace function public.admin_approve_transaction(
  p_transaction_id uuid,
  p_reason text default null
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_tx public.transaction;
begin
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;

  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.approval_status<>'awaiting' then raise exception 'Transaction is not awaiting approval'; end if;

  update public.transaction
  set approval_status='approved',
      status=case when type in ('deposit','withdraw') then 'pending' else 'approved' end,
      approved_by=v_admin.id,
      approval_reason=p_reason,
      approved_at=now(),
      updated_at=now()
  where id=p_transaction_id
  returning * into v_tx;

  insert into public.transaction_audit(
    transaction_id,admin_id,action,old_values,new_values,reason
  )
  values(
    v_tx.id,v_admin.id,'approved',
    jsonb_build_object('approval_status','awaiting'),
    jsonb_build_object('approval_status',v_tx.approval_status,'status',v_tx.status),
    p_reason
  );
  return v_tx;
end;
$function$;

create or replace function public.admin_reject_transaction(
  p_transaction_id uuid,
  p_reason text
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_tx public.transaction;
begin
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'Rejection reason is required'; end if;

  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.approval_status<>'awaiting' then raise exception 'Transaction is not awaiting approval'; end if;

  if v_tx.type='withdraw' then
    update public.user_profile
    set available_balance=available_balance+v_tx.amount,updated_at=now()
    where user_id=v_tx.user_id;
  end if;

  update public.transaction
  set approval_status='rejected',
      status='failed',
      approved_by=v_admin.id,
      approval_reason=p_reason,
      approved_at=now(),
      updated_at=now()
  where id=p_transaction_id
  returning * into v_tx;

  insert into public.transaction_audit(
    transaction_id,admin_id,action,old_values,new_values,reason
  )
  values(
    v_tx.id,v_admin.id,'rejected',
    jsonb_build_object('approval_status','awaiting'),
    jsonb_build_object('approval_status',v_tx.approval_status,'status',v_tx.status),
    p_reason
  );
  return v_tx;
end;
$function$;

-- Production hardening: keep all financial/profile mutations behind controlled RPCs.
-- Direct Data API writes are intentionally removed from client roles.

begin;

-- Client roles may read only. All writes below happen through RPCs.
revoke all on table public.user_profile from anon, authenticated;
revoke all on table public.admin_user from anon, authenticated;
revoke all on table public.transaction from anon, authenticated;
revoke all on table public.transaction_audit from anon, authenticated;
revoke all on table public.investment_plan_catalog from anon, authenticated;
revoke all on table public.user_investment from anon, authenticated;

grant select on table public.user_profile to authenticated;
grant select on table public.admin_user to authenticated;
grant select on table public.transaction to authenticated;
grant select on table public.transaction_audit to authenticated;
grant select on table public.investment_plan_catalog to authenticated;
grant select on table public.user_investment to authenticated;

-- Every write-capable application function runs with tightly controlled owner
-- privileges. The search path is pinned to trusted schemas.
alter function public.ensure_user_profile(text,text,text,text,text)
  security definer set search_path = pg_catalog, public, pg_temp;

alter function public.update_user_profile(text,text,text,text,text)
  security definer set search_path = pg_catalog, public, pg_temp;

alter function public.create_financial_transaction(text,numeric,text,text)
  security definer set search_path = pg_catalog, public, pg_temp;

alter function public.buy_investment_plan(text,numeric)
  security definer set search_path = pg_catalog, public, pg_temp;

alter function public.accrue_user_investments(uuid)
  security definer set search_path = pg_catalog, public, pg_temp;

alter function public.swap_assets(text,text,numeric,numeric)
  security definer set search_path = pg_catalog, public, pg_temp;

alter function public.admin_approve_transaction(uuid,text)
  security definer set search_path = pg_catalog, public, pg_temp;

alter function public.admin_reject_transaction(uuid,text)
  security definer set search_path = pg_catalog, public, pg_temp;

alter function public.admin_settle_transaction(uuid,text)
  security definer set search_path = pg_catalog, public, pg_temp;

alter function public.credit_referral_for_deposit(uuid)
  security definer set search_path = pg_catalog, public, pg_temp;

-- A browser client may request only a deposit or withdrawal transaction.
-- Plan/swap/profit/referral rows are created only by their dedicated RPCs.
create or replace function public.create_financial_transaction(
  p_type text,
  p_amount numeric,
  p_method text default null,
  p_note text default null
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_tx public.transaction;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  if p_type not in ('deposit','withdraw') then
    raise exception 'Invalid transaction type';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;

  if p_type = 'withdraw' then
    update public.user_profile
      set available_balance = available_balance - p_amount, updated_at = now()
      where user_id = v_uid and available_balance >= p_amount;
    if not found then raise exception 'Insufficient balance'; end if;
  end if;

  insert into public.transaction(user_id,type,amount,status,approval_status,method,note)
  values (v_uid,p_type,p_amount,'pending','awaiting',p_method,p_note)
  returning * into v_tx;

  return v_tx;
end;
$function$;

-- Re-establish only the RPC permissions the browser needs.
revoke all on function public.ensure_user_profile(text,text,text,text,text) from public, anon;
revoke all on function public.update_user_profile(text,text,text,text,text) from public, anon;
revoke all on function public.create_financial_transaction(text,numeric,text,text) from public, anon;
revoke all on function public.buy_investment_plan(text,numeric) from public, anon;
revoke all on function public.accrue_user_investments(uuid) from public, anon;
revoke all on function public.swap_assets(text,text,numeric,numeric) from public, anon;
revoke all on function public.admin_approve_transaction(uuid,text) from public, anon;
revoke all on function public.admin_reject_transaction(uuid,text) from public, anon;
revoke all on function public.admin_settle_transaction(uuid,text) from public, anon;
revoke all on function public.credit_referral_for_deposit(uuid) from public, anon, authenticated;

grant execute on function public.ensure_user_profile(text,text,text,text,text) to authenticated;
grant execute on function public.update_user_profile(text,text,text,text,text) to authenticated;
grant execute on function public.create_financial_transaction(text,numeric,text,text) to authenticated;
grant execute on function public.buy_investment_plan(text,numeric) to authenticated;
grant execute on function public.accrue_user_investments(uuid) to authenticated;
grant execute on function public.swap_assets(text,text,numeric,numeric) to authenticated;
grant execute on function public.admin_approve_transaction(uuid,text) to authenticated;
grant execute on function public.admin_reject_transaction(uuid,text) to authenticated;
grant execute on function public.admin_settle_transaction(uuid,text) to authenticated;

commit;