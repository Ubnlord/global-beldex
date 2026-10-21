begin;

-- Enforce one fixed 400 BDX referral reward per referred user, not per deposit.
-- Existing per-deposit markers are recognized to avoid issuing another
-- reward to users who were already rewarded by the previous implementation.
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

  -- One reward per referred user. Recognize both the new stable marker and
  -- legacy per-deposit markers so existing rewards cannot be repeated.
  if exists (
    select 1
    from public.transaction r
    where r.type = 'referral'
      and r.user_id = v_ref
      and (
        r.method = 'Referral user ' || v_tx.user_id::text
        or exists (
          select 1
          from public.transaction prior_deposit
          where prior_deposit.user_id = v_tx.user_id
            and prior_deposit.type = 'deposit'
            and r.method = 'Referral deposit ' || prior_deposit.id::text
        )
      )
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
    'Referral user ' || v_tx.user_id::text,
    'Fixed 400 BDX referral bonus for first eligible completed deposit'
  );

  return v_cut;
end;
$function$;

revoke all on function public.credit_referral_for_deposit(uuid)
  from public, anon, authenticated;

commit;
