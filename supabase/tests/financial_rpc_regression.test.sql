begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

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
values ('a3100000-0000-4000-8000-000000000001','admin',array['manage_users']::text[])
on conflict (user_id) do update set role='admin',permissions=array['manage_users']::text[];

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
  $select public.admin_manage_investment('a3100000-0000-4000-8000-000000000011',0.01,'completed','non-admin regression')$,
  'P0001','not authorized',
  'ordinary authenticated user cannot manage investments'
);
select set_config('request.jwt.claim.sub','a3100000-0000-4000-8000-000000000001',true);

update public.admin_user set permissions=array[]::text[]
where user_id='a3100000-0000-4000-8000-000000000001';
select throws_ok(
  $select public.admin_manage_investment('a3100000-0000-4000-8000-000000000011',0.01,'completed','wrong permission regression')$,
  'P0001','not authorized',
  'admin without manage_users permission cannot manage investments'
);
update public.admin_user set permissions=array['manage_users']::text[]
where user_id='a3100000-0000-4000-8000-000000000001';

update public.user_profile set blocked=true
where user_id='a3100000-0000-4000-8000-000000000002';
select throws_ok(
  $select public.admin_manage_investment('a3100000-0000-4000-8000-000000000011',0.01,'completed','blocked account regression')$,
  'P0001','blocked user cannot have investment managed',
  'blocked account investment mutation is rejected'
);
update public.user_profile set blocked=false
where user_id='a3100000-0000-4000-8000-000000000002';

update public.user_profile set locked_balance=99
where user_id='a3100000-0000-4000-8000-000000000002';
select throws_ok(
  $select public.admin_manage_investment('a3100000-0000-4000-8000-000000000011',0.01,'completed','insufficient USD lock regression')$,
  'P0001','locked balance is below investment principal',
  'USD completion rejects insufficient USD locked balance'
);
update public.user_profile set locked_balance=100
where user_id='a3100000-0000-4000-8000-000000000002';

update public.user_profile set locked_bdx_balance=199
where user_id='a3100000-0000-4000-8000-000000000002';
select throws_ok(
  $select public.admin_manage_investment('a3100000-0000-4000-8000-000000000012',0.01,'completed','insufficient BDX lock regression')$,
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

select * from finish();
rollback;
