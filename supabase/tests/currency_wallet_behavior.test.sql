begin;
create extension if not exists pgtap with schema extensions;

select plan(38);

-- Isolated identities and balances; transaction rollback leaves no fixture data.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a1100000-0000-4000-8000-000000000001','authenticated','authenticated','wallet-behavior-user@example.test','',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('a1100000-0000-4000-8000-000000000002','authenticated','authenticated','wallet-behavior-admin@example.test','',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('a1100000-0000-4000-8000-000000000003','authenticated','authenticated','wallet-behavior-referrer@example.test','',now(),'{}'::jsonb,'{}'::jsonb,now(),now())
on conflict (id) do nothing;

insert into public.user_profile(user_id,available_balance,bdx_balance)
values ('a1100000-0000-4000-8000-000000000001',1000,10000)
on conflict (user_id) do update set available_balance=1000,bdx_balance=10000;

insert into public.user_profile(user_id,bdx_balance,referral_earnings_bdx)
values ('a1100000-0000-4000-8000-000000000003',0,0)
on conflict (user_id) do update set bdx_balance=0,referral_earnings_bdx=0;

update public.user_profile set referred_by_user_id='a1100000-0000-4000-8000-000000000003'
where user_id='a1100000-0000-4000-8000-000000000001';

insert into public.admin_user(user_id,role,permissions)
values ('a1100000-0000-4000-8000-000000000002','admin',array['approve_transactions','reject_transactions','manage_users'])
on conflict (user_id) do update set permissions=excluded.permissions;

