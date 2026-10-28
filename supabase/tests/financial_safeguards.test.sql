begin;

create extension if not exists pgtap with schema extensions;

select plan(82);

-- Schema and RLS baseline.
select has_table('public', 'user_profile', 'user_profile exists');
select has_table('public', 'transaction', 'transaction exists');
select has_table('public', 'user_investment', 'user_investment exists');
select ok((select column_default like '%BDX%' from information_schema.columns where table_schema='public' and table_name='transaction' and column_name='currency'), 'new transaction rows default to BDX');
select ok((select column_default like '%BDX%' from information_schema.columns where table_schema='public' and table_name='user_investment' and column_name='currency'), 'new investment rows default to BDX');
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
select ok(to_regprocedure('public.admin_fund_user(uuid,numeric,text)') is not null, 'legacy USD funding signature remains available for existing admin clients');
select ok(to_regprocedure('public.admin_adjust_balance(uuid,numeric,text)') is not null, 'legacy USD adjustment signature remains available for existing admin clients');
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
  position('v_method not in (''BELDEX'',''BITCOIN'')' in pg_get_functiondef('public.create_financial_transaction(text,numeric,text,text,uuid,text)'::regprocedure)) > 0
  and position('p_type=''deposit'' and v_method <> ''BELDEX''' in pg_get_functiondef('public.create_financial_transaction(text,numeric,text,text,uuid,text)'::regprocedure)) > 0,
  'financial request RPC allows BTC withdrawals but keeps BTC deposits on the verified deposit-intent workflow and rejects unsupported methods'
);

select ok(
  position('Only BDX accounting is supported' in pg_get_functiondef('public.create_financial_transaction(text,numeric,text,text,uuid,text)'::regprocedure)) > 0,
  'withdrawal RPC rejects legacy USD denomination'
);

select ok(
  position('Invalid Beldex destination address' in pg_get_functiondef('public.create_financial_transaction(text,numeric,text,text,uuid,text)'::regprocedure)) > 0,
  'withdrawal RPC validates Beldex destinations'
);

select ok(
  to_regprocedure('public.swap_assets(uuid,text,text,numeric,numeric)') is null,
  'currency swap RPC is removed from the exposed database API'
);

select ok(
  to_regprocedure('public.create_financial_transaction(text,numeric,text,text,uuid)') is not null
  and position('p_request_id' in pg_get_functiondef('public.create_financial_transaction(text,numeric,text,text,uuid)'::regprocedure)) > 0
  and position('BDX' in pg_get_functiondef('public.create_financial_transaction(text,numeric,text,text,uuid)'::regprocedure)) > 0
  and not has_function_privilege('anon', 'public.create_financial_transaction(text,numeric,text,text,uuid)', 'EXECUTE'),
  'legacy currency-optional RPC remains only as an authenticated wrapper routing to guarded BDX accounting'
);
select has_function('public', 'admin_adjust_bdx_balance', array['uuid','numeric','text','text'], 'BDX admin adjustment RPC exists');
select has_function('public', 'admin_financial_reconciliation_v3', array[]::text[], 'currency-separated reconciliation v3 exists');
select ok(
  to_regprocedure('public.admin_manage_investment(uuid,numeric,boolean,text,text)') is null,
  'legacy five-argument investment management overload is absent after cutover'
);
select ok(
  position('financial_currency_conversion_profile_audit' in pg_get_functiondef('public.admin_financial_reconciliation_v3()'::regprocedure)) > 0
  and position('financial_currency_conversion_investment_audit' in pg_get_functiondef('public.admin_financial_reconciliation_v3()'::regprocedure)) > 0,
  'post-conversion reconciliation includes both conversion audit ledgers'
);
select ok(
  position('Admin daily investment profit' in pg_get_functiondef('public.admin_financial_reconciliation_v3()'::regprocedure)) > 0,
  'BDX profit reconciliation includes authorized manual daily profit credits'
);
select ok(
  position('and currency=''BDX''' in pg_get_functiondef('public.accrue_user_investments(uuid)'::regprocedure)) > 0
  and position('available_balance' in pg_get_functiondef('public.accrue_user_investments(uuid)'::regprocedure)) = 0,
  'automatic accrual cannot mutate archived legacy wallet balances'
);
select ok(
  to_regprocedure('public.admin_manage_investment(uuid,numeric,boolean,text,text)') is null,
  'legacy five-argument investment-management overload is retired'
);
select ok(
  position('Legacy investment is read-only until the audited BDX conversion is completed' in
    pg_get_functiondef('public.admin_manage_investment(uuid,numeric,text,text)'::regprocedure)) > 0,
  'legacy four-argument admin RPC cannot mutate unconverted investment records'
);
select ok(
  position('Legacy investment is read-only until the audited BDX conversion is completed' in
    pg_get_functiondef('public.admin_update_investment(uuid,numeric,boolean)'::regprocedure)) > 0,
  'BDX accrual settings cannot mutate unconverted investment records'
);
select ok(
  position('admin_has_permission(''view_transactions'')' in pg_get_functiondef('public.admin_financial_reconciliation_v3()'::regprocedure)) > 0
  and position('referral_earnings_bdx' in pg_get_functiondef('public.admin_financial_reconciliation_v3()'::regprocedure)) > 0
  and position('lower(coalesce(t.method' in pg_get_functiondef('public.admin_financial_reconciliation_v3()'::regprocedure)) > 0
  and position('admin adjustment' in pg_get_functiondef('public.admin_financial_reconciliation_v3()'::regprocedure)) > 0,
  'BDX reconciliation enforces report permission, includes BDX referrals, and excludes legacy admin adjustments from user withdrawals'
);

select ok(
  (select abs(daily_rate - 0.019::numeric) < 0.000000000000000001 from public.investment_plan_catalog where id='gns')
  and (select abs(daily_rate - 0.0251::numeric) < 0.000000000000000001 from public.investment_plan_catalog where id='build')
  and (select abs(daily_rate - 0.0392::numeric) < 0.000000000000000001 from public.investment_plan_catalog where id='follow')
  and (select abs(daily_rate - 0.0856::numeric) < 0.000000000000000001 from public.investment_plan_catalog where id='apex')
  and (select abs(daily_rate - 0.1343::numeric) < 0.000000000000000001 from public.investment_plan_catalog where id='edifex')
  and (select abs(daily_rate - 0.1543::numeric) < 0.000000000000000001 from public.investment_plan_catalog where id='dixon')
  and (select abs(daily_rate - 0.2378::numeric) < 0.000000000000000001 from public.investment_plan_catalog where id='falcon'),
  'new BDX plan daily rates equal published daily ROI'
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

-- Compatibility signatures remain only where their behavior is safe after cutover.
select ok(
  to_regprocedure('public.admin_fund_user(uuid,numeric,text)') is not null
  and position('BDX' in pg_get_functiondef('public.admin_fund_user(uuid,numeric,text)'::regprocedure)) > 0,
  'admin funding compatibility RPC is BDX-only'
);

select ok(
  to_regprocedure('public.admin_adjust_balance(uuid,numeric,text)') is not null
  and position('Legacy balance adjustments are disabled' in pg_get_functiondef('public.admin_adjust_balance(uuid,numeric,text)'::regprocedure)) > 0
  and not has_function_privilege('authenticated', 'public.admin_adjust_balance(uuid,numeric,text)', 'EXECUTE'),
  'legacy balance adjustment compatibility RPC fails closed and is not executable by authenticated clients'
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
