begin;

select plan(14);

select has_column('public', 'user_profile', 'available_balance',
  'USD available balance remains present');
select has_column('public', 'user_profile', 'locked_balance',
  'USD locked balance remains present');
select has_column('public', 'user_profile', 'bdx_balance',
  'BDX available balance remains present');
select has_column('public', 'user_profile', 'locked_bdx_balance',
  'BDX locked balance exists separately');
select has_column('public', 'user_profile', 'total_deposits_bdx',
  'BDX deposit totals are stored separately');
select has_column('public', 'user_profile', 'total_withdrawals_bdx',
  'BDX withdrawal totals are stored separately');
select has_column('public', 'user_investment', 'currency',
  'Investments retain an explicit denomination');
select has_column('public', 'transaction', 'currency',
  'Transactions retain an explicit denomination');

select has_function('public', 'create_financial_transaction',
  array['text','numeric','text','text','uuid','text'],
  'Currency-aware transaction RPC exists');
select ok(to_regprocedure('public.admin_financial_reconciliation_v2()') is null,
  'Legacy reconciliation RPC is retired');
select has_function('public', 'buy_investment_plan',
  array['text','numeric'],
  'Investment purchase RPC remains present');
select has_function('public', 'accrue_user_investments',
  array['uuid'],
  'Investment accrual RPC remains present');
select has_function('public', 'admin_adjust_bdx_balance',
  array['uuid','numeric','text','text'],
  'BDX admin adjustment RPC exists');
select has_function('public', 'admin_financial_reconciliation_v3',
  array[]::text[],
  'Currency-separated reconciliation v3 exists');

select * from finish();
rollback;
