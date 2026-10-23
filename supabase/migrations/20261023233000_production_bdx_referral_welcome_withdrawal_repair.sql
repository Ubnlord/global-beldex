begin;

-- Snapshot current accounts so the new welcome bonus is never retroactively paid.
create table if not exists public.welcome_bonus_migration_exclusions (
  user_id uuid primary key,
  created_at timestamptz not null default now()
);
insert into public.welcome_bonus_migration_exclusions(user_id)
select id from auth.users on conflict (user_id) do nothing;
insert into public.welcome_bonus_migration_exclusions(user_id)
select user_id from public.user_profile on conflict (user_id) do nothing;
revoke all on public.welcome_bonus_migration_exclusions from public, anon, authenticated;

-- The 5% referral policy starts now and applies only to the first completed BDX deposit after cutover.
create table if not exists public.bdx_referral_policy_cutover (
  singleton boolean primary key default true check (singleton),
  effective_at timestamptz not null default now()
);
insert into public.bdx_referral_policy_cutover(singleton) values (true) on conflict (singleton) do nothing;
revoke all on public.bdx_referral_policy_cutover from public, anon, authenticated;
grant select on public.bdx_referral_policy_cutover to service_role;

-- Enforce BDX-only requests and the 76 BDX withdrawal floor at the database boundary.
create or replace function public.create_financial_transaction(
  p_type text, p_amount numeric, p_method text, p_note text, p_request_id uuid, p_currency text
) returns public.transaction
language plpgsql security definer
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
  if v_currency <> 'BDX' then raise exception 'Only BDX accounting is supported'; end if;
  if v_method <> 'BELDEX' then raise exception 'Only Beldex transactions are supported'; end if;
  if p_type='deposit' and p_amount < 4000 then raise exception 'Minimum deposit is 4000 BDX'; end if;
  if p_type='withdraw' and p_amount < 76 then raise exception 'Minimum withdrawal is 76 BDX'; end if;
  if p_type='withdraw' and (
    v_address !~ '^[1-9A-HJ-NP-Za-km-z]+$' or length(v_address) < 90 or length(v_address) > 110
  ) then raise exception 'Invalid Beldex destination address'; end if;
  perform public.assert_user_can_transact(v_uid);
  if p_request_id is not null then
    select * into v_tx from public.transaction where user_id=v_uid and request_id=p_request_id limit 1;
    if found then
      if v_tx.type <> p_type or v_tx.amount <> p_amount
        or coalesce(v_tx.currency,'USD') <> v_currency
        or upper(coalesce(v_tx.method,'')) <> v_method then
        raise exception 'Request ID was already used for a different transaction';
      end if;
      return v_tx;
    end if;
  end if;
  if p_type='withdraw' then
    update public.user_profile set bdx_balance=bdx_balance-p_amount,updated_at=now()
    where user_id=v_uid and bdx_balance>=p_amount;
    if not found then raise exception 'Insufficient BDX balance'; end if;
  end if;
  insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note,request_id)
  values(v_uid,p_type,p_amount,'BDX','pending','awaiting','Beldex',
    case when p_type='withdraw' then v_address else null end,p_request_id)
  returning * into v_tx;
  return v_tx;
exception when unique_violation then
  if p_request_id is not null then
    select * into v_tx from public.transaction where user_id=v_uid and request_id=p_request_id limit 1;
    if found and v_tx.type=p_type and v_tx.amount=p_amount
      and coalesce(v_tx.currency,'USD')=v_currency
      and upper(coalesce(v_tx.method,''))=v_method then return v_tx; end if;
  end if;
  raise;
end;
$function$;
revoke all on function public.create_financial_transaction(text,numeric,text,text,uuid,text) from public, anon;
grant execute on function public.create_financial_transaction(text,numeric,text,text,uuid,text) to authenticated;

