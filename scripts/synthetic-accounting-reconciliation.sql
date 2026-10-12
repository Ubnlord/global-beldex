-- Synthetic accounting reconciliation. Disposable local Supabase only.
-- Fabricated users/ledger only. Snapshot tables are TEMP and survive the migration's own COMMIT.
\set ON_ERROR_STOP on

insert into auth.users (id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('a4800000-0000-4000-8000-000000000001','authenticated','authenticated','synthetic-accounting-user@example.test','',now(),'{}','{}',now(),now()),
('a4800000-0000-4000-8000-000000000002','authenticated','authenticated','synthetic-accounting-referrer@example.test','',now(),'{}','{}',now(),now()),
('a4800000-0000-4000-8000-000000000003','authenticated','authenticated','synthetic-accounting-admin@example.test','',now(),'{}','{}',now(),now())
on conflict (id) do nothing;

insert into public.user_profile(user_id,available_balance,locked_balance,total_deposits,total_withdrawals,referral_earnings,bdx_balance,locked_bdx_balance,total_deposits_bdx,total_withdrawals_bdx,blocked)
values
('a4800000-0000-4000-8000-000000000001',810,200,1000,10,0,4500,1000,6000,500,false),
('a4800000-0000-4000-8000-000000000002',0,0,0,0,0,0,0,0,0,false),
('a4800000-0000-4000-8000-000000000003',0,0,0,0,0,0,0,0,0,false)
on conflict(user_id) do update set available_balance=excluded.available_balance,locked_balance=excluded.locked_balance,
 total_deposits=excluded.total_deposits,total_withdrawals=excluded.total_withdrawals,referral_earnings=excluded.referral_earnings,
 bdx_balance=excluded.bdx_balance,locked_bdx_balance=excluded.locked_bdx_balance,
 total_deposits_bdx=excluded.total_deposits_bdx,total_withdrawals_bdx=excluded.total_withdrawals_bdx,blocked=false;

update public.user_profile set referred_by_user_id='a4800000-0000-4000-8000-000000000002'
where user_id='a4800000-0000-4000-8000-000000000001';

insert into public.admin_user(user_id,role,permissions)
values('a4800000-0000-4000-8000-000000000003','admin',array['approve_transactions','reject_transactions','manage_users'])
on conflict(user_id) do update set role=excluded.role,permissions=excluded.permissions;

-- Historical fabricated USD and BDX flows reconcile to the two wallet balances.
insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note,created_at,settled_at) values
('a4800000-0000-4000-8000-000000000001','deposit',1000,'USD','completed','approved','Bank','synthetic legacy USD deposit',now()-interval '10 days',now()-interval '10 days'),
('a4800000-0000-4000-8000-000000000001','bonus',20,'USD','completed','approved','Daily interest','synthetic historical USD interest',now()-interval '9 days',now()-interval '9 days'),
('a4800000-0000-4000-8000-000000000001','withdraw',10,'USD','completed','approved','Bitcoin','synthetic historical USD withdrawal',now()-interval '8 days',now()-interval '8 days'),
('a4800000-0000-4000-8000-000000000001','plan',200,'USD','completed','approved','GNS','synthetic legacy USD investment',now()-interval '7 days',now()-interval '7 days'),
('a4800000-0000-4000-8000-000000000001','deposit',6000,'BDX','completed','approved','Beldex','synthetic historical BDX deposit',now()-interval '6 days',now()-interval '6 days'),
('a4800000-0000-4000-8000-000000000001','withdraw',500,'BDX','completed','approved','Beldex','synthetic historical BDX withdrawal',now()-interval '5 days',now()-interval '5 days'),
('a4800000-0000-4000-8000-000000000001','plan',1000,'BDX','completed','approved','GNS','synthetic BDX investment',now()-interval '4 days',now()-interval '4 days');

insert into public.user_investment(user_id,plan_id,principal,daily_rate,duration_days,started_at,last_accrual_at,credited_profit,status,currency,daily_accrual_enabled)
values
('a4800000-0000-4000-8000-000000000001','gns',200,0.000633333333333333,30,now()-interval '7 days',now()-interval '7 days',20,'active','USD',true),
('a4800000-0000-4000-8000-000000000001','gns',1000,0.019,30,now()-interval '4 days',now()-interval '4 days',0,'active','BDX',true);

create temporary table _acct_profile_before as
select user_id,available_balance,locked_balance,total_deposits,total_withdrawals,referral_earnings,
 bdx_balance,locked_bdx_balance,total_deposits_bdx,total_withdrawals_bdx,blocked,referred_by_user_id
