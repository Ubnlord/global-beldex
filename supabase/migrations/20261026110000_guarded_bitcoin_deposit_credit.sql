begin;

-- Server-only, atomic BDX credit for a previously verified BTC deposit.
-- This function intentionally does not verify the blockchain itself. A trusted
-- verifier must write the observation and set intent.status='verified' only
-- after checking the canonical chain, address, output amount and confirmations.
create or replace function public.credit_verified_bitcoin_deposit(p_intent_id uuid)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $function$
declare
  v_intent public.bitcoin_deposit_intent;
  v_tx public.transaction;
  v_min_sats bigint;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Forbidden: server-side verifier required';
  end if;
  if p_intent_id is null then
    raise exception 'Deposit intent ID is required';
  end if;

  select * into v_intent
    from public.bitcoin_deposit_intent
   where id = p_intent_id
   for update;

  if not found then raise exception 'Bitcoin deposit intent not found'; end if;

  -- Idempotent retry: never credit an already-credited intent twice.
  if v_intent.status = 'credited' then
    select * into v_tx
      from public.transaction
     where user_id = v_intent.user_id
       and request_id = v_intent.id
     limit 1;
    if found and v_tx.type = 'deposit'
      and v_tx.currency = 'BDX'
      and v_tx.amount = v_intent.target_bdx then
      return v_tx;
    end if;
    raise exception 'Credited intent has no matching ledger transaction; manual review required';
  end if;

  if v_intent.status <> 'verified' then
    raise exception 'Deposit has not been verified by the trusted chain verifier';
  end if;

  v_min_sats := ceil(v_intent.quoted_btc * 100000000)::bigint;
  if not exists (
    select 1
      from public.bitcoin_chain_observation o
     where o.intent_id = v_intent.id
       and lower(o.destination_address) = lower(v_intent.receiving_address)
       and o.received_sats >= v_min_sats
       and o.confirmations >= 3
  ) then
    raise exception 'No matching Bitcoin output with required confirmations';
  end if;

  -- The request UUID is also the ledger idempotency key.
  select * into v_tx
    from public.transaction
   where user_id = v_intent.user_id
     and request_id = v_intent.id
   limit 1;
  if found then
    if v_tx.type = 'deposit'
      and v_tx.currency = 'BDX'
      and v_tx.amount = v_intent.target_bdx
      and upper(coalesce(v_tx.method,'')) = 'BITCOIN' then
      update public.bitcoin_deposit_intent
         set status = 'credited', updated_at = now()
       where id = v_intent.id;
      return v_tx;
    end if;
    raise exception 'Deposit idempotency key conflicts with another ledger transaction';
  end if;

  update public.user_profile
     set bdx_balance = bdx_balance + v_intent.target_bdx,
         total_deposits_bdx = total_deposits_bdx + v_intent.target_bdx,
         updated_at = now()
   where user_id = v_intent.user_id;
  if not found then raise exception 'User BDX wallet not found'; end if;

  insert into public.transaction(
    user_id, type, amount, currency, status, approval_status,
    method, note, request_id, settled_at
  ) values (
    v_intent.user_id, 'deposit', v_intent.target_bdx, 'BDX',
    'completed', 'approved', 'Bitcoin',
    'Verified Bitcoin deposit intent ' || v_intent.id::text,
    v_intent.id, now()
  ) returning * into v_tx;

  update public.bitcoin_deposit_intent
     set status = 'credited', updated_at = now()
   where id = v_intent.id;

  return v_tx;
end;
$function$;

revoke all on function public.credit_verified_bitcoin_deposit(uuid) from public, anon, authenticated;
grant execute on function public.credit_verified_bitcoin_deposit(uuid) to service_role;

comment on function public.credit_verified_bitcoin_deposit(uuid) is
  'Atomically credits the requested BDX amount for a previously verified BTC deposit. Service-role only; requires a trusted verifier to mark the intent verified and record a matching output with at least 3 confirmations.';

commit;
