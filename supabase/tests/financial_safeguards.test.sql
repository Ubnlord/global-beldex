begin;

create extension if not exists pgtap with schema extensions;

select plan(78);

-- Schema and RLS baseline.
select has_table('public', 'user_profile', 'user_profile exists');
select has_table('public', 'transaction', 'transaction exists');
select has_table('public', 'user_investment', 'user_investment exists');
select has_table('public', 'investment_plan_catalog', 'investment_plan_catalog exists');
select has_table('public', 'admin_action_audit', 'admin_action_audit exists');
select ok((select not attnotnull from pg_attribute where attrelid='public.admin_action_audit'::regclass and attname='admin_id'), 'admin audit actor can be null for deleted admins');
select has_table('public', 'transaction_audit', 'transaction_audit exists');

select ok((select relrowsecurity from pg_class where oid = 'public.user_profile'::regclass), 'user_profile has RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.transaction'::regclass), 'transaction has RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.user_investment'::regclass), 'user_investment has RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.admin_action_audit'::regclass), 'admin_action_audit has RLS enabled');
select ok((select relrowsecurity from pg_class where oid = 'public.transaction_audit'::regclass), 'transaction_audit has RLS enabled');

-- Financial constraints.
select ok(exists (
  select 1 from pg_constraint
  where conrelid = 'public.user_profile'::regclass
    and conname = 'user_profile_available_balance_nonnegative'
), 'available balance cannot be negative');

select ok(exists (
  select 1 from pg_constraint
  where conrelid = 'public.user_profile'::regclass
    and conname = 'user_profile_locked_balance_nonnegative'
), 'locked balance cannot be negative');

select ok(exists (
  select 1 from pg_constraint
  where conrelid = 'public.user_profile'::regclass
    and conname = 'user_profile_bdx_balance_nonnegative'
), 'BDX balance cannot be negative');

select ok(exists (
  select 1 from pg_constraint
  where conrelid = 'public.transaction'::regclass
    and conname = 'transaction_amount_positive'
), 'transaction amount must be positive');

select ok(exists (
  select 1 from pg_constraint
  where conrelid = 'public.user_investment'::regclass
    and conname = 'user_investment_principal_positive'
), 'investment principal must be positive');

select ok(exists (
  select 1 from pg_constraint
  where conrelid = 'public.user_investment'::regclass
    and conname = 'user_investment_daily_rate_nonnegative'
), 'investment daily rate cannot be negative');

select ok(exists (
  select 1 from pg_constraint
  where conrelid = 'public.user_investment'::regclass
    and conname = 'user_investment_duration_positive'
), 'investment duration must be positive');

select ok(exists (
  select 1 from pg_constraint
  where conrelid = 'public.user_investment'::regclass
    and conname = 'user_investment_credited_profit_nonnegative'
), 'credited profit cannot be negative');

select ok(exists (
  select 1 from pg_constraint
  where conrelid = 'public.investment_plan_catalog'::regclass
    and conname = 'investment_plan_min_amount_positive'
), 'plan minimum must be positive');

select ok(exists (
  select 1 from pg_constraint
  where conrelid = 'public.investment_plan_catalog'::regclass
    and conname = 'investment_plan_max_amount_valid'
), 'plan maximum cannot be below minimum');

select ok(exists (
  select 1 from pg_constraint
  where conrelid = 'public.investment_plan_catalog'::regclass
    and conname = 'investment_plan_duration_positive'
), 'plan duration must be positive');

select ok(exists (
  select 1 from pg_constraint
  where conrelid = 'public.investment_plan_catalog'::regclass
    and conname = 'investment_plan_daily_rate_nonnegative'
), 'plan daily rate cannot be negative');

