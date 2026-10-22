begin;

-- Abort rather than strand any legacy request if the live ledger changed after
-- the read-only cutover audit. Completed/failed history is left untouched.
do $preflight$
begin
  if exists (
    select 1 from public.transaction
    where coalesce(currency,'USD')='USD'
      and type in ('deposit','withdraw')
      and status not in ('completed','failed')
  ) then
    raise exception 'BDX cutover blocked: unresolved legacy USD deposit/withdrawal exists';
  end if;

  -- Active legacy principal must be covered by legacy locked funds before conversion.
  if exists (
    select 1
    from public.user_profile p
    join (
      select user_id, sum(principal) as active_principal
      from public.user_investment
      where currency='USD' and status='active'
      group by user_id
    ) i on i.user_id=p.user_id
    where abs(p.locked_balance - i.active_principal) > 0.00000001
  ) then
    raise exception 'BDX cutover blocked: active legacy principal and locked balance do not reconcile per account';
  end if;

  if exists (
    select 1
    from public.user_profile p
    left join (
      select user_id, sum(principal) as active_principal
      from public.user_investment
      where currency='USD' and status='active'
      group by user_id
    ) i on i.user_id=p.user_id
    where p.locked_balance > 0.00000001 and coalesce(i.active_principal,0)=0
  ) then
    raise exception 'BDX cutover blocked: locked legacy balance has no matching active legacy investment';
  end if;

  if exists (
    select 1 from public.user_profile
    where available_balance < 0 or locked_balance < 0 or bdx_balance < 0 or locked_bdx_balance < 0
  ) then
    raise exception 'BDX cutover blocked: negative wallet balance requires manual reconciliation';
  end if;
end;
$preflight$;

-- BDX-only accounting cutover. This migration defines the guarded conversion but
-- does NOT execute it automatically. The conversion RPC requires two fresh,
-- independently sourced BDX/USD quotes and is callable only with service_role.
-- Historical transaction rows are intentionally preserved unchanged for audit.
-- Defaults affect future rows only; archived legacy records retain their currency.
alter table public.transaction alter column currency set default 'BDX';
alter table public.user_investment alter column currency set default 'BDX';