from public.user_profile where user_id='a4800000-0000-4000-8000-000000000001';
create temporary table _acct_ledger_before as
select id,user_id,type,amount,currency,status,approval_status,method,note,request_id,created_at,settled_at
from public.transaction where user_id='a4800000-0000-4000-8000-000000000001';
create temporary table _acct_investments_before as
select id,user_id,plan_id,principal,daily_rate,duration_days,started_at,last_accrual_at,credited_profit,status,currency,daily_accrual_enabled,completed_at
from public.user_investment where user_id='a4800000-0000-4000-8000-000000000001';

do $seed_check$
begin
 if (select count(*) from _acct_ledger_before)<>7 or (select count(*) from _acct_investments_before)<>2 then
  raise exception 'synthetic seed mismatch: expected 7 ledger rows and 2 investments';
 end if;
end;
$seed_check$;

-- Validate per-account and aggregate opening equations before replay.
do $opening_reconciliation$
declare r record; v_available numeric; v_locked numeric; v_expected numeric; v_principal numeric;
 v_total_available numeric; v_total_expected numeric; v_total_locked numeric; v_total_principal numeric;
begin
 for r in select p.user_id,c.currency from public.user_profile p
   cross join (values('USD'::text),('BDX'::text)) c(currency)
   where p.user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002')
 loop
  if r.currency='USD' then
   select available_balance,locked_balance into v_available,v_locked from public.user_profile where user_id=r.user_id;
  else
   select bdx_balance,locked_bdx_balance into v_available,v_locked from public.user_profile where user_id=r.user_id;
  end if;
  select coalesce(sum(principal),0) into v_principal from public.user_investment
   where user_id=r.user_id and status='active' and currency=r.currency;
  select coalesce(sum(amount) filter(where type='deposit' and status='completed' and currency=r.currency),0)
   + coalesce(sum(amount) filter(where type in ('bonus','referral') and status='completed' and currency=r.currency),0)
   - coalesce(sum(amount) filter(where type='withdraw' and status='completed' and currency=r.currency),0)
   - v_principal into v_expected from public.transaction where user_id=r.user_id;
  if v_available<>v_expected or v_locked<>v_principal then
   raise exception 'opening % account equation failed for %: available %, expected %, locked %, principal %',
    r.currency,r.user_id,v_available,v_expected,v_locked,v_principal;
  end if;
 end loop;

 select sum(available_balance),sum(locked_balance) into v_total_available,v_total_locked
 from public.user_profile where user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002');
 select coalesce(sum(principal),0) into v_total_principal from public.user_investment
 where user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002') and status='active' and currency='USD';
 select coalesce(sum(amount) filter(where type='deposit' and status='completed' and currency='USD'),0)
  + coalesce(sum(amount) filter(where type in ('bonus','referral') and status='completed' and currency='USD'),0)
  - coalesce(sum(amount) filter(where type='withdraw' and status='completed' and currency='USD'),0)
  - v_total_principal into v_total_expected from public.transaction
  where user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002');
 if v_total_available<>v_total_expected or v_total_locked<>v_total_principal then
  raise exception 'opening aggregate USD equation failed: available %, expected %, locked %, principal %',v_total_available,v_total_expected,v_total_locked,v_total_principal;
 end if;

 select sum(bdx_balance),sum(locked_bdx_balance) into v_total_available,v_total_locked
 from public.user_profile where user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002');
 select coalesce(sum(principal),0) into v_total_principal from public.user_investment
 where user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002') and status='active' and currency='BDX';
 select coalesce(sum(amount) filter(where type='deposit' and status='completed' and currency='BDX'),0)
  + coalesce(sum(amount) filter(where type in ('bonus','referral') and status='completed' and currency='BDX'),0)
  - coalesce(sum(amount) filter(where type='withdraw' and status='completed' and currency='BDX'),0)
  - v_total_principal into v_total_expected from public.transaction
  where user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002');
 if v_total_available<>v_total_expected or v_total_locked<>v_total_principal then
  raise exception 'opening aggregate BDX equation failed: available %, expected %, locked %, principal %',v_total_available,v_total_expected,v_total_locked,v_total_principal;
 end if;
end;
$opening_reconciliation$;

\echo 'PASS: synthetic per-account and aggregate USD/BDX equations reconcile before migration replay'
\echo 'SNAPSHOT: fabricated profile wallets/totals, 7 historical ledger rows, and 2 investment snapshots captured'

\i ../supabase/migrations/20261011050000_bdx_native_accounting.sql