-- Critical RPC signatures and security-definer status.
select ok(to_regprocedure('public.admin_fund_user(uuid,numeric,text)') is null, 'legacy USD funding signature is retired');
select ok(to_regprocedure('public.admin_adjust_balance(uuid,numeric,text)') is null, 'legacy USD adjustment signature is retired');
select has_function('public', 'admin_approve_deposit', array['uuid','text'], 'admin_approve_deposit signature');
select has_function('public', 'admin_reject_deposit', array['uuid','text'], 'admin_reject_deposit signature');
select has_function('public', 'admin_approve_withdrawal', array['uuid','text'], 'admin_approve_withdrawal signature');
select has_function('public', 'admin_reject_withdrawal', array['uuid','text'], 'admin_reject_withdrawal signature');
select has_function('public', 'admin_manage_investment', array['uuid','numeric','text','text'], 'admin_manage_investment signature');

select is_definer('public', 'admin_adjust_bdx_balance', array['uuid','numeric','text','text'], 'BDX adjustment is security definer');
select ok(
  position('Existing BDX adjustment is missing matching audit evidence' in pg_get_functiondef('public.admin_adjust_bdx_balance(uuid,numeric,text,text)'::regprocedure)) > 0,
  'idempotent BDX adjustment replay fails closed when its audit evidence is missing'
);
select is_definer('public', 'admin_financial_reconciliation_v3', array[]::text[], 'BDX reconciliation is security definer');
select is_definer('public', 'admin_approve_deposit', array['uuid','text'], 'admin_approve_deposit is security definer');
select is_definer('public', 'admin_reject_deposit', array['uuid','text'], 'admin_reject_deposit is security definer');
select is_definer('public', 'admin_approve_withdrawal', array['uuid','text'], 'admin_approve_withdrawal is security definer');
select is_definer('public', 'admin_reject_withdrawal', array['uuid','text'], 'admin_reject_withdrawal is security definer');
select is_definer('public', 'admin_manage_investment', array['uuid','numeric','text','text'], 'admin_manage_investment is security definer');

-- Financial admin RPC execution is never anonymous.
select function_privs_are('public', 'admin_adjust_bdx_balance', array['uuid','numeric','text','text'], 'anon', '{}', 'anon cannot execute BDX adjustment');
select function_privs_are('public', 'admin_financial_reconciliation_v3', array[]::text[], 'anon', '{}', 'anon cannot execute BDX reconciliation');
select function_privs_are('public', 'admin_approve_deposit', array['uuid','text'], 'anon', '{}', 'anon cannot execute admin_approve_deposit');
select function_privs_are('public', 'admin_reject_deposit', array['uuid','text'], 'anon', '{}', 'anon cannot execute admin_reject_deposit');
select function_privs_are('public', 'admin_approve_withdrawal', array['uuid','text'], 'anon', '{}', 'anon cannot execute admin_approve_withdrawal');
select function_privs_are('public', 'admin_reject_withdrawal', array['uuid','text'], 'anon', '{}', 'anon cannot execute admin_reject_withdrawal');
select function_privs_are('public', 'admin_manage_investment', array['uuid','numeric','text','text'], 'anon', '{}', 'anon cannot execute admin_manage_investment');

-- Client-facing execution is authenticated-only where intended.
select function_privs_are('public', 'admin_adjust_bdx_balance', array['uuid','numeric','text','text'], 'authenticated', array['EXECUTE'], 'authenticated can call reference-idempotent BDX adjustment');
select function_privs_are('public', 'admin_financial_reconciliation_v3', array[]::text[], 'authenticated', array['EXECUTE'], 'authenticated can call authorized reconciliation RPC');

select function_privs_are('public', 'create_financial_transaction', array['text','numeric','text','text','uuid','text'], 'authenticated', array['EXECUTE'], 'authenticated can create currency-aware financial requests');

select ok(to_regprocedure('public.create_financial_transaction(text,numeric,text,text,uuid,text)') is not null,
  'currency-explicit financial request RPC exists'
);

select ok(
  position('Invalid Ethereum destination address' in pg_get_functiondef('public.create_financial_transaction(text,numeric,text,text,uuid,text)'::regprocedure)) > 0,
  'withdrawal RPC validates Ethereum destinations'
);

