begin;
create extension if not exists pgtap with schema extensions;

-- Test-only RPC prototype. This file is not under supabase/migrations and
-- creates no persistent public objects. It deliberately models a one-time
-- account conversion in temporary tables; production integration is prohibited
-- until schema mapping, multi-session concurrency, and accounting review pass.
select plan(23);

create temporary table sim_profile (
  user_id text primary key,
  available_usd numeric(38,18) not null,
  locked_usd numeric(38,18) not null,
  referral_usd numeric(38,18) not null,
  available_bdx numeric(38,18) not null,
  locked_bdx numeric(38,18) not null,
  referral_bdx numeric(38,18) not null
) on commit drop;
create temporary table sim_investment (
  id text primary key, user_id text not null, currency text not null,
  status text not null, principal numeric(38,18) not null,
  credited_profit numeric(38,18) not null
) on commit drop;
create temporary table sim_history (
  id text primary key, user_id text not null, currency text not null,
  amount numeric(38,18) not null
) on commit drop;
create temporary table sim_conversion_run (
  conversion_id uuid primary key, user_id text not null unique,
  quote_usd_per_bdx numeric(38,18) not null,
  quote_source text not null, provider_at timestamptz,
  observed_at timestamptz not null, completed_at timestamptz not null default now()
) on commit drop;
create temporary table sim_conversion_map (
  conversion_id uuid not null, record_kind text not null, record_id text not null,
  source_currency text not null, source_amount numeric(38,18) not null,
  target_amount numeric(38,18) not null, rounding_remainder numeric(38,18) not null,
  primary key(conversion_id,record_kind,record_id)
) on commit drop;

insert into sim_profile values
 ('account-a',125,250,5,10,20,1),('account-b',40,0,0,0,0,0);
insert into sim_investment values
 ('active-a','account-a','USD','active',200,12.5),
 ('completed-a','account-a','USD','completed',50,7.25),
 ('native-bdx','account-a','BDX','active',300,4);
insert into sim_history values
 ('old-usd','account-a','USD',75),('old-bdx','account-a','BDX',125);

create function pg_temp.convert_account_once(
 p_conversion_id uuid, p_user_id text, p_quote numeric,
 p_source text, p_provider_at timestamptz, p_observed_at timestamptz,
 p_fail_after_wallet boolean default false
) returns text language plpgsql as $rpc$
declare
 v_run sim_conversion_run%rowtype;
 v_profile sim_profile%rowtype;
 v_rows integer;
 v_investment sim_investment%rowtype;
 v_usd numeric;
 v_bdx numeric;
begin
 if p_conversion_id is null or p_user_id is null then raise exception 'Missing conversion identity'; end if;
 if p_quote is null or p_quote<=0 or p_quote::text in ('NaN','Infinity','-Infinity') then raise exception 'Invalid quote'; end if;
 if p_source not in ('coingecko','kucoin','dexscreener') then raise exception 'Unapproved quote source'; end if;
 if p_observed_at is null or p_observed_at < now()-interval '2 minutes' or p_observed_at > now()+interval '10 seconds' then raise exception 'Stale quote'; end if;
 if p_provider_at is not null and (p_provider_at > p_observed_at+interval '10 seconds' or p_provider_at < p_observed_at-interval '2 minutes') then raise exception 'Provider quote timestamp out of policy'; end if;

 -- Serialize all attempts for the same account, including distinct run IDs.
 perform pg_advisory_xact_lock(hashtextextended(p_user_id, 741109));
 select * into v_run from sim_conversion_run where user_id=p_user_id;
 if found then
   if v_run.conversion_id=p_conversion_id then return 'already_converted'; end if;
   raise exception 'Account already converted by another run';
 end if;

 select * into v_profile from sim_profile where user_id=p_user_id for update;
 if not found then raise exception 'Account not found'; end if;
 if v_profile.available_usd<0 or v_profile.locked_usd<0 or v_profile.referral_usd<0 then raise exception 'Negative USD source balance'; end if;

 insert into sim_conversion_run(conversion_id,user_id,quote_usd_per_bdx,quote_source,provider_at,observed_at)
 values(p_conversion_id,p_user_id,p_quote,p_source,p_provider_at,p_observed_at);

 insert into sim_conversion_map
 select p_conversion_id,'wallet_available',p_user_id,'USD',available_usd,
   round(available_usd/p_quote,18),available_usd-round(round(available_usd/p_quote,18)*p_quote,18)
 from sim_profile where user_id=p_user_id and available_usd<>0;
 insert into sim_conversion_map
 select p_conversion_id,'wallet_locked',p_user_id,'USD',locked_usd,
   round(locked_usd/p_quote,18),locked_usd-round(round(locked_usd/p_quote,18)*p_quote,18)
 from sim_profile where user_id=p_user_id and locked_usd<>0;
 insert into sim_conversion_map
 select p_conversion_id,'referral',p_user_id,'USD',referral_usd,
   round(referral_usd/p_quote,18),referral_usd-round(round(referral_usd/p_quote,18)*p_quote,18)
 from sim_profile where user_id=p_user_id and referral_usd<>0;

 update sim_profile set
   available_bdx=available_bdx+round(available_usd/p_quote,18),
   locked_bdx=locked_bdx+round(locked_usd/p_quote,18),
   referral_bdx=referral_bdx+round(referral_usd/p_quote,18),
   available_usd=0,locked_usd=0,referral_usd=0
 where user_id=p_user_id;

 if p_fail_after_wallet then raise exception 'forced conversion failure'; end if;

 -- Convert active USD investments only. Completed investments remain historical
 -- USD facts. Active principal and already-credited profit are separately mapped.
 for v_investment in select * from sim_investment
   where user_id=p_user_id and currency='USD' and status='active' for update
 loop
   insert into sim_conversion_map values
    (p_conversion_id,'active_investment_principal',v_investment.id,'USD',v_investment.principal,
     round(v_investment.principal/p_quote,18),
     v_investment.principal-round(round(v_investment.principal/p_quote,18)*p_quote,18));
   if v_investment.credited_profit<>0 then
     insert into sim_conversion_map values
      (p_conversion_id,'credited_profit',v_investment.id,'USD',v_investment.credited_profit,
       round(v_investment.credited_profit/p_quote,18),
       v_investment.credited_profit-round(round(v_investment.credited_profit/p_quote,18)*p_quote,18));
   end if;
   update sim_investment set principal=round(principal/p_quote,18),
     credited_profit=round(credited_profit/p_quote,18),currency='BDX'
   where id=v_investment.id;
 end loop;

 -- Historical transaction records are intentionally immutable.
 return 'converted';