create table if not exists public.financial_currency_conversion_run (
  id uuid primary key default gen_random_uuid(),
  status text not null check (status in ('completed')),
  bdx_usd_rate_a numeric(24,12) not null,
  bdx_usd_rate_b numeric(24,12) not null,
  bdx_usd_rate_applied numeric(24,12) not null,
  quote_source_a text not null,
  quote_source_b text not null,
  quote_at_a timestamptz not null,
  quote_at_b timestamptz not null,
  quote_reference_a text not null,
  quote_reference_b text not null,
  profile_count integer not null default 0,
  investment_count integer not null default 0,
  created_by text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.financial_currency_conversion_profile_audit (
  run_id uuid not null references public.financial_currency_conversion_run(id),
  user_id uuid not null,
  old_available_balance numeric not null,
  old_locked_balance numeric not null,
  old_bdx_balance numeric not null,
  old_locked_bdx_balance numeric not null,
  old_total_deposits numeric not null,
  old_total_withdrawals numeric not null,
  old_referral_earnings numeric not null,
  converted_available_bdx numeric not null,
  converted_locked_bdx numeric not null,
  converted_deposits_bdx numeric not null,
  converted_withdrawals_bdx numeric not null,
  converted_referrals_bdx numeric not null,
  created_at timestamptz not null default now(),
  primary key (run_id, user_id)
);

create table if not exists public.financial_currency_conversion_investment_audit (
  run_id uuid not null references public.financial_currency_conversion_run(id),
  investment_id uuid not null,
  user_id uuid not null,
  old_currency text not null,
  old_principal numeric not null,
  old_credited_profit numeric not null,
  converted_principal_bdx numeric not null,
  converted_profit_bdx numeric not null,
  created_at timestamptz not null default now(),
  primary key (run_id, investment_id)
);

-- Existing users must not receive a second welcome bonus merely because the
-- account is migrated. New accounts created after this migration are eligible.
create table if not exists public.welcome_bonus_migration_exclusions (
  user_id uuid primary key,
  created_at timestamptz not null default now()
);
insert into public.welcome_bonus_migration_exclusions(user_id)
select id from auth.users
on conflict (user_id) do nothing;
insert into public.welcome_bonus_migration_exclusions(user_id)
select user_id from public.user_profile
on conflict (user_id) do nothing;

-- The 5% referral policy applies to the first completed BDX deposit after
-- cutover. Historical deposits are immutable audit history, not new eligibility.
create table if not exists public.bdx_referral_policy_cutover (
  singleton boolean primary key default true check (singleton),
  effective_at timestamptz not null default now()
);
insert into public.bdx_referral_policy_cutover(singleton)
values (true) on conflict (singleton) do nothing;
revoke all on public.bdx_referral_policy_cutover from public, anon, authenticated;
grant select on public.bdx_referral_policy_cutover to service_role;

revoke all on public.financial_currency_conversion_run from public, anon, authenticated;
revoke all on public.financial_currency_conversion_profile_audit from public, anon, authenticated;
revoke all on public.financial_currency_conversion_investment_audit from public, anon, authenticated;
revoke all on public.welcome_bonus_migration_exclusions from public, anon, authenticated;
grant select on public.financial_currency_conversion_run to service_role;
grant select on public.financial_currency_conversion_profile_audit to service_role;
grant select on public.financial_currency_conversion_investment_audit to service_role;

create or replace function public.preview_usd_to_bdx_conversion(p_bdx_usd_rate numeric)
returns table (
  profile_count bigint,
  profiles_with_legacy_available bigint,
  legacy_available_total numeric,
  legacy_locked_total numeric,
  active_legacy_investment_count bigint,
  active_legacy_investment_principal numeric,
  projected_available_bdx numeric,
  projected_locked_bdx numeric,
  projected_active_principal_bdx numeric
)
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if p_bdx_usd_rate is null or p_bdx_usd_rate < 0.02 or p_bdx_usd_rate > 0.20 then
    raise exception 'BDX/USD quote is outside the reviewed safety range';
  end if;
  return query
  select
    count(*)::bigint,
    count(*) filter (where p.available_balance <> 0)::bigint,
    coalesce(sum(p.available_balance),0),
    coalesce(sum(p.locked_balance),0),
    (select count(*) from public.user_investment ui where ui.currency='USD' and ui.status='active'),
    (select coalesce(sum(ui.principal),0) from public.user_investment ui where ui.currency='USD' and ui.status='active'),
    coalesce(sum(round(p.available_balance / p_bdx_usd_rate,18)),0),
    coalesce(sum(round(p.locked_balance / p_bdx_usd_rate,18)),0),
    (select coalesce(sum(round(ui.principal / p_bdx_usd_rate,18)),0)
       from public.user_investment ui where ui.currency='USD' and ui.status='active')
  from public.user_profile p;
end;
$function$;
revoke all on function public.preview_usd_to_bdx_conversion(numeric) from public, anon, authenticated;
grant execute on function public.preview_usd_to_bdx_conversion(numeric) to service_role;

create or replace function public.execute_usd_to_bdx_conversion(
  p_quote_source_a text,
  p_bdx_usd_rate_a numeric,
  p_quote_at_a timestamptz,
  p_quote_reference_a text,
  p_quote_source_b text,
  p_bdx_usd_rate_b numeric,
  p_quote_at_b timestamptz,
  p_quote_reference_b text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_rate numeric(24,12);
  v_run_id uuid;
  v_profile_count integer;
  v_investment_count integer;
  v_created_by text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;

  -- Both sources must quote BDX directly against USD. Do not mix a USDT
  -- exchange quote into a USD conversion unless a separately verified USDT/USD
  -- rate is available; this migration deliberately blocks that shortcut.
  if lower(coalesce(p_quote_source_a,'')) not in ('coingecko','coinmarketcap')
     or lower(coalesce(p_quote_source_b,'')) not in ('coingecko','coinmarketcap')
     or lower(p_quote_source_a)=lower(p_quote_source_b) then
    raise exception 'CoinGecko and CoinMarketCap USD quotes are both required';
  end if;
  if p_quote_reference_a is null or btrim(p_quote_reference_a)=''
     or p_quote_reference_b is null or btrim(p_quote_reference_b)='' then
    raise exception 'Both quote references are required';
  end if;
  if p_quote_at_a is null or p_quote_at_b is null
     or p_quote_at_a > now() + interval '1 minute'
     or p_quote_at_b > now() + interval '1 minute'
     or p_quote_at_a < now() - interval '10 minutes'
     or p_quote_at_b < now() - interval '10 minutes' then
    raise exception 'Both market quotes must be no more than 10 minutes old';
  end if;
  if abs(extract(epoch from (p_quote_at_a-p_quote_at_b))) > 120 then
    raise exception 'Market quote timestamps must be within 2 minutes of each other';
  end if;
  if p_bdx_usd_rate_a is null or p_bdx_usd_rate_b is null
     or p_bdx_usd_rate_a < 0.02 or p_bdx_usd_rate_a > 0.20
     or p_bdx_usd_rate_b < 0.02 or p_bdx_usd_rate_b > 0.20 then
    raise exception 'BDX/USD quote is outside the reviewed safety range';
  end if;
  if abs(p_bdx_usd_rate_a - p_bdx_usd_rate_b)
     / ((p_bdx_usd_rate_a + p_bdx_usd_rate_b) / 2) > 0.02 then
    raise exception 'Market quotes differ by more than 2 percent';
  end if;
  if exists (select 1 from public.financial_currency_conversion_run) then
    raise exception 'A currency conversion run already exists; refusing to repeat it';
  end if;

  v_rate := round((p_bdx_usd_rate_a + p_bdx_usd_rate_b) / 2, 12);
  v_created_by := coalesce(auth.uid()::text, 'service_role');

  insert into public.financial_currency_conversion_run (
    status, bdx_usd_rate_a, bdx_usd_rate_b, bdx_usd_rate_applied,
    quote_source_a, quote_source_b, quote_at_a, quote_at_b,
    quote_reference_a, quote_reference_b, created_by
  ) values (
    'completed', p_bdx_usd_rate_a, p_bdx_usd_rate_b, v_rate,
    lower(p_quote_source_a), lower(p_quote_source_b), p_quote_at_a, p_quote_at_b,
    p_quote_reference_a, p_quote_reference_b, v_created_by
  ) returning id into v_run_id;

  insert into public.financial_currency_conversion_profile_audit (
    run_id,user_id,old_available_balance,old_locked_balance,old_bdx_balance,
    old_locked_bdx_balance,old_total_deposits,old_total_withdrawals,old_referral_earnings,
    converted_available_bdx,converted_locked_bdx,converted_deposits_bdx,
    converted_withdrawals_bdx,converted_referrals_bdx
  )
  select v_run_id,p.user_id,p.available_balance,p.locked_balance,p.bdx_balance,
    p.locked_bdx_balance,p.total_deposits,p.total_withdrawals,p.referral_earnings,
    round(p.available_balance/v_rate,18),round(p.locked_balance/v_rate,18),
    coalesce((select round(sum(t.amount)/v_rate,18) from public.transaction t
      where t.user_id=p.user_id and t.type='deposit' and t.status='completed'
        and coalesce(t.currency,'USD')='USD'),0),
    coalesce((select round(sum(t.amount)/v_rate,18) from public.transaction t
      where t.user_id=p.user_id and t.type='withdraw' and t.status='completed'
        and coalesce(t.currency,'USD')='USD'),0),
    coalesce((select round(sum(t.amount)/v_rate,18) from public.transaction t
      where t.user_id=p.user_id and t.type='referral' and t.status='completed'
        and coalesce(t.currency,'USD')='USD'),0)
  from public.user_profile p
  where p.available_balance<>0 or p.locked_balance<>0
     or p.total_deposits<>0 or p.total_withdrawals<>0 or p.referral_earnings<>0
     or exists (select 1 from public.transaction t where t.user_id=p.user_id
       and t.status='completed' and coalesce(t.currency,'USD')='USD'
       and t.type in ('deposit','withdraw','referral'))
     or exists (select 1 from public.user_investment ui
       where ui.user_id=p.user_id and ui.currency='USD');

  insert into public.financial_currency_conversion_investment_audit (
    run_id,investment_id,user_id,old_currency,old_principal,old_credited_profit,
    converted_principal_bdx,converted_profit_bdx
  )
  select v_run_id,ui.id,ui.user_id,ui.currency,ui.principal,ui.credited_profit,
    round(ui.principal/v_rate,18),round(ui.credited_profit/v_rate,18)
  from public.user_investment ui
  where ui.currency='USD';

  select count(*) into v_profile_count
  from public.financial_currency_conversion_profile_audit where run_id=v_run_id;
  select count(*) into v_investment_count
  from public.financial_currency_conversion_investment_audit where run_id=v_run_id;

  -- Shared profile aggregate counters can contain more than one currency.
  -- Rebuild the BDX-specific counters from the transaction ledger, converting
  -- only completed legacy USD rows. Never divide mixed-currency profile totals.
  update public.user_profile p
  set bdx_balance = p.bdx_balance + round(p.available_balance/v_rate,18),
      locked_bdx_balance = p.locked_bdx_balance + round(p.locked_balance/v_rate,18),
      total_deposits_bdx = p.total_deposits_bdx + coalesce((
        select round(sum(t.amount)/v_rate,18) from public.transaction t
        where t.user_id=p.user_id and t.type='deposit' and t.status='completed'
          and coalesce(t.currency,'USD')='USD'),0),
      total_withdrawals_bdx = p.total_withdrawals_bdx + coalesce((
        select round(sum(t.amount)/v_rate,18) from public.transaction t
        where t.user_id=p.user_id and t.type='withdraw' and t.status='completed'
          and coalesce(t.currency,'USD')='USD'),0),
      referral_earnings_bdx = p.referral_earnings_bdx + coalesce((
        select round(sum(t.amount)/v_rate,18) from public.transaction t
        where t.user_id=p.user_id and t.type='referral' and t.status='completed'
          and coalesce(t.currency,'USD')='USD'),0),
      available_balance=0,
      locked_balance=0,
      total_deposits=0,
      total_withdrawals=0,
      referral_earnings=0,
      updated_at=now()
  where p.available_balance<>0 or p.locked_balance<>0
     or p.total_deposits<>0 or p.total_withdrawals<>0 or p.referral_earnings<>0
     or exists (select 1 from public.transaction t where t.user_id=p.user_id
       and t.status='completed' and coalesce(t.currency,'USD')='USD'
       and t.type in ('deposit','withdraw','referral'))
     or exists (select 1 from public.user_investment ui
       where ui.user_id=p.user_id and ui.currency='USD');

  update public.user_investment ui
  set principal=round(ui.principal/v_rate,18),
      credited_profit=round(ui.credited_profit/v_rate,18),
      currency='BDX',
      updated_at=now()
  where ui.currency='USD';

  update public.financial_currency_conversion_run
  set profile_count=v_profile_count, investment_count=v_investment_count
  where id=v_run_id;

  return v_run_id;
end;
$function$;
revoke all on function public.execute_usd_to_bdx_conversion(text,numeric,timestamptz,text,text,numeric,timestamptz,text) from public, anon, authenticated;
grant execute on function public.execute_usd_to_bdx_conversion(text,numeric,timestamptz,text,text,numeric,timestamptz,text) to service_role;

-- New financial requests are BDX-only. Legacy transaction rows remain immutable
-- history; all active balance and investment accounting is normalized by the
-- explicitly invoked conversion above.
create or replace function public.create_financial_transaction(
  p_type text,
  p_amount numeric,
  p_method text,
  p_note text,
  p_request_id uuid,
  p_currency text
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
  v_tx public.transaction;
  v_currency text := upper(trim(coalesce(p_currency,'')));
  v_method text := upper(trim(coalesce(p_method,'')));
  v_address text := btrim(coalesce(p_note,''));
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  if p_type not in ('deposit','withdraw') then raise exception 'Invalid transaction type'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be greater than zero'; end if;
  if p_request_id is null then raise exception 'Request ID is required for idempotency'; end if;
  if v_currency <> 'BDX' then raise exception 'Only BDX accounting is supported'; end if;
  if v_method <> 'BELDEX' then raise exception 'Only Beldex transactions are supported'; end if;
  if p_type='deposit' and p_amount < 4000 then raise exception 'Minimum deposit is 4000 BDX'; end if;
  if p_type='withdraw' and p_amount < 76 then raise exception 'Minimum withdrawal is 76 BDX'; end if;

  perform public.assert_user_can_transact(v_uid);

  select * into v_tx from public.transaction
  where user_id=v_uid and request_id=p_request_id limit 1;
  if found then
    if v_tx.type<>p_type or v_tx.amount<>p_amount
       or coalesce(v_tx.currency,'')<>v_currency
       or upper(coalesce(v_tx.method,''))<>v_method
       or coalesce(v_tx.note,'')<>case when p_type='withdraw' then v_address else '' end then
      raise exception 'Request ID was already used for a different transaction';
    end if;
    return v_tx;
  end if;

  if p_type='withdraw' then
    if v_address !~ '^[1-9A-HJ-NP-Za-km-z]+$'
       or length(v_address)<90 or length(v_address)>110 then
      raise exception 'Invalid Beldex destination address';
    end if;
    update public.user_profile
      set bdx_balance=bdx_balance-p_amount,updated_at=now()
      where user_id=v_uid and bdx_balance>=p_amount;
    if not found then raise exception 'Insufficient BDX balance'; end if;
  end if;

  insert into public.transaction(
    user_id,type,amount,currency,status,approval_status,method,note,request_id
  ) values (
    v_uid,p_type,p_amount,'BDX','pending','awaiting','Beldex',
    case when p_type='withdraw' then v_address else null end,p_request_id
  ) returning * into v_tx;
  return v_tx;
exception when unique_violation then
  select * into v_tx from public.transaction
  where user_id=v_uid and request_id=p_request_id limit 1;
  if found and v_tx.type=p_type and v_tx.amount=p_amount
     and v_tx.currency='BDX' and upper(coalesce(v_tx.method,''))='BELDEX'
     and coalesce(v_tx.note,'')=case when p_type='withdraw' then v_address else '' end then
    return v_tx;
  end if;
  raise;
end;
$function$;
revoke all on function public.create_financial_transaction(text,numeric,text,text,uuid,text) from public, anon;
grant execute on function public.create_financial_transaction(text,numeric,text,text,uuid,text) to authenticated;
drop function if exists public.create_financial_transaction(text,numeric,text,text,uuid);
drop function if exists public.create_financial_transaction(text,numeric,text,text);

-- Welcome bonus is BDX-denominated and one-time. Existing accounts are excluded
-- by the migration snapshot above, even if an old account has no bonus row.
create or replace function public.ensure_user_profile(
  p_username text,
  p_fullname text,
  p_phone text default '',
  p_country text default '',
  p_ref text default null
)
returns public.user_profile
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
  v_profile public.user_profile;
  v_ref uuid;
  v_code text;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  if coalesce(trim(p_username),'')='' then raise exception 'Username is required'; end if;

  if p_ref is not null and trim(p_ref)<>'' then
    select user_id into v_ref from public.user_profile
    where lower(username)=lower(trim(p_ref))
       or lower(coalesce(referral_code,''))=lower(trim(p_ref))
    limit 1;
    if v_ref=v_uid then raise exception 'Cannot refer yourself'; end if;
  end if;

  v_code := lower(regexp_replace(trim(p_username),'[^a-zA-Z0-9_-]','','g'));
  if v_code='' then v_code := substr(replace(v_uid::text,'-',''),1,12); end if;

  insert into public.user_profile(
    user_id,username,fullname,phone,country,referral_code,referred_by_user_id,updated_at
  ) values (
    v_uid,trim(p_username),coalesce(nullif(trim(p_fullname),''),trim(p_username)),
    coalesce(p_phone,''),coalesce(p_country,''),v_code,v_ref,now()
  )
  on conflict (user_id) do update set
    username=coalesce(nullif(excluded.username,''),public.user_profile.username),
    fullname=coalesce(nullif(excluded.fullname,''),public.user_profile.fullname),
    phone=excluded.phone,country=excluded.country,
    referral_code=coalesce(public.user_profile.referral_code,excluded.referral_code),
    referred_by_user_id=coalesce(public.user_profile.referred_by_user_id,excluded.referred_by_user_id),
    updated_at=now()
  returning * into v_profile;

  if not exists (select 1 from public.welcome_bonus_migration_exclusions where user_id=v_uid)
     and not exists (
       select 1 from public.transaction
       where user_id=v_uid and type='bonus' and method='Welcome Bonus'
     ) then
    update public.user_profile
      set bdx_balance=bdx_balance+40,updated_at=now()
      where user_id=v_uid returning * into v_profile;
    insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
    values(v_uid,'bonus',40,'BDX','completed','approved','Welcome Bonus','Server-side 40 BDX welcome bonus');
  end if;

  return v_profile;
end;
$function$;

create or replace function public.credit_referral_for_deposit(p_transaction_id uuid)
returns numeric
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_tx public.transaction;
  v_ref uuid;
  v_first_deposit_id uuid;
  v_reward numeric;
begin
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if not found then raise exception 'Transaction not found'; end if;
  if v_tx.type<>'deposit' or v_tx.status<>'completed' or v_tx.currency<>'BDX' then return 0; end if;

  select t.id into v_first_deposit_id
  from public.transaction t
  cross join public.bdx_referral_policy_cutover c
  where c.singleton
    and t.user_id=v_tx.user_id and t.type='deposit'
    and t.status='completed' and t.currency='BDX'
    and coalesce(t.settled_at,t.created_at) >= c.effective_at
  order by coalesce(t.settled_at,t.created_at),t.created_at,t.id
  limit 1;
  if v_first_deposit_id is distinct from v_tx.id then return 0; end if;

  select referred_by_user_id into v_ref
  from public.user_profile where user_id=v_tx.user_id;
  if v_ref is null or v_ref=v_tx.user_id then return 0; end if;

  -- Idempotency across both the current transaction marker and legacy
  -- markers. The old "Referral deposit <transaction-id>" form is resolved by
  -- joining back to the deposit ledger without casting untrusted text to UUID.
  if exists (
    select 1 from public.transaction r
    where r.user_id=v_ref and r.type='referral'
      and (
        r.method='Referral user '||v_tx.user_id::text
        or exists (
          select 1 from public.transaction prior_deposit
          where prior_deposit.user_id=v_tx.user_id
            and prior_deposit.type='deposit'
            and prior_deposit.id::text=substring(r.method from length('Referral deposit ')+1)
        )
      )
  ) then return 0; end if;

  v_reward := round(v_tx.amount*0.05,18);
  if v_reward<=0 then return 0; end if;

  update public.user_profile
  set bdx_balance=bdx_balance+v_reward,
      referral_earnings_bdx=referral_earnings_bdx+v_reward,
      updated_at=now()
  where user_id=v_ref;
  if not found then raise exception 'Referrer profile not found'; end if;

  insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
  values(v_ref,'referral',v_reward,'BDX','completed','approved',
    'Referral deposit '||v_tx.id::text,
    '5% BDX referral reward for the first completed deposit');
  return v_reward;
end;
$function$;
revoke all on function public.credit_referral_for_deposit(uuid) from public, anon, authenticated;

-- Settlement only processes BDX requests. Pending USD requests must be resolved
-- through a separately reviewed manual reconciliation before this migration is run.
create or replace function public.admin_settle_transaction(
  p_transaction_id uuid,
  p_reason text default null
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_tx public.transaction;
  v_reason text := nullif(btrim(coalesce(p_reason,'')),'');
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then
    raise exception 'Permission denied';
  end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  if v_reason is null then raise exception 'Settlement reason is required'; end if;

  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if not found then raise exception 'Transaction not found'; end if;
  if v_tx.type not in ('deposit','withdraw') then raise exception 'Only deposit and withdrawal can be settled'; end if;
  if v_tx.status<>'pending' then raise exception 'Only pending transactions can be settled'; end if;
  if v_tx.approval_status<>'approved' then raise exception 'Transaction must be approved first'; end if;
  if v_tx.currency<>'BDX' or upper(coalesce(v_tx.method,''))<>'BELDEX' then
    raise exception 'Only BDX Beldex transactions can be settled';
  end if;

  if v_tx.type='deposit' then
    update public.user_profile
    set bdx_balance=bdx_balance+v_tx.amount,
        total_deposits_bdx=total_deposits_bdx+v_tx.amount,
        updated_at=now()
    where user_id=v_tx.user_id;
  else
    update public.user_profile
    set total_withdrawals_bdx=total_withdrawals_bdx+v_tx.amount,
        updated_at=now()
    where user_id=v_tx.user_id;
  end if;
  if not found then raise exception 'User profile not found during settlement'; end if;

  update public.transaction
  set status='completed',settled_at=now(),updated_at=now()
  where id=p_transaction_id returning * into v_tx;

  if v_tx.type='deposit' then perform public.credit_referral_for_deposit(v_tx.id); end if;

  insert into public.transaction_audit(transaction_id,admin_id,action,old_values,new_values,reason)
  values(v_tx.id,v_admin.id,'settled',jsonb_build_object('status','pending'),
    jsonb_build_object('status',v_tx.status,'currency','BDX'),v_reason);
  return v_tx;
end;
$function$;
revoke all on function public.admin_settle_transaction(uuid,text) from public, anon;
grant execute on function public.admin_settle_transaction(uuid,text) to authenticated;

-- Close legacy admin RPC paths that could approve, reject, or adjust a
-- non-BDX transaction after cutover. Deposit/withdraw wrappers delegate here.
create or replace function public.admin_approve_transaction(
  p_transaction_id uuid,
  p_reason text default null
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_tx public.transaction;
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then
    raise exception 'Permission denied';
  end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.type not in ('deposit','withdraw') then raise exception 'Only deposit and withdrawal requests can be approved'; end if;
  if v_tx.currency<>'BDX' or upper(coalesce(v_tx.method,''))<>'BELDEX' then
    raise exception 'Only BDX Beldex requests can be approved';
  end if;
  if v_tx.status<>'pending' or v_tx.approval_status<>'awaiting' then
    raise exception 'Only pending transactions awaiting approval can be approved';
  end if;

  update public.transaction
  set approval_status='approved',
      status='pending',
      approved_by=v_admin.id,
      approval_reason=p_reason,
      approved_at=now(),
      updated_at=now()
  where id=p_transaction_id returning * into v_tx;

  insert into public.transaction_audit(transaction_id,admin_id,action,old_values,new_values,reason)
  values(v_tx.id,v_admin.id,'approved',
    jsonb_build_object('approval_status','awaiting'),
    jsonb_build_object('approval_status','approved','status','pending','currency','BDX'),
    p_reason);
  return v_tx;
end;
$function$;
revoke all on function public.admin_approve_transaction(uuid,text) from public, anon;
grant execute on function public.admin_approve_transaction(uuid,text) to authenticated;

create or replace function public.admin_reject_transaction(
  p_transaction_id uuid,
  p_reason text
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_tx public.transaction;
  v_reason text := nullif(btrim(coalesce(p_reason,'')),'');
begin
  if not public.is_admin() or not public.admin_has_permission('reject_transactions') then
    raise exception 'Permission denied';
  end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  if v_reason is null then raise exception 'Rejection reason is required'; end if;
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.type not in ('deposit','withdraw') then raise exception 'Only deposit and withdrawal requests can be rejected'; end if;
  if v_tx.currency<>'BDX' or upper(coalesce(v_tx.method,''))<>'BELDEX' then
    raise exception 'Only BDX Beldex requests can be rejected';
  end if;
  if v_tx.status<>'pending' or v_tx.approval_status<>'awaiting' then
    raise exception 'Only pending transactions awaiting approval can be rejected';
  end if;

  if v_tx.type='withdraw' then
    update public.user_profile set bdx_balance=bdx_balance+v_tx.amount,updated_at=now()
    where user_id=v_tx.user_id;
    if not found then raise exception 'User profile not found while restoring rejected withdrawal'; end if;
  end if;

  update public.transaction
  set approval_status='rejected',status='failed',approved_by=v_admin.id,
      approval_reason=v_reason,approved_at=now(),updated_at=now()
  where id=p_transaction_id returning * into v_tx;

  insert into public.transaction_audit(transaction_id,admin_id,action,old_values,new_values,reason)
  values(v_tx.id,v_admin.id,'rejected',
    jsonb_build_object('approval_status','awaiting'),
    jsonb_build_object('approval_status','rejected','status','failed','currency','BDX'),
    v_reason);
  return v_tx;
end;
$function$;
revoke all on function public.admin_reject_transaction(uuid,text) from public, anon;
grant execute on function public.admin_reject_transaction(uuid,text) to authenticated;

-- Legacy balance adjustments are retired; use the dedicated BDX adjustment RPC.
create or replace function public.admin_adjust_balance(
  p_user_id uuid,
  p_delta numeric,
  p_reason text
)
returns public.user_profile
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
begin
  raise exception 'Legacy balance adjustments are disabled; use the audited BDX adjustment operation';
end;
$function$;
revoke all on function public.admin_adjust_balance(uuid,numeric,text) from public, anon, authenticated;

drop function if exists public.swap_assets(uuid,text,text,numeric,numeric);

-- Admin investment status changes must never mutate the legacy USD wallet.
-- Until the guarded conversion is completed, legacy investments are read-only.
create or replace function public.admin_manage_investment(
  p_investment_id uuid,
  p_daily_rate numeric,
  p_status text,
  p_reason text
)
returns public.user_investment
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_inv public.user_investment;
  v_profile public.user_profile;
  v_old_status text;
  v_reason text := nullif(btrim(coalesce(p_reason,'')),'');
begin
  if not public.is_admin() or not public.admin_has_permission('manage_users') then
    raise exception 'Permission denied';
  end if;
  if p_investment_id is null then raise exception 'Investment is required'; end if;
  if p_daily_rate is null or p_daily_rate < 0 then raise exception 'Invalid daily rate'; end if;
  if p_status not in ('active','completed','cancelled') then raise exception 'Invalid investment status'; end if;
  if v_reason is null then raise exception 'Reason is required'; end if;

  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  select * into v_inv from public.user_investment where id=p_investment_id for update;
  if v_inv.id is null then raise exception 'Investment not found'; end if;
  if v_inv.currency <> 'BDX' then
    raise exception 'Legacy investment is read-only until the audited BDX conversion is completed';
  end if;
  v_old_status := v_inv.status;

  select * into v_profile from public.user_profile where user_id=v_inv.user_id for update;
  if v_profile.user_id is null then raise exception 'User profile not found'; end if;
  if v_profile.blocked then raise exception 'Blocked user investment cannot be managed'; end if;

  if v_old_status='active' and p_status in ('completed','cancelled') then
    if v_profile.locked_bdx_balance < v_inv.principal then
      raise exception 'Locked BDX balance does not cover investment principal';
    end if;
    update public.user_profile
      set locked_bdx_balance=locked_bdx_balance-v_inv.principal,
          bdx_balance=bdx_balance+v_inv.principal,
          updated_at=now()
      where user_id=v_inv.user_id;
    insert into public.transaction(
      user_id,type,amount,currency,status,approval_status,method,note,
      approved_by,approval_reason,approved_at,settled_at
    ) values (
      v_inv.user_id,'bonus',v_inv.principal,'BDX','completed','approved',
      'Admin investment principal release',
      'Investment principal returned by admin: '||v_reason,
      v_admin.id,v_reason,now(),now()
    );
  elsif v_old_status in ('completed','cancelled') and p_status='active' then
    raise exception 'Completed or cancelled investments cannot be reactivated';
  end if;

  update public.user_investment
    set daily_rate=p_daily_rate,
        status=p_status,
        completed_at=case when p_status in ('completed','cancelled') then coalesce(completed_at,now()) else null end,
        updated_at=now()
    where id=p_investment_id returning * into v_inv;

  insert into public.admin_action_audit(admin_id,user_id,action,target_id,old_values,new_values,reason)
  values(v_admin.id,v_inv.user_id,'investment_managed',v_inv.id,
    jsonb_build_object('status',v_old_status,'principal',v_inv.principal,'currency','BDX'),
    jsonb_build_object('status',v_inv.status,'daily_rate',v_inv.daily_rate,'currency','BDX'),
    v_reason);
  return v_inv;
end;
$function$;
revoke all on function public.admin_manage_investment(uuid,numeric,text,text) from public, anon;
grant execute on function public.admin_manage_investment(uuid,numeric,text,text) to authenticated;

create or replace function public.admin_update_investment(
  p_investment_id uuid,
  p_daily_rate numeric default null,
  p_daily_accrual_enabled boolean default null
)
returns public.user_investment
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_old public.user_investment;
  v_new public.user_investment;
begin
  if not public.is_admin() or not public.admin_has_permission('manage_users') then
    raise exception 'Permission denied';
  end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  select * into v_old from public.user_investment where id=p_investment_id for update;
  if v_old.id is null then raise exception 'Investment not found'; end if;
  if v_old.currency <> 'BDX' then
    raise exception 'Legacy investment is read-only until the audited BDX conversion is completed';
  end if;
  if p_daily_rate is not null and p_daily_rate < 0 then raise exception 'Daily rate cannot be negative'; end if;

  update public.user_investment
  set daily_rate=coalesce(p_daily_rate,daily_rate),
      daily_accrual_enabled=coalesce(p_daily_accrual_enabled,daily_accrual_enabled),
      updated_at=now()
  where id=p_investment_id returning * into v_new;

  insert into public.admin_action_audit(admin_id,user_id,action,target_id,old_values,new_values,reason)
  values(v_admin.id,v_old.user_id,'investment_updated',p_investment_id,
    jsonb_build_object('daily_rate',v_old.daily_rate,'daily_accrual_enabled',v_old.daily_accrual_enabled,'currency','BDX'),
    jsonb_build_object('daily_rate',v_new.daily_rate,'daily_accrual_enabled',v_new.daily_accrual_enabled,'currency','BDX'),
    'Administrator updated BDX investment accrual settings');
  return v_new;
end;
$function$;
revoke all on function public.admin_update_investment(uuid,numeric,boolean) from public, anon;
grant execute on function public.admin_update_investment(uuid,numeric,boolean) to authenticated;

-- Remove the older five-argument overload: it still allowed USD investment
-- management and would bypass the BDX-only guard in the replacement functions.
drop function if exists public.admin_manage_investment(uuid,numeric,boolean,text,text);

-- Replace legacy USD admin funding with the same audited BDX wallet denomination.
create or replace function public.admin_fund_user(
  p_user_id uuid,
  p_amount numeric,
  p_reason text
)
returns public.user_profile
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_profile public.user_profile;
  v_admin_id uuid;
  v_before numeric;
  v_reason text := nullif(btrim(coalesce(p_reason,'')),'');
begin
  select id into v_admin_id from public.admin_user where user_id=auth.uid();
  if v_admin_id is null or not public.admin_has_permission('approve_transactions') then
    raise exception 'not authorized';
  end if;
  if p_user_id is null or p_amount is null or p_amount<=0 then raise exception 'invalid funding request'; end if;
  if v_reason is null then raise exception 'reason is required'; end if;
  select * into v_profile from public.user_profile where user_id=p_user_id for update;
  if not found then raise exception 'user profile not found'; end if;
  if v_profile.blocked then raise exception 'blocked user cannot receive funding'; end if;
  v_before := v_profile.bdx_balance;
  update public.user_profile set bdx_balance=bdx_balance+p_amount,updated_at=now()
    where user_id=p_user_id returning * into v_profile;
  insert into public.transaction(user_id,type,amount,currency,status,method,note,approved_by,approval_status,approval_reason,approved_at,settled_at,created_at)
  values(p_user_id,'bonus',p_amount,'BDX','completed','admin',v_reason,v_admin_id,'approved',v_reason,now(),now(),now());
  insert into public.admin_action_audit(admin_id,user_id,action,target_id,old_values,new_values,reason,created_at)
  values(v_admin_id,p_user_id,'fund_user',p_user_id,
    jsonb_build_object('bdx_balance',v_before),
    jsonb_build_object('bdx_balance',v_profile.bdx_balance),v_reason,now());
  return v_profile;
end;
$function$;


-- Keep the admin reconciliation endpoint available on the live schema even
-- when the newer source migration history has not been applied. Before the
-- conversion it reconciles both ledgers; after conversion it treats archived
-- USD rows as history and uses the conversion audit to reconcile their BDX value.
create or replace function public.admin_financial_reconciliation_v3()
returns table(
  user_id uuid,
  available_balance numeric,
  locked_balance numeric,
  expected_locked_balance numeric,
  locked_delta numeric,
  total_deposits numeric,
  recorded_deposits numeric,
  deposits_delta numeric,
  total_withdrawals numeric,
  recorded_withdrawals numeric,
  withdrawals_delta numeric,
  referral_earnings numeric,
  recorded_referrals numeric,
  referral_delta numeric,
  credited_investment_profit numeric,
  recorded_investment_profit numeric,
  investment_profit_delta numeric,
  bdx_balance numeric,
  locked_bdx_balance numeric,
  expected_locked_bdx_balance numeric,
  locked_bdx_delta numeric,
  total_deposits_bdx numeric,
  recorded_deposits_bdx numeric,
  deposits_bdx_delta numeric,
  total_withdrawals_bdx numeric,
  recorded_withdrawals_bdx numeric,
  withdrawals_bdx_delta numeric,
  referral_earnings_bdx numeric,
  recorded_referrals_bdx numeric,
  referral_bdx_delta numeric,
  credited_investment_profit_bdx numeric,
  recorded_investment_profit_bdx numeric,
  investment_profit_bdx_delta numeric,
  negative_balance boolean
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_converted boolean;
begin
  if not public.is_admin() or not public.admin_has_permission('view_transactions') then
    raise exception 'Permission denied';
  end if;

  select exists(select 1 from public.financial_currency_conversion_run)
  into v_converted;

  return query
  with d_usd as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='deposit' and t.status='completed' and coalesce(t.currency,'USD')='USD'
    group by t.user_id
  ), w_usd as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='withdraw' and t.status='completed' and coalesce(t.currency,'USD')='USD'
      and lower(coalesce(t.method,'')) not in ('admin','admin adjustment') group by t.user_id
  ), d_bdx as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='deposit' and t.status='completed' and t.currency='BDX' group by t.user_id
  ), w_bdx as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='withdraw' and t.status='completed' and t.currency='BDX'
      and coalesce(t.method,'')<>'Admin BDX adjustment' group by t.user_id
  ), r_usd as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='referral' and t.status='completed' and coalesce(t.currency,'USD')='USD'
    group by t.user_id
  ), r_bdx as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='referral' and t.status='completed' and t.currency='BDX' group by t.user_id
  ), ip_usd as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='bonus' and t.status='completed' and t.note='Server-side investment profit'
      and coalesce(t.currency,'USD')='USD' group by t.user_id
  ), ip_bdx as (
    select t.user_id,coalesce(sum(t.amount),0) amount from public.transaction t
    where t.type='bonus' and t.status='completed' and t.note='Server-side investment profit'
      and t.currency='BDX' group by t.user_id
  ), inv as (
    select ui.user_id,
      coalesce(sum(ui.principal) filter(where ui.status='active' and coalesce(ui.currency,'USD')='USD'),0) active_usd,
      coalesce(sum(ui.credited_profit) filter(where coalesce(ui.currency,'USD')='USD'),0) profit_usd,
      coalesce(sum(ui.principal) filter(where ui.status='active' and ui.currency='BDX'),0) active_bdx,
      coalesce(sum(ui.credited_profit) filter(where ui.currency='BDX'),0) profit_bdx
    from public.user_investment ui group by ui.user_id
  ), converted_profiles as (
    select a.user_id,
      coalesce(sum(a.converted_deposits_bdx),0) deposits_bdx,
      coalesce(sum(a.converted_withdrawals_bdx),0) withdrawals_bdx,
      coalesce(sum(a.converted_referrals_bdx),0) referrals_bdx
    from public.financial_currency_conversion_profile_audit a
    group by a.user_id
  ), converted_profit as (
    select a.user_id,coalesce(sum(a.converted_profit_bdx),0) profit_bdx
    from public.financial_currency_conversion_investment_audit a
    group by a.user_id
  )
  select
    p.user_id,
    p.available_balance,
    p.locked_balance,
    case when v_converted then 0 else coalesce(inv.active_usd,0) end,
    p.locked_balance-case when v_converted then 0 else coalesce(inv.active_usd,0) end,
    p.total_deposits,
    case when v_converted then 0 else coalesce(d_usd.amount,0) end,
    p.total_deposits-(case when v_converted then 0 else coalesce(d_usd.amount,0) end),
    p.total_withdrawals,
    case when v_converted then 0 else coalesce(w_usd.amount,0) end,
    p.total_withdrawals-(case when v_converted then 0 else coalesce(w_usd.amount,0) end),
    p.referral_earnings,
    case when v_converted then 0 else coalesce(r_usd.amount,0) end,
    p.referral_earnings-(case when v_converted then 0 else coalesce(r_usd.amount,0) end),
    coalesce(inv.profit_usd,0),
    case when v_converted then 0 else coalesce(ip_usd.amount,0) end,
    coalesce(inv.profit_usd,0)-(case when v_converted then 0 else coalesce(ip_usd.amount,0) end),
    p.bdx_balance,p.locked_bdx_balance,coalesce(inv.active_bdx,0),
    p.locked_bdx_balance-coalesce(inv.active_bdx,0),
    p.total_deposits_bdx,
    coalesce(d_bdx.amount,0)+case when v_converted then coalesce(cp.deposits_bdx,0) else 0 end,
    p.total_deposits_bdx-(coalesce(d_bdx.amount,0)+case when v_converted then coalesce(cp.deposits_bdx,0) else 0 end),
    p.total_withdrawals_bdx,
    coalesce(w_bdx.amount,0)+case when v_converted then coalesce(cp.withdrawals_bdx,0) else 0 end,
    p.total_withdrawals_bdx-(coalesce(w_bdx.amount,0)+case when v_converted then coalesce(cp.withdrawals_bdx,0) else 0 end),
    p.referral_earnings_bdx,
    coalesce(r_bdx.amount,0)+case when v_converted then coalesce(cp.referrals_bdx,0) else 0 end,
    p.referral_earnings_bdx-(coalesce(r_bdx.amount,0)+case when v_converted then coalesce(cp.referrals_bdx,0) else 0 end),
    coalesce(inv.profit_bdx,0),
    coalesce(ip_bdx.amount,0)+case when v_converted then coalesce(cip.profit_bdx,0) else 0 end,
    coalesce(inv.profit_bdx,0)-(coalesce(ip_bdx.amount,0)+case when v_converted then coalesce(cip.profit_bdx,0) else 0 end),
    p.available_balance<0 or p.locked_balance<0 or p.bdx_balance<0 or p.locked_bdx_balance<0
  from public.user_profile p
  left join d_usd on d_usd.user_id=p.user_id
  left join w_usd on w_usd.user_id=p.user_id
  left join d_bdx on d_bdx.user_id=p.user_id
  left join w_bdx on w_bdx.user_id=p.user_id
  left join r_usd on r_usd.user_id=p.user_id
  left join r_bdx on r_bdx.user_id=p.user_id
  left join ip_usd on ip_usd.user_id=p.user_id
  left join ip_bdx on ip_bdx.user_id=p.user_id
  left join inv on inv.user_id=p.user_id
  left join converted_profiles cp on cp.user_id=p.user_id
  left join converted_profit cip on cip.user_id=p.user_id
  order by p.created_at;
end;
$function$;
revoke all on function public.admin_financial_reconciliation_v3() from public, anon;
grant execute on function public.admin_financial_reconciliation_v3() to authenticated;

commit;
