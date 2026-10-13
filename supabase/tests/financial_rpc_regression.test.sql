begin;
create extension if not exists pgtap with schema extensions;
select plan(30);

-- Disposable rows only. The test suite is run against the isolated local
-- Supabase database; no production account or transaction is referenced.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a3100000-0000-4000-8000-000000000001','authenticated','authenticated',
  'rpc-regression-admin@example.test','',now(),'{}'::jsonb,'{}'::jsonb,now(),now()
), (
  'a3100000-0000-4000-8000-000000000002','authenticated','authenticated',
  'rpc-regression-user@example.test','',now(),'{}'::jsonb,'{}'::jsonb,now(),now()
) on conflict (id) do nothing;

insert into public.user_profile(user_id,available_balance,locked_balance,bdx_balance,locked_bdx_balance,blocked)
values ('a3100000-0000-4000-8000-000000000002',100,100,200,200,false)
on conflict (user_id) do update set
  available_balance=100,locked_balance=100,bdx_balance=200,locked_bdx_balance=200,blocked=false;

insert into public.admin_user(user_id,role,permissions)
values ('a3100000-0000-4000-8000-000000000001','admin',array['manage_users','approve_transactions','reject_transactions']::text[])
on conflict (user_id) do update set role='admin',permissions=array['manage_users','approve_transactions','reject_transactions']::text[];

insert into public.user_investment(id,user_id,plan_id,principal,daily_rate,duration_days,status,currency)
values
 ('a3100000-0000-4000-8000-000000000011','a3100000-0000-4000-8000-000000000002','gns',100,0.01,30,'active','USD'),
 ('a3100000-0000-4000-8000-000000000012','a3100000-0000-4000-8000-000000000002','gns',200,0.01,30,'active','BDX')
on conflict (id) do update set status='active',currency=excluded.currency,principal=excluded.principal;

select set_config('request.jwt.claim.sub','a3100000-0000-4000-8000-000000000001',true);

select is((public.admin_manage_investment('a3100000-0000-4000-8000-000000000011',0.01,'completed','USD currency regression')).status,
  'completed'::text,'USD investment can be completed');
select is((select available_balance from public.user_profile where user_id='a3100000-0000-4000-8000-000000000002'),
  200::numeric,'USD principal returns to USD available wallet');
select is((select locked_balance from public.user_profile where user_id='a3100000-0000-4000-8000-000000000002'),
  0::numeric,'USD principal leaves USD locked wallet');

select is((public.admin_manage_investment('a3100000-0000-4000-8000-000000000012',0.01,'completed','BDX currency regression')).status,
  'completed'::text,'BDX investment can be completed');
select is((select bdx_balance from public.user_profile where user_id='a3100000-0000-4000-8000-000000000002'),
  400::numeric,'BDX principal returns to BDX available wallet');
select is((select locked_bdx_balance from public.user_profile where user_id='a3100000-0000-4000-8000-000000000002'),
  0::numeric,'BDX principal leaves BDX locked wallet');

select is((public.admin_manage_investment('a3100000-0000-4000-8000-000000000011',0.01,'active','USD reactivation regression')).status,
  'active'::text,'USD investment can be reactivated');
select is((select available_balance from public.user_profile where user_id='a3100000-0000-4000-8000-000000000002'),
  100::numeric,'USD principal is debited from USD available wallet on reactivation');
select is((select locked_balance from public.user_profile where user_id='a3100000-0000-4000-8000-000000000002'),
  100::numeric,'USD principal returns to USD locked wallet on reactivation');

select is((public.admin_manage_investment('a3100000-0000-4000-8000-000000000012',0.01,'active','BDX reactivation regression')).status,
  'active'::text,'BDX investment can be reactivated');
select is((select bdx_balance from public.user_profile where user_id='a3100000-0000-4000-8000-000000000002'),
  200::numeric,'BDX principal is debited from BDX available wallet on reactivation');
