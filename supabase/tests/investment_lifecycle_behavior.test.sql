begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

-- Assert the database catalog contains all seven published daily rates.
select is((select daily_rate from public.investment_plan_catalog where id='gns'),0.019::numeric,'GNS daily rate equals 1.90% daily ROI');
select is((select min_amount * daily_rate from public.investment_plan_catalog where id='gns'),76::numeric,'GNS minimum 4,000 BDX investment earns 76 BDX per full day');
select is((select daily_rate from public.investment_plan_catalog where id='build'),0.0251::numeric,'BUILD UP daily rate equals 2.51% daily ROI');
select is((select daily_rate from public.investment_plan_catalog where id='follow'),0.0392::numeric,'FOLLOW UP daily rate equals 3.92% daily ROI');
select is((select daily_rate from public.investment_plan_catalog where id='apex'),0.0856::numeric,'APEX daily rate equals 8.56% daily ROI');
select is((select daily_rate from public.investment_plan_catalog where id='edifex'),0.1343::numeric,'EDIFEX daily rate equals 13.43% daily ROI');
select is((select daily_rate from public.investment_plan_catalog where id='dixon'),0.1543::numeric,'DIXON daily rate equals 15.43% daily ROI');
select is((select daily_rate from public.investment_plan_catalog where id='falcon'),0.2378::numeric,'FALCON daily rate equals 23.78% daily ROI');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a2200000-0000-4000-8000-000000000001','authenticated','authenticated',
  'investment-lifecycle-user@example.test','',now(),'{}'::jsonb,'{}'::jsonb,now(),now()
) on conflict (id) do nothing;

insert into public.user_profile(user_id,available_balance,locked_balance,bdx_balance,locked_bdx_balance)
values ('a2200000-0000-4000-8000-000000000001',0,100,0,100)
on conflict (user_id) do update set available_balance=0,locked_balance=100,bdx_balance=0,locked_bdx_balance=100;

-- A legacy investment omits currency and must remain USD. The second row is
-- explicitly BDX-denominated. Both are past maturity with one uncredited day.
insert into public.user_investment(
  user_id,plan_id,principal,daily_rate,duration_days,started_at,last_accrual_at,status,daily_accrual_enabled
) values (
  'a2200000-0000-4000-8000-000000000001','gns',100,0.01,1,now()-interval '2 days',now()-interval '2 days','active',true
);

insert into public.user_investment(
  user_id,plan_id,principal,daily_rate,duration_days,started_at,last_accrual_at,status,daily_accrual_enabled,currency
) values (
  'a2200000-0000-4000-8000-000000000001','gns',100,0.01,1,now()-interval '2 days',now()-interval '2 days','active',true,'BDX'
);

select set_config('request.jwt.claim.sub','a2200000-0000-4000-8000-000000000001',true);

select is(public.accrue_user_investments('a2200000-0000-4000-8000-000000000001'),1::numeric,
  'legacy numeric accrual return reports USD interest only, without summing BDX');
select is((select available_balance from public.user_profile where user_id='a2200000-0000-4000-8000-000000000001'),101::numeric,
  'legacy USD maturity returns principal and profit to USD wallet');
select is((select bdx_balance from public.user_profile where user_id='a2200000-0000-4000-8000-000000000001'),101::numeric,
  'BDX maturity returns principal and profit to BDX wallet');
select is((select locked_balance from public.user_profile where user_id='a2200000-0000-4000-8000-000000000001'),0::numeric,
  'USD locked principal is released at maturity');
select is((select locked_bdx_balance from public.user_profile where user_id='a2200000-0000-4000-8000-000000000001'),0::numeric,
  'BDX locked principal is released at maturity');
select is(public.accrue_user_investments('a2200000-0000-4000-8000-000000000001'),0::numeric,
  'repeated accrual after maturity credits nothing');
select is((select count(*)::integer from public.transaction where user_id='a2200000-0000-4000-8000-000000000001' and note='Investment principal returned'),2,
  'each investment has exactly one principal-return ledger entry');
select is((select count(*)::integer from public.user_investment where user_id='a2200000-0000-4000-8000-000000000001' and status='completed' and currency='USD'),1,
  'legacy investment remains USD and is marked completed');
select is((select count(*)::integer from public.user_investment where user_id='a2200000-0000-4000-8000-000000000001' and status='completed' and currency='BDX'),1,
  'BDX investment is marked completed separately');

select * from finish();
rollback;
