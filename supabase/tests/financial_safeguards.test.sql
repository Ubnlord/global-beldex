begin;

create extension if not exists pgtap with schema extensions;

select plan(61);

-- Schema and RLS baseline.
select has_table('public', 'user_profile', 'user_profile exists');
select has_table('public', 'transaction', 'transaction exists');
select has_table('public', 'user_investment', 'user_investment exists');
select has_table('public', 'investment_plan_catalog', 'investment_plan_catalog exists');
select has_table('public', 'admin_action_audit', 'admin_action_audit exists');
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
select has_function('public', 'admin_fund_user', array['uuid','numeric','text'], 'admin_fund_user signature');
select has_function('public', 'admin_adjust_balance', array['uuid','numeric','text'], 'admin_adjust_balance signature');
select has_function('public', 'admin_approve_deposit', array['uuid','text'], 'admin_approve_deposit signature');
select has_function('public', 'admin_reject_deposit', array['uuid','text'], 'admin_reject_deposit signature');
select has_function('public', 'admin_approve_withdrawal', array['uuid','text'], 'admin_approve_withdrawal signature');
select has_function('public', 'admin_reject_withdrawal', array['uuid','text'], 'admin_reject_withdrawal signature');
select has_function('public', 'admin_manage_investment', array['uuid','numeric','text','text'], 'admin_manage_investment signature');

select is_definer('public', 'admin_fund_user', array['uuid','numeric','text'], 'admin_fund_user is security definer');
select is_definer('public', 'admin_adjust_balance', array['uuid','numeric','text'], 'admin_adjust_balance is security definer');
select is_definer('public', 'admin_approve_deposit', array['uuid','text'], 'admin_approve_deposit is security definer');
select is_definer('public', 'admin_reject_deposit', array['uuid','text'], 'admin_reject_deposit is security definer');
select is_definer('public', 'admin_approve_withdrawal', array['uuid','text'], 'admin_approve_withdrawal is security definer');
select is_definer('public', 'admin_reject_withdrawal', array['uuid','text'], 'admin_reject_withdrawal is security definer');
select is_definer('public', 'admin_manage_investment', array['uuid','numeric','text','text'], 'admin_manage_investment is security definer');

-- Financial admin RPC execution is never anonymous.
select function_privs_are('public', 'admin_fund_user', array['uuid','numeric','text'], 'anon', '{}', 'anon cannot execute admin_fund_user');
select function_privs_are('public', 'admin_adjust_balance', array['uuid','numeric','text'], 'anon', '{}', 'anon cannot execute admin_adjust_balance');
select function_privs_are('public', 'admin_approve_deposit', array['uuid','text'], 'anon', '{}', 'anon cannot execute admin_approve_deposit');
select function_privs_are('public', 'admin_reject_deposit', array['uuid','text'], 'anon', '{}', 'anon cannot execute admin_reject_deposit');
select function_privs_are('public', 'admin_approve_withdrawal', array['uuid','text'], 'anon', '{}', 'anon cannot execute admin_approve_withdrawal');
select function_privs_are('public', 'admin_reject_withdrawal', array['uuid','text'], 'anon', '{}', 'anon cannot execute admin_reject_withdrawal');
select function_privs_are('public', 'admin_manage_investment', array['uuid','numeric','text','text'], 'anon', '{}', 'anon cannot execute admin_manage_investment');

-- Client-facing execution is authenticated-only where intended.
select function_privs_are('public', 'admin_fund_user', array['uuid','numeric','text'], 'authenticated', array['EXECUTE'], 'authenticated can reach admin_fund_user; function enforces permission');
select function_privs_are('public', 'admin_adjust_balance', array['uuid','numeric','text'], 'authenticated', array['EXECUTE'], 'authenticated can reach admin_adjust_balance; function enforces permission');
select function_privs_are('public', 'create_financial_transaction', array['text','numeric','text','text','uuid'], 'authenticated', array['EXECUTE'], 'authenticated can create financial requests');

select ok(
  position('p_type = ''withdraw'' and p_amount < 300' in pg_get_functiondef('public.create_financial_transaction(text,numeric,text,text,uuid)'::regprocedure)) > 0,
  'withdrawal RPC enforces the $300 minimum'
);
select function_privs_are('public', 'swap_assets', array['uuid','text','text','numeric','numeric'], 'authenticated', '{}', 'authenticated cannot execute swap_assets directly');
select function_privs_are('public', 'swap_assets', array['uuid','text','text','numeric','numeric'], 'service_role', array['EXECUTE'], 'service role can execute swap_assets');

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

-- Source-level invariants for the two most sensitive admin balance RPCs.
select ok(
  position('p_amount <= 0' in pg_get_functiondef('public.admin_fund_user(uuid,numeric,text)'::regprocedure)) > 0
  and position('reason is required' in pg_get_functiondef('public.admin_fund_user(uuid,numeric,text)'::regprocedure)) > 0
  and position('v_profile.blocked' in pg_get_functiondef('public.admin_fund_user(uuid,numeric,text)'::regprocedure)) > 0,
  'admin_fund_user validates amount, reason, and blocked status'
);

select ok(
  position('p_delta = 0' in pg_get_functiondef('public.admin_adjust_balance(uuid,numeric,text)'::regprocedure)) > 0
  and position('reason is required' in pg_get_functiondef('public.admin_adjust_balance(uuid,numeric,text)'::regprocedure)) > 0
  and position('v_profile.available_balance + p_delta < 0' in pg_get_functiondef('public.admin_adjust_balance(uuid,numeric,text)'::regprocedure)) > 0
  and position('v_profile.blocked' in pg_get_functiondef('public.admin_adjust_balance(uuid,numeric,text)'::regprocedure)) > 0,
  'admin_adjust_balance validates delta, reason, blocked status, and nonnegative balance'
);

select * from finish();

rollback;