do $preservation$
begin
 if exists(select user_id,available_balance,locked_balance,total_deposits,total_withdrawals,referral_earnings,bdx_balance,locked_bdx_balance,total_deposits_bdx,total_withdrawals_bdx,blocked,referred_by_user_id from public.user_profile where user_id='a4800000-0000-4000-8000-000000000001' except select user_id,available_balance,locked_balance,total_deposits,total_withdrawals,referral_earnings,bdx_balance,locked_bdx_balance,total_deposits_bdx,total_withdrawals_bdx,blocked,referred_by_user_id from _acct_profile_before)
 or exists(select user_id,available_balance,locked_balance,total_deposits,total_withdrawals,referral_earnings,bdx_balance,locked_bdx_balance,total_deposits_bdx,total_withdrawals_bdx,blocked,referred_by_user_id from _acct_profile_before except select user_id,available_balance,locked_balance,total_deposits,total_withdrawals,referral_earnings,bdx_balance,locked_bdx_balance,total_deposits_bdx,total_withdrawals_bdx,blocked,referred_by_user_id from public.user_profile where user_id='a4800000-0000-4000-8000-000000000001')
 then raise exception 'migration changed synthetic legacy wallet/profile fields'; end if;
 if exists(select id,user_id,type,amount,currency,status,approval_status,method,note,request_id,created_at,settled_at from public.transaction where user_id='a4800000-0000-4000-8000-000000000001' except select id,user_id,type,amount,currency,status,approval_status,method,note,request_id,created_at,settled_at from _acct_ledger_before)
 or exists(select id,user_id,type,amount,currency,status,approval_status,method,note,request_id,created_at,settled_at from _acct_ledger_before except select id,user_id,type,amount,currency,status,approval_status,method,note,request_id,created_at,settled_at from public.transaction where user_id='a4800000-0000-4000-8000-000000000001')
 then raise exception 'migration changed or removed a historical synthetic ledger row'; end if;
 if exists(select id,user_id,plan_id,principal,daily_rate,duration_days,started_at,last_accrual_at,credited_profit,status,currency,daily_accrual_enabled,completed_at from public.user_investment where user_id='a4800000-0000-4000-8000-000000000001' except select id,user_id,plan_id,principal,daily_rate,duration_days,started_at,last_accrual_at,credited_profit,status,currency,daily_accrual_enabled,completed_at from _acct_investments_before)
 or exists(select id,user_id,plan_id,principal,daily_rate,duration_days,started_at,last_accrual_at,credited_profit,status,currency,daily_accrual_enabled,completed_at from _acct_investments_before except select id,user_id,plan_id,principal,daily_rate,duration_days,started_at,last_accrual_at,credited_profit,status,currency,daily_accrual_enabled,completed_at from public.user_investment where user_id='a4800000-0000-4000-8000-000000000001')
 then raise exception 'migration changed historical synthetic investment principal/rate/profit'; end if;
end;
$preservation$;
\echo 'PASS: migration replay preserved historical USD/BDX wallets, all 7 ledger rows, and both investment snapshots'

-- Request replay must not create duplicate rows or mutate either wallet before settlement.
select set_config('request.jwt.claim.sub','a4800000-0000-4000-8000-000000000001',false);
select public.create_financial_transaction('deposit',1000,'Beldex',null,'a4800000-0000-4000-8000-000000000101','BDX');
select public.create_financial_transaction('deposit',1000,'Beldex',null,'a4800000-0000-4000-8000-000000000101','BDX');
do $request_idempotency$
begin
 if (select count(*) from public.transaction where request_id='a4800000-0000-4000-8000-000000000101')<>1 then
  raise exception 'same request ID created multiple transaction rows';
 end if;
 if (select available_balance from public.user_profile where user_id='a4800000-0000-4000-8000-000000000001')<>810
  or (select bdx_balance from public.user_profile where user_id='a4800000-0000-4000-8000-000000000001')<>4500 then
  raise exception 'pending deposit changed a wallet before settlement';
 end if;
end;
$request_idempotency$;

