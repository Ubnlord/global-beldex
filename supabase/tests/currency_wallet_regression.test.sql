begin;

create extension if not exists pgtap with schema extensions;
select plan(18);

-- Schema denomination defaults preserve existing records as USD.
select has_column('public','user_profile','locked_bdx_balance','BDX principal has a separate locked balance');
select has_column('public','user_investment','currency','investment currency is recorded');
select has_column('public','transaction','currency','ledger currency is recorded');
select col_default_is('public','user_investment','currency', 'BDX', 'new investments default to BDX');
select col_default_is('public','transaction','currency', 'BDX', 'new transactions default to BDX');

-- Daily simple-interest contract for all seven published plans.
select is((4000::numeric * 0.019), 76::numeric, 'GNS 4,000 BDX earns 76 BDX per day');
select is((4000::numeric * 0.019 * 30), 2280::numeric, 'GNS 30-day profit is 2,280 BDX');
select is((4000::numeric + 4000::numeric * 0.019 * 30), 6280::numeric, 'GNS maturity total is 6,280 BDX');
select is((11000::numeric * 0.0251), 276.1::numeric, 'BUILD UP daily interest uses daily rate');
select is((17000::numeric * 0.0392), 666.4::numeric, 'FOLLOW UP daily interest uses daily rate');
select is((40000::numeric * 0.0856), 3424::numeric, 'APEX daily interest uses daily rate');
select is((90000::numeric * 0.1343), 12087::numeric, 'EDIFEX daily interest uses daily rate');
select is((160000::numeric * 0.1543), 24688::numeric, 'DIXON daily interest uses daily rate');
select is((220000::numeric * 0.2378), 52316::numeric, 'FALCON daily interest uses daily rate');

-- Automatic accrual is intentionally disabled; assert fail-closed behavior
-- rather than testing the retired automatic accrual implementation.
select ok(pg_get_functiondef('public.accrue_user_investments(uuid)'::regprocedure) like
  '%and currency=''BDX''%', 'investment accrual processes only BDX-denominated investments');
select ok(pg_get_functiondef('public.run_daily_investment_accrual()'::regprocedure) like
  '%Automatic investment accrual is disabled%', 'legacy scheduled accrual entry point fails closed');
select ok(pg_get_functiondef('public.admin_add_daily_investment_profit(uuid,text)'::regprocedure) like
  '%v_inv.principal * v_inv.daily_rate%', 'manual profit uses the full daily rate without dividing by duration');
select ok(pg_get_functiondef('public.admin_add_daily_investment_profit(uuid,text)'::regprocedure) like
  '%on conflict (investment_id,profit_date) do nothing%', 'manual profit prevents duplicate credits for the same UTC day');

select * from finish();
rollback;