-- BDX withdrawal reserves only BDX. Replaying the same request ID returns the
-- same transaction and does not reserve the balance twice.
select set_config('request.jwt.claim.sub','a1100000-0000-4000-8000-000000000001',true);
select is(
  (select bdx_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  10000::numeric,'initial BDX wallet fixture'
);
select is(
  (public.create_financial_transaction(
    'withdraw',4000,'Beldex',
    '4' || repeat('A',94),
    'a1100000-0000-4000-8000-000000000101','BDX'
  )).currency,
  'BDX'::text,'BDX withdrawal request is denominated in BDX'
);
select is(
  (select bdx_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  6000::numeric,'BDX withdrawal is reserved from BDX wallet'
);
select is(
  (public.create_financial_transaction('withdraw',4000,'Beldex','4' || repeat('A',94),'a1100000-0000-4000-8000-000000000101','BDX')).id,
  (select id from public.transaction where request_id='a1100000-0000-4000-8000-000000000101'),
  'duplicate request ID returns the original transaction'
);
select is(
  (select count(*)::integer from public.transaction where user_id='a1100000-0000-4000-8000-000000000001' and request_id='a1100000-0000-4000-8000-000000000101'),
  1,'duplicate request creates one ledger row'
);
select throws_ok(
  $$select public.create_financial_transaction('withdraw',4000,'Beldex','4' || repeat('A',94),'a1100000-0000-4000-8000-000000000101','USD')$$,
  'P0001','Request ID was already used for a different transaction',
  'reusing a request ID with a different currency is rejected'
);

select throws_ok(
  $$select public.create_financial_transaction('withdraw',4000,null,'4' || repeat('A',94),'a1100000-0000-4000-8000-000000000199','BDX')$$,
  'P0001','Invalid withdrawal method',
  'withdrawal RPC rejects a missing method'
);

-- Rejecting a pending withdrawal releases its reservation in the same currency.
select set_config('request.jwt.claim.sub','a1100000-0000-4000-8000-000000000002',true);
select is(
  (public.admin_reject_transaction((select id from public.transaction where request_id='a1100000-0000-4000-8000-000000000101'),'test rejection')).status,
  'failed'::text,'admin rejection marks withdrawal failed'
);
select is(
  (select bdx_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  10000::numeric,'rejection restores the BDX reservation'
);
select is(
  (select count(*)::integer from public.transaction_audit where transaction_id=(select id from public.transaction where request_id='a1100000-0000-4000-8000-000000000101') and action='rejected'),
  1,'rejection writes transaction audit history'
);

-- USD-input withdrawal is normalized to BDX and reserves only the BDX wallet.
select set_config('request.jwt.claim.sub','a1100000-0000-4000-8000-000000000001',true);
select public.create_financial_transaction('withdraw',300,'Beldex','4' || repeat('A',94),'a1100000-0000-4000-8000-000000000102','USD');
select is(
  (select currency from public.transaction where request_id='a1100000-0000-4000-8000-000000000102'),
  'BDX'::text,'USD withdrawal input is stored as BDX ledger currency'
);
select is(
  (select round(amount,3) from public.transaction where request_id='a1100000-0000-4000-8000-000000000102'),
  round(300/(293.984/4000),3),'USD input is converted using the documented platform rate'
);
select is(
  (select round(bdx_balance,3) from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  round(10000 - (300/(293.984/4000)),3),'USD input withdrawal reserves its BDX equivalent after the earlier reservation was released'
);

-- USD input deposits are normalized to BDX ledger amounts; all new credits land in BDX.
select set_config('request.jwt.claim.sub','a1100000-0000-4000-8000-000000000001',true);
select public.create_financial_transaction('deposit',50,'Bank',null,'a1100000-0000-4000-8000-000000000103','USD');
select public.create_financial_transaction('deposit',500,'Beldex',null,'a1100000-0000-4000-8000-000000000104','BDX');
select set_config('request.jwt.claim.sub','a1100000-0000-4000-8000-000000000002',true);
select public.admin_approve_transaction((select id from public.transaction where request_id='a1100000-0000-4000-8000-000000000103'),'approve USD deposit');
select public.admin_settle_transaction((select id from public.transaction where request_id='a1100000-0000-4000-8000-000000000103'),'settle USD deposit');
select public.admin_approve_transaction((select id from public.transaction where request_id='a1100000-0000-4000-8000-000000000104'),'approve BDX deposit');
select public.admin_settle_transaction((select id from public.transaction where request_id='a1100000-0000-4000-8000-000000000104'),'settle BDX deposit');
select is(
  (select available_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  1000::numeric,'USD-input deposit does not alter the pre-existing legacy USD wallet balance'
);
select is(
  (select round(bdx_balance,3) from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  round(10000 - (300/(293.984/4000)) + (50/(293.984/4000)) + 500,3),'USD-input and BDX deposits credit the BDX wallet'
);
select is(
  (select total_deposits from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  0::numeric,'USD-input deposit leaves legacy USD deposit total unchanged'
);
select is(
  (select round(total_deposits_bdx,3) from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  round((50/(293.984/4000)) + 500,3),'both new deposit inputs increment BDX-specific totals'
);
select is(
  (select count(*)::integer from public.transaction where user_id='a1100000-0000-4000-8000-000000000001' and status='completed' and currency='BDX'),
  2,'completed USD-input and BDX deposits are both identifiable as BDX ledger rows'
);
select is(
  (select deposits_delta from public.admin_financial_reconciliation_v2() where user_id='a1100000-0000-4000-8000-000000000001'),
  0::numeric,'USD deposit reconciliation compares USD totals to USD ledger only'
);
select is(
  (select deposits_bdx_delta from public.admin_financial_reconciliation_v2() where user_id='a1100000-0000-4000-8000-000000000001'),
  0::numeric,'BDX deposit reconciliation compares BDX totals to BDX ledger only'
);
select is(
  (select withdrawals_delta from public.admin_financial_reconciliation_v2() where user_id='a1100000-0000-4000-8000-000000000001'),
  0::numeric,'USD withdrawal reconciliation remains currency-correct'
);
select is(
  (select withdrawals_bdx_delta from public.admin_financial_reconciliation_v2() where user_id='a1100000-0000-4000-8000-000000000001'),
  0::numeric,'rejected BDX withdrawal is excluded from completed BDX withdrawal totals'
);
select is(
  (select bdx_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000003'),
  round((50/(293.984/4000) + 500)*0.10,18),'settled BDX-ledger deposits credit the referrer in BDX'
);
select is(
  (select referral_earnings_bdx from public.user_profile where user_id='a1100000-0000-4000-8000-000000000003'),
  round((50/(293.984/4000) + 500)*0.10,18),'referral earnings are recorded in the BDX-specific total'
);


-- Isolated admin-console RPC integration: funding is legacy USD, adjustment is BDX.
select set_config('request.jwt.claim.sub','a1100000-0000-4000-8000-000000000002',true);
select public.admin_fund_user(
  'a1100000-0000-4000-8000-000000000001'::uuid,
  125::numeric,
  'integration test legacy USD funding'::text,
  'integration-test-reference'::text
);
select is(
  (select available_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  1125::numeric,'admin_fund_user credits the legacy USD wallet'
);
select is(
  (select count(*)::integer from public.admin_action_audit
   where user_id='a1100000-0000-4000-8000-000000000001' and action='user_funded' and reason='integration test legacy USD funding'),
  1,'legacy USD funding creates an admin audit record'
);
select is(
  (select currency from public.transaction
   where user_id='a1100000-0000-4000-8000-000000000001' and method='Admin funding' and note like 'Admin funding: integration test legacy USD funding%'
   order by created_at desc limit 1),
  'USD'::text,'admin funding ledger entry is explicitly marked USD'
);
select is(
  (public.admin_adjust_balance('a1100000-0000-4000-8000-000000000001',250,'integration test BDX adjustment')).bdx_balance,
  round(10000 - (300/(293.984/4000)) + (50/(293.984/4000)) + 500 + 250,18),
  'admin_adjust_balance changes the BDX wallet only'
);
select is(
  (select available_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  1125::numeric,'BDX adjustment leaves legacy USD balance unchanged'
);
select is(
  (select count(*)::integer from public.admin_action_audit
   where user_id='a1100000-0000-4000-8000-000000000001' and action='adjust_bdx_balance' and reason='integration test BDX adjustment'),
  1,'BDX adjustment creates an admin audit record'
);
select throws_ok(
  $$select public.admin_adjust_balance('a1100000-0000-4000-8000-000000000001'::uuid,1::numeric,'ordinary user must be denied'::text)$$,
  'P0001','Permission denied','ordinary user cannot invoke admin BDX adjustment'
);

-- Blocked users cannot create financial requests; balances and ledger remain unchanged.
update public.user_profile set blocked=true
where user_id='a1100000-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub','a1100000-0000-4000-8000-000000000001',true);
select throws_ok(
  $$select public.create_financial_transaction('deposit',25::numeric,'Bank'::text,null::text,'a1100000-0000-4000-8000-000000000105'::uuid,'USD'::text)$$,
  'P0001','User account is blocked','blocked user cannot create a financial request'
);
select is(
  (select bdx_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  round(10000 - (300/(293.984/4000)) + (50/(293.984/4000)) + 500 + 250,18),
  'blocked financial request leaves BDX balance unchanged'
);
select is(
  (select count(*)::integer from public.transaction where user_id='a1100000-0000-4000-8000-000000000001' and request_id='a1100000-0000-4000-8000-000000000105'),
  0,'blocked financial request creates no ledger row'
);
update public.user_profile set blocked=false
where user_id='a1100000-0000-4000-8000-000000000001';

-- Approved legacy USD transactions cannot be settled through the BDX-only path.
insert into public.transaction(user_id,type,amount,status,approval_status,currency,method,note,approved_at)
values ('a1100000-0000-4000-8000-000000000001','deposit',75,'pending','approved','USD','Bank','legacy USD settlement safeguard fixture',now());
select set_config('request.jwt.claim.sub','a1100000-0000-4000-8000-000000000002',true);
select throws_ok(
  format('select public.admin_settle_transaction(%L::uuid,%L)',(select id from public.transaction where note='legacy USD settlement safeguard fixture'),'test legacy USD settlement denial'),
  'P0001','Legacy USD transaction requires manual reconciliation before settlement',
  'approved legacy USD transaction is refused by BDX settlement'
);
select is(
  (select available_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  1125::numeric,'legacy USD settlement denial leaves USD balance unchanged'
);
select is(
  (select count(*)::integer from public.transaction_audit where transaction_id=(select id from public.transaction where note='legacy USD settlement safeguard fixture') and action='settled'),
  0,'denied legacy USD settlement writes no successful settlement audit'
);
select is(
  (select status from public.transaction where note='legacy USD settlement safeguard fixture'),
  'pending'::text,'denied legacy USD settlement leaves transaction pending'
);

select * from finish();
rollback;