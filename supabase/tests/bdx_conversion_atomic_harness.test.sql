begin;
create extension if not exists pgtap with schema extensions;

-- Fully disposable model harness. All objects are TEMPORARY and the enclosing
-- transaction is rolled back. This tests transaction semantics only; it does
-- not install or call a production conversion RPC.
select plan(19);

create temporary table sim_wallet (
  user_id text primary key,
  available_usd numeric not null,
  locked_usd numeric not null,
  available_bdx numeric not null default 0,
  locked_bdx numeric not null default 0,
  referral_usd numeric not null default 0,
  referral_bdx numeric not null default 0
) on commit drop;

create temporary table sim_investment (
  investment_id text primary key,
  user_id text not null,
  currency text not null,
  status text not null,
  principal numeric not null,
  credited_profit numeric not null
) on commit drop;

create temporary table sim_transaction (
  transaction_id text primary key,
  user_id text not null,
  currency text not null,
  amount numeric not null,
  status text not null,
  created_at timestamptz not null
) on commit drop;

create temporary table sim_conversion_run (
  conversion_id text primary key,
  quote_price numeric not null,
  quote_source text not null,
  quote_at timestamptz not null,
  completed_at timestamptz not null default now()
) on commit drop;

create temporary table sim_audit (
  conversion_id text not null,
  record_type text not null,
  record_id text not null,
  original_currency text not null,
  original_amount numeric not null,
  primary key (conversion_id, record_type, record_id)
) on commit drop;

insert into sim_wallet values
  ('user-a', 125.00, 250.00, 10.00, 20.00, 5.00, 1.00),
  ('user-b', 0.00, 40.00, 0.00, 0.00, 0.00, 0.00);

insert into sim_investment values
  ('inv-active','user-a','USD','active',200.00,12.50),
  ('inv-completed','user-a','USD','completed',50.00,7.25),
  ('inv-bdx','user-a','BDX','active',300.00,4.00);

insert into sim_transaction values
  ('tx-old-usd','user-a','USD',75.00,'completed','2025-01-01T00:00:00Z'),
  ('tx-old-bdx','user-a','BDX',125.00,'completed','2025-02-01T00:00:00Z');

create function pg_temp.simulate_atomic_conversion(
  p_conversion_id text,
  p_usd_per_bdx numeric,
  p_quote_source text,
  p_quote_at timestamptz,
  p_fail_after_wallet boolean default false
) returns integer
language plpgsql
as $fn$
declare
  v_existing integer;
  v_count integer := 0;
begin
  if p_usd_per_bdx is null or p_usd_per_bdx <= 0
     or p_quote_source not in ('coingecko','kucoin','dexscreener')
     or p_quote_at is null
     or p_quote_at < now() - interval '2 minutes'
     or p_quote_at > now() + interval '10 seconds' then
    raise exception 'Invalid or stale conversion quote';
  end if;

  select count(*) into v_existing from sim_conversion_run
  where conversion_id = p_conversion_id;
  if v_existing > 0 then
    return 0;
  end if;

  insert into sim_conversion_run(conversion_id,quote_price,quote_source,quote_at)
  values (p_conversion_id,p_usd_per_bdx,p_quote_source,p_quote_at);

  insert into sim_audit(conversion_id,record_type,record_id,original_currency,original_amount)
  select p_conversion_id,'wallet_available',user_id,'USD',available_usd
  from sim_wallet where available_usd <> 0;
  insert into sim_audit(conversion_id,record_type,record_id,original_currency,original_amount)
  select p_conversion_id,'wallet_locked',user_id,'USD',locked_usd
  from sim_wallet where locked_usd <> 0;
  insert into sim_audit(conversion_id,record_type,record_id,original_currency,original_amount)
  select p_conversion_id,'referral',user_id,'USD',referral_usd
  from sim_wallet where referral_usd <> 0;
  insert into sim_audit(conversion_id,record_type,record_id,original_currency,original_amount)
  select p_conversion_id,'investment_principal',investment_id,'USD',principal
  from sim_investment where currency='USD';
  insert into sim_audit(conversion_id,record_type,record_id,original_currency,original_amount)
  select p_conversion_id,'investment_profit',investment_id,'USD',credited_profit
  from sim_investment where currency='USD' and credited_profit <> 0;

  update sim_wallet set
    available_bdx = available_bdx + available_usd / p_usd_per_bdx,
    locked_bdx = locked_bdx + locked_usd / p_usd_per_bdx,
    referral_bdx = referral_bdx + referral_usd / p_usd_per_bdx,
    available_usd = 0,
    locked_usd = 0,
    referral_usd = 0
  where available_usd <> 0 or locked_usd <> 0 or referral_usd <> 0;
  get diagnostics v_count = row_count;

  if p_fail_after_wallet then
    raise exception 'forced mid-conversion failure';
  end if;

  update sim_investment set
    principal = principal / p_usd_per_bdx,
    credited_profit = credited_profit / p_usd_per_bdx,
    currency = 'BDX'
  where currency = 'USD';
  get diagnostics v_existing = row_count;
  v_count := v_count + v_existing;

  -- Historical transaction rows are intentionally immutable and remain in USD
  -- where originally recorded. They are not rewritten by a wallet conversion.
  return v_count;