end;
$rpc$;

select is(pg_temp.convert_account_once('a0000000-0000-4000-8000-000000000001','account-a',0.1,'coingecko',now(),now()),'converted','fresh quote converts the account once');
select is((select available_usd from sim_profile where user_id='account-a'),0::numeric,'USD available balance is cleared only after mapping');
select is((select available_bdx from sim_profile where user_id='account-a'),1260::numeric,'available BDX includes pre-existing BDX plus converted USD');
select is((select locked_bdx from sim_profile where user_id='account-a'),2520::numeric,'locked BDX includes converted locked USD');
select is((select referral_bdx from sim_profile where user_id='account-a'),51::numeric,'referral value remains in its separate BDX bucket');
select is((select principal from sim_investment where id='active-a'),2000::numeric,'active investment principal converted');
select is((select credited_profit from sim_investment where id='active-a'),125::numeric,'credited profit converted exactly once');
select is((select currency from sim_investment where id='completed-a'),'USD','completed investment remains historical USD');
select is((select principal from sim_investment where id='native-bdx'),300::numeric,'native BDX investment unchanged');
select is((select amount from sim_history where id='old-usd'),75::numeric,'historical transaction amount unchanged');
select is((select currency from sim_history where id='old-usd'),'USD','historical transaction denomination unchanged');
select ok((select count(*)=5 from sim_conversion_map where conversion_id='a0000000-0000-4000-8000-000000000001'),'source-to-target mapping and rounding remainders recorded');
select is(pg_temp.convert_account_once('a0000000-0000-4000-8000-000000000001','account-a',0.1,'coingecko',now(),now()),'already_converted','same conversion ID retry does not credit twice');
select throws_ok($$select pg_temp.convert_account_once('a0000000-0000-4000-8000-000000000002','account-a',0.1,'coingecko',now(),now())$$,'P0001','Account already converted by another run','second run cannot reconvert account');
select throws_ok($$select pg_temp.convert_account_once('a0000000-0000-4000-8000-000000000003','account-b',0,'coingecko',now(),now())$$,'P0001','Invalid quote','invalid quote is rejected');
select throws_ok($$select pg_temp.convert_account_once('a0000000-0000-4000-8000-000000000004','account-b',0.1,'coingecko',now()-interval '5 minutes',now()-interval '5 minutes')$$,'P0001','Stale quote','stale quote is rejected');
select throws_ok($$select pg_temp.convert_account_once('a0000000-0000-4000-8000-000000000005','account-b',0.1,'coingecko',now(),now(),true)$$,'P0001','forced conversion failure','mid-conversion error aborts the statement');
select is((select available_usd from sim_profile where user_id='account-b'),40::numeric,'failed conversion preserves source USD balance');
select is((select available_bdx from sim_profile where user_id='account-b'),0::numeric,'failed conversion leaves destination BDX unchanged');
select is((select count(*)::integer from sim_conversion_run where conversion_id='a0000000-0000-4000-8000-000000000005'),0,'failed conversion leaves no conversion-run marker');
select is((select count(*)::integer from sim_conversion_map where conversion_id='a0000000-0000-4000-8000-000000000005'),0,'failed conversion leaves no partial audit mapping');
select is((select sum(source_amount) from sim_conversion_map where conversion_id='a0000000-0000-4000-8000-000000000001'),592.5::numeric,'per-account source mapping reconciles to all converted USD categories');
select is((select sum(target_amount)*0.1+sum(rounding_remainder) from sim_conversion_map where conversion_id='a0000000-0000-4000-8000-000000000001'),592.5::numeric,'destination BDX value plus recorded rounding remainder reconciles to source USD');

select * from finish();
rollback;