-- BDX settlement credits only BDX, and referral credit is BDX-only and idempotent.
select set_config('request.jwt.claim.sub','a4800000-0000-4000-8000-000000000003',false);
select public.admin_approve_transaction((select id from public.transaction where request_id='a4800000-0000-4000-8000-000000000101'),'synthetic BDX approval');
select public.admin_settle_transaction((select id from public.transaction where request_id='a4800000-0000-4000-8000-000000000101'),'synthetic BDX settlement');
do $referral_currency$
begin
 if (select available_balance from public.user_profile where user_id='a4800000-0000-4000-8000-000000000001')<>810 then raise exception 'BDX settlement changed USD wallet'; end if;
 if (select bdx_balance from public.user_profile where user_id='a4800000-0000-4000-8000-000000000001')<>5500 then raise exception 'BDX deposit did not credit BDX wallet exactly once'; end if;
 if (select bdx_balance from public.user_profile where user_id='a4800000-0000-4000-8000-000000000002')<>100
  or (select referral_earnings_bdx from public.user_profile where user_id='a4800000-0000-4000-8000-000000000002')<>100 then
  raise exception 'referral credit/counter did not reconcile in BDX';
 end if;
 if public.credit_referral_for_deposit((select id from public.transaction where request_id='a4800000-0000-4000-8000-000000000101'))<>0 then
  raise exception 'referral credit replay should return zero';
 end if;
 if (select bdx_balance from public.user_profile where user_id='a4800000-0000-4000-8000-000000000002')<>100 then
  raise exception 'referral replay duplicated credit';
 end if;
end;
$referral_currency$;

-- BDX withdrawal reserves and then restores only the BDX wallet.
select set_config('request.jwt.claim.sub','a4800000-0000-4000-8000-000000000001',false);
select public.create_financial_transaction('withdraw',4000,'Beldex','4'||repeat('A',94),'a4800000-0000-4000-8000-000000000102','BDX');
do $bdx_reservation$
begin
 if (select bdx_balance from public.user_profile where user_id='a4800000-0000-4000-8000-000000000001')<>1500 then raise exception 'withdrawal did not reserve BDX'; end if;
 if (select available_balance from public.user_profile where user_id='a4800000-0000-4000-8000-000000000001')<>810 then raise exception 'BDX withdrawal changed USD'; end if;
end;
$bdx_reservation$;
select set_config('request.jwt.claim.sub','a4800000-0000-4000-8000-000000000003',false);
select public.admin_reject_transaction((select id from public.transaction where request_id='a4800000-0000-4000-8000-000000000102'),'synthetic BDX rejection');
do $bdx_release$
begin
 if (select bdx_balance from public.user_profile where user_id='a4800000-0000-4000-8000-000000000001')<>5500 then raise exception 'rejected withdrawal did not restore BDX'; end if;
 if (select available_balance from public.user_profile where user_id='a4800000-0000-4000-8000-000000000001')<>810 then raise exception 'rejected BDX withdrawal changed USD'; end if;
end;
$bdx_release$;

-- Admin funding is USD-only; unauthorized and blocked targets must fail closed.
select public.admin_fund_user('a4800000-0000-4000-8000-000000000001',125,'synthetic USD admin funding','synthetic-ref-1');
do $usd_funding$
begin
 if (select available_balance from public.user_profile where user_id='a4800000-0000-4000-8000-000000000001')<>935 then raise exception 'admin funding did not credit USD by 125'; end if;
 if (select bdx_balance from public.user_profile where user_id='a4800000-0000-4000-8000-000000000001')<>5500 then raise exception 'USD admin funding changed BDX'; end if;
 if (select count(*) from public.transaction where user_id='a4800000-0000-4000-8000-000000000001' and method='Admin funding' and currency='USD' and note like 'Admin funding: synthetic USD admin funding%')<>1 then
  raise exception 'USD funding ledger row missing or incorrectly denominated';
 end if;
end;
$usd_funding$;

select set_config('request.jwt.claim.sub','a4800000-0000-4000-8000-000000000001',false);
do $ordinary_user_denial$
begin
 begin
  perform public.admin_fund_user('a4800000-0000-4000-8000-000000000001',5,'ordinary user attempt',null);
  raise exception 'synthetic assertion failed: ordinary user invoked admin funding';
 exception when others then
  if sqlerrm like 'synthetic assertion failed:%' then raise; end if;
  if sqlerrm<>'Permission denied' then raise exception 'unexpected ordinary-user denial: %',sqlerrm; end if;
 end;
end;
$ordinary_user_denial$;

select set_config('request.jwt.claim.sub','a4800000-0000-4000-8000-000000000003',false);
update public.user_profile set blocked=true where user_id='a4800000-0000-4000-8000-000000000001';
do $blocked_target_denial$
begin
 begin
  perform public.admin_fund_user('a4800000-0000-4000-8000-000000000001',5,'blocked target attempt',null);
  raise exception 'synthetic assertion failed: blocked account received funding';
 exception when others then
  if sqlerrm like 'synthetic assertion failed:%' then raise; end if;
  if sqlerrm<>'User account is blocked' then raise exception 'unexpected blocked-account denial: %',sqlerrm; end if;
 end;