select ok(
  position('Invalid Bitcoin destination address' in pg_get_functiondef('public.create_financial_transaction(text,numeric,text,text,uuid,text)'::regprocedure)) > 0,
  'withdrawal RPC validates Bitcoin destinations'
);

select ok(
  position('Invalid Beldex destination address' in pg_get_functiondef('public.create_financial_transaction(text,numeric,text,text,uuid,text)'::regprocedure)) > 0,
  'withdrawal RPC validates Beldex destinations'
);

select ok(
  to_regprocedure('public.swap_assets(uuid,text,text,numeric,numeric)') is not null
  and position('Currency swaps are retired; use the BDX-native wallet flow' in pg_get_functiondef('public.swap_assets(uuid,text,text,numeric,numeric)'::regprocedure)) > 0
  and not has_function_privilege('public', 'public.swap_assets(uuid,text,text,numeric,numeric)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.swap_assets(uuid,text,text,numeric,numeric)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.swap_assets(uuid,text,text,numeric,numeric)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.swap_assets(uuid,text,text,numeric,numeric)', 'EXECUTE'),
  'currency swap RPC is a fail-closed compatibility stub for service_role only'
);
select ok(to_regprocedure('public.swap_assets(text,text,numeric,numeric)') is null, 'legacy currency swap RPC overload is retired');

-- Runtime proof that the service-role compatibility entrypoint rejects swaps
-- without changing balances, transaction rows, or audit rows.
create temporary table swap_stub_before as
select
  coalesce((select sum(available_balance) from public.user_profile),0) as usd_available,
  coalesce((select sum(locked_balance) from public.user_profile),0) as usd_locked,
  coalesce((select sum(bdx_balance) from public.user_profile),0) as bdx_available,
  coalesce((select sum(locked_bdx_balance) from public.user_profile),0) as bdx_locked,
  (select count(*) from public.transaction) as transaction_count,
  (select count(*) from public.admin_action_audit) as admin_audit_count,
  (select count(*) from public.transaction_audit) as transaction_audit_count;

select throws_ok(
  $$select public.swap_assets('00000000-0000-0000-0000-000000000001'::uuid,'USD','BDX',1,1)$$,
  'P0001',
  'Currency swaps are retired; use the BDX-native wallet flow',
  'retired swap RPC returns the explicit fail-closed error'
);

select ok(
  (select b.usd_available = coalesce((select sum(available_balance) from public.user_profile),0)
    and b.usd_locked = coalesce((select sum(locked_balance) from public.user_profile),0)
    and b.bdx_available = coalesce((select sum(bdx_balance) from public.user_profile),0)
    and b.bdx_locked = coalesce((select sum(locked_bdx_balance) from public.user_profile),0)
    and b.transaction_count = (select count(*) from public.transaction)
    and b.admin_audit_count = (select count(*) from public.admin_action_audit)
    and b.transaction_audit_count = (select count(*) from public.transaction_audit)
   from swap_stub_before b),
  'rejected swap leaves USD/BDX balances, transactions, and audit logs unchanged'
);

select ok(to_regprocedure('public.create_financial_transaction(text,numeric,text,text,uuid)') is null, 'legacy currency-optional financial request RPC is retired');
select has_function('public', 'admin_adjust_bdx_balance', array['uuid','numeric','text','text'], 'BDX admin adjustment RPC exists');
select has_function('public', 'admin_financial_reconciliation_v3', array[]::text[], 'currency-separated reconciliation v3 exists');
select ok(
  position('locked_bdx_balance=locked_bdx_balance-v_old.principal' in pg_get_functiondef('public.admin_manage_investment(uuid,numeric,boolean,text,text)'::regprocedure)) > 0
  and position('Completed or cancelled investments cannot be reactivated' in pg_get_functiondef('public.admin_manage_investment(uuid,numeric,boolean,text,text)'::regprocedure)) > 0,
  'admin investment management preserves BDX principal and prevents unsafe reactivation'
);
select ok(
  position('null::boolean' in pg_get_functiondef('public.admin_manage_investment(uuid,numeric,text,text)'::regprocedure)) > 0,
  'legacy admin investment RPC delegates to currency-aware implementation'
);
select ok(
  position('admin_has_permission(''view_transactions'')' in pg_get_functiondef('public.admin_financial_reconciliation_v3()'::regprocedure)) > 0
  and position('referral_earnings_bdx' in pg_get_functiondef('public.admin_financial_reconciliation_v3()'::regprocedure)) > 0,
  'BDX reconciliation enforces report permission and includes BDX referrals'
);

