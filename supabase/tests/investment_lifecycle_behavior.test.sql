begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

-- Assert the database catalog contains all seven published daily rates.
select ok(abs((select daily_rate from public.investment_plan_catalog where id='gns')-(0.019::numeric))<0.000000000000000001,'GNS daily rate equals the published daily ROI');
select ok(abs((select daily_rate from public.investment_plan_catalog where id='build')-(0.0251::numeric))<0.000000000000000001,'BUILD UP daily rate equals the published daily ROI');
select ok(abs((select daily_rate from public.investment_plan_catalog where id='follow')-(0.0392::numeric))<0.000000000000000001,'FOLLOW UP daily rate equals the published daily ROI');
select ok(abs((select daily_rate from public.investment_plan_catalog where id='apex')-(0.0856::numeric))<0.000000000000000001,'APEX daily rate equals the published daily ROI');
select ok(abs((select daily_rate from public.investment_plan_catalog where id='edifex')-(0.1343::numeric))<0.000000000000000001,'EDIFEX daily rate equals the published daily ROI');
select ok(abs((select daily_rate from public.investment_plan_catalog where id='dixon')-(0.1543::numeric))<0.000000000000000001,'DIXON daily rate equals the published daily ROI');
select ok(abs((select daily_rate from public.investment_plan_catalog where id='falcon')-(0.2378::numeric))<0.000000000000000001,'FALCON daily rate equals the published daily ROI');

-- Automatic accrual is deliberately disabled. Verify the old entry points
-- fail closed and the replacement manual path retains its financial controls.
select ok(pg_get_functiondef('public.accrue_user_investments(uuid)'::regprocedure) like
  '%Automatic investment accrual is disabled%', 'legacy per-user accrual is disabled');
select ok(pg_get_functiondef('public.run_daily_investment_accrual()'::regprocedure) like
  '%Automatic investment accrual is disabled%', 'legacy scheduled accrual is disabled');
select ok(pg_get_functiondef('public.admin_add_daily_investment_profit(uuid,text)'::regprocedure) like
  '%v_inv.principal * v_inv.daily_rate%', 'manual profit multiplies principal by the full daily rate');
select ok(pg_get_functiondef('public.admin_add_daily_investment_profit(uuid,text)'::regprocedure) not like
  '%v_inv.principal * v_inv.daily_rate /%', 'manual profit does not divide the daily rate by duration');
select ok(pg_get_functiondef('public.admin_add_daily_investment_profit(uuid,text)'::regprocedure) like
  '%admin_has_permission%', 'manual profit checks admin permissions');
select ok(pg_get_functiondef('public.admin_add_daily_investment_profit(uuid,text)'::regprocedure) like
  '%Blocked accounts cannot receive manual daily profit%', 'blocked users cannot receive manual profit');
select ok(pg_get_functiondef('public.admin_add_daily_investment_profit(uuid,text)'::regprocedure) like
  '%Reason is required%', 'manual profit requires an audit reason');
select ok(pg_get_functiondef('public.admin_add_daily_investment_profit(uuid,text)'::regprocedure) like
  '%on conflict (investment_id,profit_date) do nothing%', 'duplicate same-day credits are ignored');
select ok(pg_get_functiondef('public.admin_add_daily_investment_profit(uuid,text)'::regprocedure) like
  '%admin_action_audit%', 'manual profit records an admin audit event');

select * from finish();
rollback;