end;
$blocked_target_denial$;
update public.user_profile set blocked=false where user_id='a4800000-0000-4000-8000-000000000001';

-- Final per-account and aggregate equations, separately by denomination.
do $final_reconciliation$
declare r record; v_available numeric; v_locked numeric; v_expected numeric; v_principal numeric;
 v_total_available numeric; v_total_locked numeric; v_total_expected numeric; v_total_principal numeric;
begin
 for r in select p.user_id,c.currency from public.user_profile p
  cross join (values('USD'::text),('BDX'::text)) c(currency)
  where p.user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002')
 loop
  if r.currency='USD' then select available_balance,locked_balance into v_available,v_locked from public.user_profile where user_id=r.user_id;
  else select bdx_balance,locked_bdx_balance into v_available,v_locked from public.user_profile where user_id=r.user_id; end if;
  select coalesce(sum(principal),0) into v_principal from public.user_investment where user_id=r.user_id and status='active' and currency=r.currency;
  select coalesce(sum(amount) filter(where type='deposit' and status='completed' and currency=r.currency),0)
   + coalesce(sum(amount) filter(where type in ('bonus','referral') and status='completed' and currency=r.currency),0)
   - coalesce(sum(amount) filter(where type='withdraw' and status='completed' and currency=r.currency),0)
   - v_principal into v_expected from public.transaction where user_id=r.user_id;
  if v_available<>v_expected or v_locked<>v_principal then
   raise exception 'final per-account % reconciliation failed for %: available %, expected %, locked %, principal %',r.currency,r.user_id,v_available,v_expected,v_locked,v_principal;
  end if;
 end loop;

 select sum(available_balance),sum(locked_balance) into v_total_available,v_total_locked from public.user_profile
 where user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002');
 select coalesce(sum(principal),0) into v_total_principal from public.user_investment where user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002') and status='active' and currency='USD';
 select coalesce(sum(amount) filter(where type='deposit' and status='completed' and currency='USD'),0)
  + coalesce(sum(amount) filter(where type in ('bonus','referral') and status='completed' and currency='USD'),0)
  - coalesce(sum(amount) filter(where type='withdraw' and status='completed' and currency='USD'),0)
  - v_total_principal into v_total_expected from public.transaction where user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002');
 if v_total_available<>v_total_expected or v_total_locked<>v_total_principal then raise exception 'final aggregate USD reconciliation failed'; end if;

 select sum(bdx_balance),sum(locked_bdx_balance) into v_total_available,v_total_locked from public.user_profile
 where user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002');
 select coalesce(sum(principal),0) into v_total_principal from public.user_investment where user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002') and status='active' and currency='BDX';
 select coalesce(sum(amount) filter(where type='deposit' and status='completed' and currency='BDX'),0)
  + coalesce(sum(amount) filter(where type in ('bonus','referral') and status='completed' and currency='BDX'),0)
  - coalesce(sum(amount) filter(where type='withdraw' and status='completed' and currency='BDX'),0)
  - v_total_principal into v_total_expected from public.transaction where user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002');
 if v_total_available<>v_total_expected or v_total_locked<>v_total_principal then raise exception 'final aggregate BDX reconciliation failed'; end if;
end;
$final_reconciliation$;

\echo 'PASS: synthetic per-account and aggregate USD/BDX equations reconcile after migration and RPC operations'
\echo 'PASS: historical snapshots preserved; referral replay idempotent; BDX withdrawal isolated; USD funding isolated; unauthorized/blocked funding denied'

-- Cleanup only fabricated records and their dependent audit rows. Workflow database is disposable.
delete from public.admin_action_audit where user_id in (
 'a4800000-0000-4000-8000-000000000001',
 'a4800000-0000-4000-8000-000000000002',
 'a4800000-0000-4000-8000-000000000003'
);
delete from public.transaction_audit where transaction_id in (
 select id from public.transaction where user_id in (
  'a4800000-0000-4000-8000-000000000001',
  'a4800000-0000-4000-8000-000000000002'
 )
);
delete from public.transaction where user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002');
delete from public.user_investment where user_id='a4800000-0000-4000-8000-000000000001';
delete from public.admin_user where user_id='a4800000-0000-4000-8000-000000000003';
delete from public.user_profile where user_id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002','a4800000-0000-4000-8000-000000000003');
delete from auth.users where id in ('a4800000-0000-4000-8000-000000000001','a4800000-0000-4000-8000-000000000002','a4800000-0000-4000-8000-000000000003');