-- Credit 40 BDX once to eligible accounts created after the migration snapshot.
create or replace function public.ensure_user_profile(
  p_username text, p_fullname text, p_phone text default '', p_country text default '', p_ref text default null
) returns public.user_profile
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
  v_profile public.user_profile;
  v_ref uuid;
  v_code text;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  perform pg_advisory_xact_lock(hashtextextended('welcome-bonus:'||v_uid::text, 0));
  if coalesce(trim(p_username),'')='' then raise exception 'Username is required'; end if;
  if p_ref is not null and trim(p_ref)<>'' then
    select user_id into v_ref from public.user_profile
    where lower(username)=lower(trim(p_ref)) or lower(coalesce(referral_code,''))=lower(trim(p_ref)) limit 1;
    if v_ref=v_uid then raise exception 'Cannot refer yourself'; end if;
  end if;
  v_code := lower(regexp_replace(trim(p_username),'[^a-zA-Z0-9_-]','','g'));
  if v_code='' then v_code := substr(replace(v_uid::text,'-',''),1,12); end if;
  insert into public.user_profile(user_id,username,fullname,phone,country,referral_code,referred_by_user_id,updated_at)
  values(v_uid,trim(p_username),coalesce(nullif(trim(p_fullname),''),trim(p_username)),
    coalesce(p_phone,''),coalesce(p_country,''),v_code,v_ref,now())
  on conflict (user_id) do update set
    username=coalesce(nullif(excluded.username,''),public.user_profile.username),
    fullname=coalesce(nullif(excluded.fullname,''),public.user_profile.fullname),
    phone=excluded.phone,country=excluded.country,
    referral_code=coalesce(public.user_profile.referral_code,excluded.referral_code),
    referred_by_user_id=coalesce(public.user_profile.referred_by_user_id,excluded.referred_by_user_id),
    updated_at=now()
  returning * into v_profile;
  if not exists(select 1 from public.welcome_bonus_migration_exclusions where user_id=v_uid)
    and not exists(select 1 from public.transaction where user_id=v_uid and type='bonus' and method='Welcome Bonus') then
    update public.user_profile set bdx_balance=bdx_balance+40,updated_at=now()
    where user_id=v_uid returning * into v_profile;
    insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
    values(v_uid,'bonus',40,'BDX','completed','approved','Welcome Bonus','Server-side 40 BDX welcome bonus');
  end if;
  return v_profile;
end;
$function$;
revoke all on function public.ensure_user_profile(text,text,text,text,text) from public, anon;
grant execute on function public.ensure_user_profile(text,text,text,text,text) to authenticated;

-- Award exactly 5% on the first completed BDX deposit after cutover, idempotently.
create or replace function public.credit_referral_for_deposit(p_transaction_id uuid)
returns numeric
language plpgsql security definer
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
  perform pg_advisory_xact_lock(hashtextextended(v_tx.user_id::text, 0));
  select t.id into v_first_deposit_id
  from public.transaction t cross join public.bdx_referral_policy_cutover c
  where c.singleton and t.user_id=v_tx.user_id and t.type='deposit'
    and t.status='completed' and t.currency='BDX'
    and coalesce(t.settled_at,t.created_at)>=c.effective_at
  order by coalesce(t.settled_at,t.created_at),t.created_at,t.id limit 1;
  if v_first_deposit_id is distinct from v_tx.id then return 0; end if;
  select referred_by_user_id into v_ref from public.user_profile where user_id=v_tx.user_id;
  if v_ref is null or v_ref=v_tx.user_id then return 0; end if;
  if exists(select 1 from public.transaction r where r.user_id=v_ref and r.type='referral'
    and (r.method='Referral user '||v_tx.user_id::text or exists(
      select 1 from public.transaction prior_deposit where prior_deposit.user_id=v_tx.user_id
      and prior_deposit.type='deposit'
      and prior_deposit.id::text=substring(r.method from length('Referral deposit ')+1)
    ))) then return 0; end if;
  v_reward := round(v_tx.amount*0.05,18);
  if v_reward<=0 then return 0; end if;
  update public.user_profile set bdx_balance=bdx_balance+v_reward,
    referral_earnings_bdx=referral_earnings_bdx+v_reward,updated_at=now() where user_id=v_ref;
  if not found then raise exception 'Referrer profile not found'; end if;
  insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note)
  values(v_ref,'referral',v_reward,'BDX','completed','approved','Referral deposit '||v_tx.id::text,
    '5% BDX referral reward for the first completed deposit');
  return v_reward;
end;
$function$;
revoke all on function public.credit_referral_for_deposit(uuid) from public, anon, authenticated;

commit;
