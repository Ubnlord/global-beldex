begin;
create extension if not exists pgtap with schema extensions;

select plan(18);

-- All fixtures are isolated and rolled back at the end of this suite.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a1100000-0000-4000-8000-000000000001','authenticated','authenticated','wallet-bdx-user@example.test','',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('a1100000-0000-4000-8000-000000000002','authenticated','authenticated','wallet-bdx-admin@example.test','',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('a1100000-0000-4000-8000-000000000003','authenticated','authenticated','wallet-bdx-referrer@example.test','',now(),'{}'::jsonb,'{}'::jsonb,now(),now())
on conflict (id) do nothing;

insert into public.user_profile(user_id,bdx_balance)
values ('a1100000-0000-4000-8000-000000000003',0)
on conflict (user_id) do update set bdx_balance=0;

insert into public.user_profile(user_id,bdx_balance,referred_by_user_id)
values ('a1100000-0000-4000-8000-000000000001',10000,'a1100000-0000-4000-8000-000000000003')
on conflict (user_id) do update
set bdx_balance=10000,referred_by_user_id='a1100000-0000-4000-8000-000000000003';

insert into public.admin_user(user_id,role,permissions)
values ('a1100000-0000-4000-8000-000000000002','admin',array['approve_transactions','reject_transactions','manage_users','view_transactions'])
on conflict (user_id) do update set permissions=excluded.permissions;

select set_config('request.jwt.claim.sub','a1100000-0000-4000-8000-000000000001',true);
select is((select bdx_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),10000::numeric,'initial BDX wallet fixture');
select is((public.create_financial_transaction('withdraw',4000,'Beldex',repeat('A',95),'a1100000-0000-4000-8000-000000000101','BDX')).currency,'BDX'::text,'withdrawal request is BDX-denominated');
select is((select bdx_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),6000::numeric,'withdrawal reserves funds from BDX wallet');
select is((public.create_financial_transaction('withdraw',4000,'Beldex',repeat('A',95),'a1100000-0000-4000-8000-000000000101','BDX')).id,(select id from public.transaction where request_id='a1100000-0000-4000-8000-000000000101'),'duplicate request returns the original transaction');
select is((select count(*)::integer from public.transaction where request_id='a1100000-0000-4000-8000-000000000101'),1,'duplicate request creates one ledger row');
select throws_ok($sql$select public.create_financial_transaction('withdraw',4000,'Beldex',repeat('A',95),'a1100000-0000-4000-8000-000000000101','USD')$sql$,'P0001','Only BDX accounting is supported','USD accounting is rejected');
select throws_ok($sql$select public.create_financial_transaction('withdraw',75,'Beldex',repeat('A',95),'a1100000-0000-4000-8000-000000000102','BDX')$sql$,'P0001','Minimum withdrawal is 76 BDX','withdrawals below 76 BDX are rejected');
select throws_ok($sql$select public.create_financial_transaction('deposit',3999,'Beldex',null,'a1100000-0000-4000-8000-000000000103','BDX')$sql$,'P0001','Minimum deposit is 4000 BDX','deposits below 4000 BDX are rejected');

select set_config('request.jwt.claim.sub','a1100000-0000-4000-8000-000000000002',true);
select is((public.admin_reject_transaction((select id from public.transaction where request_id='a1100000-0000-4000-8000-000000000101'),'test rejection')).status,'failed'::text,'rejected withdrawal is marked failed');
select is((select bdx_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),10000::numeric,'rejected withdrawal restores reserved BDX');
select is((select count(*)::integer from public.transaction_audit where transaction_id=(select id from public.transaction where request_id='a1100000-0000-4000-8000-000000000101') and action='rejected'),1,'withdrawal rejection writes audit history');

select set_config('request.jwt.claim.sub','a1100000-0000-4000-8000-000000000001',true);
select is((public.create_financial_transaction('deposit',4000,'Beldex',null,'a1100000-0000-4000-8000-000000000104','BDX')).currency,'BDX'::text,'deposit request is BDX-denominated');
select set_config('request.jwt.claim.sub','a1100000-0000-4000-8000-000000000002',true);
select public.admin_approve_transaction((select id from public.transaction where request_id='a1100000-0000-4000-8000-000000000104'),'approve BDX deposit');
select is((public.admin_settle_transaction((select id from public.transaction where request_id='a1100000-0000-4000-8000-000000000104'),'settle BDX deposit')).status,'completed'::text,'approved BDX deposit settles');
select is((select bdx_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),14000::numeric,'settled BDX deposit credits the BDX wallet');
select is((select bdx_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000003'),200::numeric,'first completed BDX deposit credits exactly 5 percent to referrer');
select is(public.credit_referral_for_deposit((select id from public.transaction where request_id='a1100000-0000-4000-8000-000000000104')),0::numeric,'replaying referral credit is idempotent');

select * from finish();
rollback;
