begin;

-- Standardize each eligible referral reward to a fixed 400 BDX.
-- The reward is credited in BDX regardless of the deposit's currency.
-- The existing referral transaction marker preserves idempotency per deposit.
create or replace function public.credit_referral_for_deposit(p_transaction_id uuid)
returns numeric
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_tx public.transaction;
  v_ref uuid;
  v_cut numeric := 400;
begin
  select * into v_tx
    from public.transaction
    where id = p_transaction_id
    for update;

  if not found then
    raise exception 'Transaction not found';
  end if;
  if v_tx.type <> 'deposit' or v_tx.status <> 'completed' then
    return 0;
  end if;

  select referred_by_user_id into v_ref
    from public.user_profile
    where user_id = v_tx.user_id;

  if v_ref is null or v_ref = v_tx.user_id then
    return 0;
  end if;

  -- One referral reward per settled deposit, even on retries.
  if exists (
    select 1 from public.transaction
    where type = 'referral'
      and method = 'Referral deposit ' || v_tx.id::text
  ) then
    return 0;
  end if;

  update public.user_profile
    set bdx_balance = bdx_balance + v_cut,
        referral_earnings_bdx = referral_earnings_bdx + v_cut,
        updated_at = now()
    where user_id = v_ref;

  if not found then
    raise exception 'Referrer profile not found';
  end if;

  insert into public.transaction(
    user_id, type, amount, currency, status, approval_status, method, note
  ) values (
    v_ref, 'referral', v_cut, 'BDX', 'completed', 'approved',
    'Referral deposit ' || v_tx.id::text,
    'Fixed 400 BDX referral bonus for eligible completed deposit'
  );

  return v_cut;
end;
$function$;

revoke all on function public.credit_referral_for_deposit(uuid)
  from public, anon, authenticated;

commit;
