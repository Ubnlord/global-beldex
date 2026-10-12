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
revoke all on function public.credit_referral_for_deposit(uuid) from public, anon, authenticated, service_role;
grant execute on function public.credit_referral_for_deposit(uuid) to service_role;

alter table public.user_profile drop column if exists referral_earnings_bdx;

-- Match the observed production three-argument legacy funding overload exactly.
-- Production does not currently have the four-argument overload; the migration
-- adds it only after retiring the old entry point.
drop function if exists public.admin_fund_user(uuid,numeric,text);
drop function if exists public.admin_fund_user(uuid,numeric,text,text);
create function public.admin_fund_user(p_user_id uuid, p_amount numeric, p_reason text)
returns public.user_profile
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $fixture$
declare
  v_profile public.user_profile;
  v_admin_id uuid;
  v_before numeric;
  v_reason text := nullif(btrim(coalesce(p_reason,'')), '');
begin
  select id into v_admin_id
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
$fixture$;
revoke all on function public.admin_fund_user(uuid,numeric,text) from public, anon;
grant execute on function public.admin_fund_user(uuid,numeric,text) to authenticated, postgres, service_role;

-- Preserve the observed legacy five-argument transaction RPC body and grants.
-- The six-argument currency-aware overload remains present, as in production.
drop function if exists public.create_financial_transaction(text,numeric,text,text,uuid);
create function public.create_financial_transaction(
  p_type text, p_amount numeric, p_method text default null,
  p_note text default null, p_request_id uuid default null
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $fixture$
declare
  v_tx public.transaction;
  v_uid uuid := auth.uid();
  v_address text := btrim(coalesce(p_note, ''));
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;

  if p_type not in ('deposit','withdraw') then
    raise exception 'Invalid transaction type';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;

  if p_type = 'withdraw' then
    if p_method = 'Beldex' then
      if p_amount < 293.984 then
        raise exception 'Minimum Beldex withdrawal is 4000 BDX (293.984 USD)';
      end if;
    elsif p_amount < 300 then
      raise exception 'Minimum withdrawal is 300';
    end if;

    if p_method not in ('Bitcoin', 'Ethereum', 'Beldex') then
      raise exception 'Invalid withdrawal method';
    end if;

    if v_address = '' then
      raise exception 'Please enter a destination address';
    end if;

    if p_method = 'Ethereum' and v_address !~ '^0x[0-9A-Fa-f]{40}$' then
      raise exception 'Invalid Ethereum destination address';
    end if;

    if p_method = 'Bitcoin'
      and v_address !~* '^bc1[ac-hj-np-z02-9]{11,71}$'
      and v_address !~ '^[13][1-9A-HJ-NP-Za-km-z]{25,34}$'
    then
      raise exception 'Invalid Bitcoin destination address';
    end if;

    if p_method = 'Beldex'
      and (v_address !~ '^[1-9A-HJ-NP-Za-km-z]+$'
        or length(v_address) < 90 or length(v_address) > 110)
    then
      raise exception 'Invalid Beldex destination address';
    end if;
  end if;

  perform public.assert_user_can_transact(v_uid);

  if p_request_id is not null then
    select * into v_tx
    from public.transaction
    where user_id = v_uid and request_id = p_request_id
    limit 1;
    if found then return v_tx; end if;
  end if;

  if p_type = 'withdraw' then
    update public.user_profile
    set available_balance = available_balance - p_amount, updated_at = now()
    where user_id = v_uid and available_balance >= p_amount;
    if not found then raise exception 'Insufficient balance'; end if;
  end if;

  insert into public.transaction(user_id,type,amount,status,approval_status,method,note,request_id)
  values (v_uid,p_type,p_amount,'pending','awaiting',p_method,v_address,p_request_id)
  returning * into v_tx;

  return v_tx;
exception
  when unique_violation then
    if p_request_id is not null then
      select * into v_tx
      from public.transaction
      where user_id = v_uid and request_id = p_request_id
      limit 1;
      if found then return v_tx; end if;
    end if;
    raise;
end;
$fixture$;
revoke all on function public.create_financial_transaction(text,numeric,text,text,uuid) from public, anon;
grant execute on function public.create_financial_transaction(text,numeric,text,text,uuid) to authenticated, postgres, service_role;

-- Production has the three-argument adjustment function only. The repository
-- migration may safely drop a stale four-argument variant if one is ever present.
drop function if exists public.admin_adjust_balance(uuid,numeric,text,text);

-- Capture the relevant production migration-history slice as metadata only.
-- Do not overwrite the isolated database's actual Supabase migration ledger: that ledger
-- must remain the repository-reset ledger so CI can still report reproducible migrations.
-- These rows are observed production version/name pairs; the catalog-only ROI migration
-- is intentionally absent from the observed production history and must not be inferred applied.
create temporary table _production_schema_migration_history_fixture (
  production_version text primary key,
  production_name text not null,
  repository_migration text,
  evidence_class text not null
) on commit drop;

insert into _production_schema_migration_history_fixture
  (production_version, production_name, repository_migration, evidence_class)
values
  ('20261010053557','correct_gns_daily_interest_rate',null,'observed production history'),
  ('20261010110000','correct_other_plan_daily_interest',null,'observed production history'),
  ('20261011054325','20261011010000_bdx_native_investments','20261011010000_bdx_native_investments.sql','version/name drift; match by migration content'),
  ('20261011054333','20261011020000_currency_aware_wallet_transactions','20261011020000_currency_aware_wallet_transactions.sql','version/name drift; match by migration content'),
  ('20261011054340','20261011030000_currency_reconciliation_v2','20261011030000_currency_reconciliation_v2.sql','version/name drift; match by migration content'),
  ('20261011054348','20261011040000_currency_schema_recovery_guard','20261011040000_currency_schema_recovery_guard.sql','version/name drift; match by migration content');

-- Fail closed if the reconstructed pre-migration schema drifts from observed production.
do $assert_production_shape$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='user_profile'
      and column_name='referral_earnings_bdx'
  ) then
    raise exception 'fixture mismatch: referral_earnings_bdx should be absent before recovery migration';
  end if;
  if to_regprocedure('public.admin_fund_user(uuid,numeric,text)') is null
     or to_regprocedure('public.admin_fund_user(uuid,numeric,text,text)') is not null then
    raise exception 'fixture mismatch: expected only the production three-argument admin_fund_user overload';
  end if;
  if to_regprocedure('public.admin_adjust_balance(uuid,numeric,text)') is null
     or to_regprocedure('public.admin_adjust_balance(uuid,numeric,text,text)') is not null then
    raise exception 'fixture mismatch: expected only the production three-argument admin_adjust_balance overload';
  end if;
  if to_regprocedure('public.create_financial_transaction(text,numeric,text,text,uuid)') is null
     or to_regprocedure('public.create_financial_transaction(text,numeric,text,text,uuid,text)') is null then
    raise exception 'fixture mismatch: expected both observed create_financial_transaction overloads';
  end if;
  if not has_function_privilege('authenticated','public.admin_fund_user(uuid,numeric,text)','EXECUTE')
     or not has_function_privilege('service_role','public.admin_fund_user(uuid,numeric,text)','EXECUTE')
     or has_function_privilege('anon','public.admin_fund_user(uuid,numeric,text)','EXECUTE') then
    raise exception 'fixture mismatch: admin_fund_user grants differ from observed production grants';
  end if;
  if not has_function_privilege('authenticated','public.create_financial_transaction(text,numeric,text,text,uuid)','EXECUTE')
     or not has_function_privilege('service_role','public.create_financial_transaction(text,numeric,text,text,uuid)','EXECUTE')
     or has_function_privilege('anon','public.create_financial_transaction(text,numeric,text,text,uuid)','EXECUTE') then
    raise exception 'fixture mismatch: legacy transaction RPC grants differ from observed production grants';
  end if;
  if (select count(*) from _production_schema_migration_history_fixture) <> 6
     or not exists (select 1 from _production_schema_migration_history_fixture
                    where production_version='20261011054348'
                      and production_name='20261011040000_currency_schema_recovery_guard')
     or not exists (select 1 from _production_schema_migration_history_fixture
                    where production_version='20261011054333'
                      and production_name='20261011020000_currency_aware_wallet_transactions')
     or not exists (select 1 from _production_schema_migration_history_fixture
                    where production_version='20261011054340'
                      and production_name='20261011030000_currency_reconciliation_v2')
     or not exists (select 1 from _production_schema_migration_history_fixture
                    where production_version='20261011054325'
                      and production_name='20261011010000_bdx_native_investments') then
    raise exception 'fixture mismatch: relevant production migration-history slice differs from observed version/name pairs';
  end if;
  if exists (select 1 from _production_schema_migration_history_fixture
             where production_version='20261011003000'
                or production_name='20261011003000_daily_roi_rate_interpretation') then
    raise exception 'fixture mismatch: catalog-only ROI migration must remain absent from observed production history';
  end if;
  if not has_function_privilege('authenticated','public.admin_adjust_balance(uuid,numeric,text)','EXECUTE')
     or not has_function_privilege('service_role','public.admin_adjust_balance(uuid,numeric,text)','EXECUTE')
     or has_function_privilege('anon','public.admin_adjust_balance(uuid,numeric,text)','EXECUTE') then
    raise exception 'fixture mismatch: admin_adjust_balance grants differ from observed production grants';
  end if;
  if has_function_privilege('authenticated','public.credit_referral_for_deposit(uuid)','EXECUTE')
     or not has_function_privilege('service_role','public.credit_referral_for_deposit(uuid)','EXECUTE')
     or has_function_privilege('anon','public.credit_referral_for_deposit(uuid)','EXECUTE') then
    raise exception 'fixture mismatch: legacy referral RPC grants differ from observed production grants';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='transaction' and column_name='currency'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='user_investment' and column_name='currency'
  ) then
    raise exception 'fixture mismatch: expected observed currency columns on ledger and investments';
  end if;
end;
$assert_production_shape$;

commit;