select is((select locked_bdx_balance from public.user_profile where user_id='a3100000-0000-4000-8000-000000000002'),
  200::numeric,'BDX principal returns to BDX locked wallet on reactivation');

-- Negative authorization and currency-matched principal safeguards. Each exception
-- is caught by pgTAP; no production account or data is involved.
select set_config('request.jwt.claim.sub','a3100000-0000-4000-8000-000000000002',true);
select throws_ok(
  $$select public.admin_manage_investment('a3100000-0000-4000-8000-000000000011',0.01,'completed','non-admin regression')$$,
  'P0001','not authorized',
  'ordinary authenticated user cannot manage investments'
);
select set_config('request.jwt.claim.sub','a3100000-0000-4000-8000-000000000001',true);

update public.admin_user set permissions=array[]::text[]
where user_id='a3100000-0000-4000-8000-000000000001';
select throws_ok(
  $$select public.admin_manage_investment('a3100000-0000-4000-8000-000000000011',0.01,'completed','wrong permission regression')$$,
  'P0001','not authorized',
  'admin without manage_users permission cannot manage investments'
);
update public.admin_user set permissions=array['manage_users']::text[]
where user_id='a3100000-0000-4000-8000-000000000001';

update public.user_profile set blocked=true
where user_id='a3100000-0000-4000-8000-000000000002';
select throws_ok(
  $$select public.admin_manage_investment('a3100000-0000-4000-8000-000000000011',0.01,'completed','blocked account regression')$$,
  'P0001','blocked user cannot have investment managed',
  'blocked account investment mutation is rejected'
);
update public.user_profile set blocked=false
where user_id='a3100000-0000-4000-8000-000000000002';

update public.user_profile set locked_balance=99
where user_id='a3100000-0000-4000-8000-000000000002';
select throws_ok(
  $$select public.admin_manage_investment('a3100000-0000-4000-8000-000000000011',0.01,'completed','insufficient USD lock regression')$$,
  'P0001','locked balance is below investment principal',
  'USD completion rejects insufficient USD locked balance'
);
update public.user_profile set locked_balance=100
where user_id='a3100000-0000-4000-8000-000000000002';

update public.user_profile set locked_bdx_balance=199
where user_id='a3100000-0000-4000-8000-000000000002';
select throws_ok(
  $$select public.admin_manage_investment('a3100000-0000-4000-8000-000000000012',0.01,'completed','insufficient BDX lock regression')$$,
  'P0001','locked balance is below investment principal',
  'BDX completion rejects insufficient BDX locked balance'
);
update public.user_profile set locked_bdx_balance=200
where user_id='a3100000-0000-4000-8000-000000000002';

-- Legacy five-argument calls now resolve to the currency-aware function because
-- the unsafe five-argument overload has been dropped and the six-argument RPC
-- provides a default currency. Reusing a request ID with changed inputs must fail.
select set_config('request.jwt.claim.sub','a3100000-0000-4000-8000-000000000002',true);
select ok(
  (select count(*)=1 from (
    select (public.create_financial_transaction('deposit',25,'test','first request',
      'a3100000-0000-4000-8000-000000000099'::uuid)).id
  ) created),
  'five-argument legacy call reaches the currency-aware transaction RPC'
);
select is(
  (public.create_financial_transaction('deposit',25,'legacy-retry','retry with another plain-text note',
    'a3100000-0000-4000-8000-000000000099'::uuid)).id,
  (select id from public.transaction where user_id='a3100000-0000-4000-8000-000000000002'
    and request_id='a3100000-0000-4000-8000-000000000099'::uuid),
  'legacy plain-text note retry returns the original matching transaction'
);
select throws_ok(
  $$select public.create_financial_transaction('deposit',26,'test','changed amount',
    'a3100000-0000-4000-8000-000000000099'::uuid)$$,
  'P0001','Request ID was already used for a different transaction',
  'reused request ID with a different amount is rejected'
);
select throws_ok(
  $$select public.create_financial_transaction('withdraw',25,'test','changed type',
    'a3100000-0000-4000-8000-000000000099'::uuid)$$,
  'P0001','Request ID was already used for a different transaction',
  'reused request ID with a different type is rejected'
);


