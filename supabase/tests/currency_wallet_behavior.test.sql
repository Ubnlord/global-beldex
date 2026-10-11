begin;
create extension if not exists pgtap with schema extensions;

select plan(22);

-- Isolated identities and balances; transaction rollback leaves no fixture data.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a1100000-0000-4000-8000-000000000001','authenticated','authenticated','wallet-behavior-user@example.test','',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('a1100000-0000-4000-8000-000000000002','authenticated','authenticated','wallet-behavior-admin@example.test','',now(),'{}'::jsonb,'{}'::jsonb,now(),now())
on conflict (id) do nothing;

insert into public.user_profile(user_id,available_balance,bdx_balance)
values ('a1100000-0000-4000-8000-000000000001',1000,10000)
on conflict (user_id) do update set available_balance=1000,bdx_balance=10000;

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
  $$select public.create_financial_transaction('withdraw',4000,'Beldex','4' || repeat('A',94),'a1100000-0000-4000-8000-000000000101','USD')$$,
  'P0001','Request ID was already used for a different transaction',
  'P0001','Request ID was already used for a different transaction',
  'reusing a request ID with a different currency is rejected'
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

-- USD withdrawal reservation and completion leave BDX untouched.
select set_config('request.jwt.claim.sub','a1100000-0000-4000-8000-000000000001',true);
select public.create_financial_transaction('withdraw',300,'Bank','test destination','a1100000-0000-4000-8000-000000000102','USD');
select is(
  (select available_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  700::numeric,'USD withdrawal reserves from USD wallet'
);
select set_config('request.jwt.claim.sub','a1100000-0000-4000-8000-000000000002',true);
select public.admin_approve_transaction((select id from public.transaction where request_id='a1100000-0000-4000-8000-000000000102'),'test approval');
select is(
  (public.admin_settle_transaction((select id from public.transaction where request_id='a1100000-0000-4000-8000-000000000102'),'test settlement')).status,
  'completed'::text,'approved USD withdrawal settles'
);
select is(
  (select total_withdrawals from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  300::numeric,'USD withdrawal increments USD total'
);
select is(
  (select total_withdrawals_bdx from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  0::numeric,'USD withdrawal does not increment BDX total'
);

-- USD and BDX deposits settle to their own wallets and their own totals.
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
  750::numeric,'USD deposit credits only USD wallet'
);
select is(
  (select bdx_balance from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  10500::numeric,'BDX deposit credits only BDX wallet'
);
select is(
  (select total_deposits from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  50::numeric,'USD deposit increments legacy USD total'
);
select is(
  (select total_deposits_bdx from public.user_profile where user_id='a1100000-0000-4000-8000-000000000001'),
  500::numeric,'BDX deposit increments BDX-specific total'
);
select is(
  (select count(*)::integer from public.transaction where user_id='a1100000-0000-4000-8000-000000000001' and status='completed' and currency='BDX'),
  1,'completed BDX transactions remain identifiable in ledger history'
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

select * from finish();
rollback;
select throws_ok(
  $$select public.create_financial_transaction('withdraw',4000,'Beldex','4' || repeat('A',94),'a1100000-0000-4000-8000-000000000101','USD')$$,
  'P0001','Request ID was already used for a different transaction',
  'reusing a request ID with a different currency is rejected'
);