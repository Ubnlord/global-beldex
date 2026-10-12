-- Production-shape compatibility fixture for PR #48.
-- Run ONLY against the disposable local Supabase database after `supabase db reset`.
-- It contains schema/function metadata patterns only; never connects to production or imports financial rows.
-- Simulate observed production drift: missing BDX referral counter and legacy RPC overloads.
begin;

-- The current repository schema has the new referral column; production did not.
-- Replace the referral routine first with the observed legacy USD-only shape, then remove the column.
create or replace function public.credit_referral_for_deposit(p_transaction_id uuid)
returns numeric
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $fixture$
declare
  v_tx public.transaction;
  v_ref uuid;
  v_cut numeric;
begin
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.type <> 'deposit' or v_tx.status <> 'completed' then return 0; end if;
  select referred_by_user_id into v_ref from public.user_profile where user_id=v_tx.user_id;
  if v_ref is null then return 0; end if;
  if exists(select 1 from public.transaction where method='Referral deposit '||v_tx.id::text) then return 0; end if;
  v_cut := round(v_tx.amount*0.10,18);
  if v_cut <= 0 then return 0; end if;
  update public.user_profile set available_balance=available_balance+v_cut,
    referral_earnings=referral_earnings+v_cut,updated_at=now() where user_id=v_ref;
  insert into public.transaction(user_id,type,amount,status,approval_status,method,note)
  values(v_ref,'referral',v_cut,'completed','approved','Referral deposit '||v_tx.id::text,'10% referral commission');
  return v_cut;
end;
$fixture$;
revoke all on function public.credit_referral_for_deposit(uuid) from public, anon;
grant execute on function public.credit_referral_for_deposit(uuid) to service_role;

alter table public.user_profile drop column if exists referral_earnings_bdx;

-- Observed production's three-argument legacy funding overload.
drop function if exists public.admin_fund_user(uuid,numeric,text);
create function public.admin_fund_user(p_user_id uuid,p_amount numeric,p_reason text)
returns public.user_profile
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $fixture$
declare v_profile public.user_profile;
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then
    raise exception 'Permission denied';
  end if;
  if p_user_id is null or p_amount is null or p_amount <= 0 or nullif(trim(coalesce(p_reason,'')),'') is null then
    raise exception 'Invalid funding request';
  end if;
  update public.user_profile set available_balance=available_balance+p_amount,updated_at=now()
    where user_id=p_user_id returning * into v_profile;
  if v_profile.user_id is null then raise exception 'User profile not found'; end if;
  return v_profile;
end;
$fixture$;
revoke all on function public.admin_fund_user(uuid,numeric,text) from public, anon;
grant execute on function public.admin_fund_user(uuid,numeric,text) to authenticated, service_role;

-- Simulate the previously deployed four-argument overload with a defaulted reference.
drop function if exists public.admin_fund_user(uuid,numeric,text,text);
create function public.admin_fund_user(p_user_id uuid,p_amount numeric,p_reason text,p_reference text default null)
returns public.user_profile
language sql security definer
set search_path = pg_catalog, public, pg_temp
as $fixture$
  update public.user_profile set available_balance=available_balance+p_amount,updated_at=now()
  where user_id=p_user_id returning *;
$fixture$;
revoke all on function public.admin_fund_user(uuid,numeric,text,text) from public, anon;
grant execute on function public.admin_fund_user(uuid,numeric,text,text) to authenticated, service_role;

-- Simulate the legacy five-argument transaction RPC overload. The migration must
-- retire this signature so calls cannot resolve to stale USD-wallet logic.
drop function if exists public.create_financial_transaction(text,numeric,text,text,uuid);
create function public.create_financial_transaction(
  p_type text,p_amount numeric,p_method text default null,p_note text default null,p_request_id uuid default null
)
returns public.transaction
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $fixture$
declare v_uid uuid := auth.uid(); v_tx public.transaction;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  insert into public.transaction(user_id,type,amount,status,approval_status,method,note,request_id)
  values(v_uid,p_type,p_amount,'pending','awaiting',p_method,p_note,p_request_id)
  returning * into v_tx;
  return v_tx;
end;
$fixture$;
revoke all on function public.create_financial_transaction(text,numeric,text,text,uuid) from public, anon;
grant execute on function public.create_financial_transaction(text,numeric,text,text,uuid) to authenticated, service_role;

-- A historical four-argument adjustment overload existed in earlier schema variants.
drop function if exists public.admin_adjust_balance(uuid,numeric,text,text);
create function public.admin_adjust_balance(p_user_id uuid,p_delta numeric,p_reason text,p_currency text)
returns public.user_profile
language sql security definer
set search_path = pg_catalog, public, pg_temp
as $fixture$
  update public.user_profile set available_balance=available_balance+p_delta,updated_at=now()
  where user_id=p_user_id returning *;
$fixture$;
revoke all on function public.admin_adjust_balance(uuid,numeric,text,text) from public, anon;
grant execute on function public.admin_adjust_balance(uuid,numeric,text,text) to authenticated, service_role;

commit;