select ok(
  to_regprocedure('public.create_financial_transaction(text,numeric,text,text,uuid)') is null,
  'unsafe five-argument overload is not callable as a distinct function'
);
select throws_ok(
  $$select public.create_financial_transaction('withdraw',31,'test','six arg changed type',
    'a3100000-0000-4000-8000-000000000098'::uuid,'USD')$$,
  'P0001','Request ID was already used for a different transaction',
  'six-argument overload rejects a conflicting transaction type retry'
);

-- Six-argument overload must reject conflicting retries independently of the
-- legacy five-argument call (which resolves to this function after migration).
select is(
  (public.create_financial_transaction('deposit',31,'test','six arg original',
    'a3100000-0000-4000-8000-000000000098'::uuid,'USD')).amount,
  31::numeric,
  'six-argument transaction request is created'
);
select throws_ok(
  $$select public.create_financial_transaction('deposit',32,'test','six arg changed amount',
    'a3100000-0000-4000-8000-000000000098'::uuid,'USD')$$,
  'P0001','Request ID was already used for a different transaction',
  'six-argument overload rejects a conflicting amount retry'
);
select throws_ok(
  $$select public.create_financial_transaction('deposit',31,'test','six arg changed currency',
    'a3100000-0000-4000-8000-000000000098'::uuid,'BDX')$$,
  'P0001','Request ID was already used for a different transaction',
  'six-argument overload rejects a conflicting currency retry'
);

-- The published plan catalog daily rate is the cap; no arbitrary global rate
-- is introduced. Blocked users may not have investment parameters modified.
select throws_ok(
  $$select public.admin_update_investment('a3100000-0000-4000-8000-000000000011',1.0,true)$$,
  'P0001','Daily rate exceeds published plan rate',
  'investment rate cannot exceed its published plan rate'
);

-- Restore the settlement permission after the manage_users-only investment checks.
update public.admin_user set permissions=array['manage_users','approve_transactions']::text[]
where user_id='a3100000-0000-4000-8000-000000000001';

-- Settlement requires a pending source state, even when approval_status is
-- accidentally/legacy marked approved. These fixtures are isolated.
insert into public.transaction(id,user_id,type,amount,currency,status,approval_status,method,note)
values
 ('a3100000-0000-4000-8000-000000000051','a3100000-0000-4000-8000-000000000002','deposit',10,'USD','failed','approved','test','failed approved legacy row'),
 ('a3100000-0000-4000-8000-000000000052','a3100000-0000-4000-8000-000000000002','deposit',11,'USD','failed','rejected','test','rejected legacy row'),
 ('a3100000-0000-4000-8000-000000000053','a3100000-0000-4000-8000-000000000002','deposit',12,'USD','pending','approved','test','blocked target deposit');
select throws_ok(
  $$select public.admin_settle_transaction('a3100000-0000-4000-8000-000000000051','regression')$$,
  'P0001','Transaction must be pending to settle',
  'failed transaction cannot be settled even if marked approved'
);
select throws_ok(
  $$select public.admin_settle_transaction('a3100000-0000-4000-8000-000000000052','regression')$$,
  'P0001','Transaction must be pending to settle',
  'rejected transaction cannot be settled'
);
update public.user_profile set blocked=true where user_id='a3100000-0000-4000-8000-000000000002';
select throws_ok(
  $$select public.admin_settle_transaction('a3100000-0000-4000-8000-000000000053','regression')$$,
  'P0001','Blocked account cannot receive a deposit',
  'blocked account cannot receive a pending deposit settlement'
);
update public.user_profile set blocked=false where user_id='a3100000-0000-4000-8000-000000000002';

select * from finish();
rollback;