select ok(
  (select abs(daily_rate - 0.019) < 0.000000000000000001 from public.investment_plan_catalog where id='gns')
  and (select abs(daily_rate - 0.0251) < 0.000000000000000001 from public.investment_plan_catalog where id='build')
  and (select abs(daily_rate - 0.0392) < 0.000000000000000001 from public.investment_plan_catalog where id='follow')
  and (select abs(daily_rate - 0.0856) < 0.000000000000000001 from public.investment_plan_catalog where id='apex')
  and (select abs(daily_rate - 0.1343) < 0.000000000000000001 from public.investment_plan_catalog where id='edifex')
  and (select abs(daily_rate - 0.1543) < 0.000000000000000001 from public.investment_plan_catalog where id='dixon')
  and (select abs(daily_rate - 0.2378) < 0.000000000000000001 from public.investment_plan_catalog where id='falcon'),
  'new BDX plan daily rates equal the published daily ROI percentages'
);

-- Direct table writes remain closed to browser roles.
select ok(not has_table_privilege('authenticated', 'public.user_profile', 'INSERT'), 'authenticated cannot insert user_profile directly');
select ok(not has_table_privilege('authenticated', 'public.user_profile', 'UPDATE'), 'authenticated cannot update user_profile directly');
select ok(not has_table_privilege('authenticated', 'public.transaction', 'INSERT'), 'authenticated cannot insert transactions directly');
select ok(not has_table_privilege('authenticated', 'public.transaction', 'UPDATE'), 'authenticated cannot update transactions directly');
select ok(not has_table_privilege('authenticated', 'public.user_investment', 'INSERT'), 'authenticated cannot insert investments directly');
select ok(not has_table_privilege('authenticated', 'public.admin_action_audit', 'INSERT'), 'authenticated cannot insert admin audit rows directly');
select ok(not has_table_privilege('authenticated', 'public.transaction_audit', 'INSERT'), 'authenticated cannot insert transaction audit rows directly');

select policies_are('public', 'admin_action_audit', array['admin_action_audit_select'], 'admin action audit has only its admin-read policy');
select policies_are('public', 'transaction_audit', array['transaction_audit_select'], 'transaction audit has only its admin-read policy');

-- Legacy USD balance-mutation endpoints are retired; new admin credits/debits
-- must use the reference-idempotent BDX adjustment RPC.
select ok(
  to_regprocedure('public.admin_fund_user(uuid,numeric,text)') is null
  and to_regprocedure('public.admin_fund_user(uuid,numeric,text,text)') is null,
  'legacy USD funding RPCs are retired'
);

select ok(
  to_regprocedure('public.admin_adjust_balance(uuid,numeric,text)') is null
  and to_regprocedure('public.admin_adjust_balance(uuid,numeric,text,text)') is null,
  'legacy USD adjustment RPCs are retired'
);

select ok(
  position('Reference is required for idempotency' in pg_get_functiondef('public.admin_adjust_bdx_balance(uuid,numeric,text,text)'::regprocedure)) > 0
  and position('md5(p_user_id::text||'':''||v_reference)' in pg_get_functiondef('public.admin_adjust_bdx_balance(uuid,numeric,text,text)'::regprocedure)) > 0,
  'BDX admin adjustments require a stable idempotency reference'
);

select ok(
  to_regprocedure('public.admin_financial_reconciliation()') is null,
  'legacy reconciliation RPC is retired'
);
select ok(
  to_regprocedure('public.admin_financial_reconciliation_v2()') is null,
  'legacy v2 reconciliation RPC is retired'
);
select * from finish();

rollback;