end;
$fn$;

select is(
  pg_temp.simulate_atomic_conversion('cutover-1',0.10,'coingecko',now(),false),
  4,
  'first conversion converts two wallet rows and two USD investments'
);

select is((select available_usd from sim_wallet where user_id='user-a'),0::numeric,
  'legacy available USD is zero after conversion');
select is((select locked_usd from sim_wallet where user_id='user-a'),0::numeric,
  'legacy locked USD is zero after conversion');
select is((select available_bdx from sim_wallet where user_id='user-a'),1260::numeric,
  'available BDX equals existing BDX plus USD available converted at captured quote');
select is((select locked_bdx from sim_wallet where user_id='user-a'),2520::numeric,
  'locked BDX equals existing BDX plus USD locked converted at captured quote');
select is((select referral_bdx from sim_wallet where user_id='user-a'),51::numeric,
  'referral earnings convert without being added to available wallet');
select is((select count(*)::integer from sim_investment where currency='USD'),0,
  'USD investment principal and credited profit are converted together');
select is((select principal from sim_investment where investment_id='inv-active'),2000::numeric,
  'active investment principal is converted at captured quote');
select is((select credited_profit from sim_investment where investment_id='inv-active'),125::numeric,
  'already-credited investment profit is converted at captured quote');
select is((select principal from sim_investment where investment_id='inv-bdx'),300::numeric,
  'existing BDX investment is unchanged');
select is((select amount from sim_transaction where transaction_id='tx-old-usd'),75::numeric,
  'historical USD transaction amount is preserved exactly');
select is((select currency from sim_transaction where transaction_id='tx-old-usd'),'USD',
  'historical USD transaction currency is preserved');
select is((select count(*)::integer from sim_audit where conversion_id='cutover-1'),8,
  'audit retains original USD wallet, referral, investment principal and profit amounts');
select is(pg_temp.simulate_atomic_conversion('cutover-1',0.10,'coingecko',now(),false),0,
  'replaying the same conversion ID performs no second credit');
select is((select available_bdx from sim_wallet where user_id='user-a'),1260::numeric,
  'duplicate execution does not duplicate available BDX credit');

-- A fresh synthetic account ensures the injected exception occurs after real
-- wallet writes would have happened; the failed SQL statement must roll them back.
insert into sim_wallet values ('user-c',25.00,15.00,2.00,3.00,4.00,1.00);
insert into sim_investment values ('inv-fail','user-c','USD','active',10.00,1.00);

select throws_ok(
  $select pg_temp.simulate_atomic_conversion('cutover-fail',0.10,'coingecko',now(),true)$,
  'P0001','forced mid-conversion failure',
  'forced failure aborts the conversion statement'
);
select is((select available_usd from sim_wallet where user_id='user-c'),25.00::numeric,
  'forced failure rolls back the wallet conversion update');
select is((select currency from sim_investment where investment_id='inv-fail'),'USD',
  'forced failure leaves later investment conversion unapplied');
select is((select count(*)::integer from sim_conversion_run where conversion_id='cutover-fail'),0,
  'failed conversion leaves no partial conversion-run marker');

select * from finish();
rollback;
