begin;

-- Forward-only production compatibility repair.
-- The observed production migration ledger does not contain the original
-- bdx_native_accounting migration, and user_profile lacks this BDX counter.
-- Preserve all existing USD balances, historical transactions, and legacy
-- referral_earnings values; do not convert or backfill historical USD amounts.
alter table public.user_profile
  add column if not exists referral_earnings_bdx numeric(38,18) not null default 0;

comment on column public.user_profile.referral_earnings_bdx is
  'Referral earnings denominated in BDX; legacy referral_earnings remains untouched for reconciliation.';

-- The current production implementation is USD-oriented. Replace it with an
-- idempotent BDX-only credit path. Historical USD deposits are deliberately
-- ineligible; this routine does not mutate legacy USD fields.
create or replace function public.credit_referral_for_deposit(p_transaction_id uuid)
returns numeric
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_tx public.transaction;
  v_ref uuid;
  v_cut numeric;
begin
  if auth.uid() is not null then
    if not public.is_admin() or not public.admin_has_permission('approve_transactions') then
      raise exception 'Permission denied';
    end if;
  end if;

  select * into v_tx
  from public.transaction
  where id = p_transaction_id
  for update;

  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.type <> 'deposit'
     or v_tx.status <> 'completed'
     or coalesce(v_tx.currency, 'USD') <> 'BDX' then
    return 0;
  end if;

  select referred_by_user_id
    into v_ref
    from public.user_profile
    where user_id = v_tx.user_id;

  if v_ref is null then return 0; end if;

  -- Use the existing transaction marker to make repeated settlement calls safe.
  if exists (
    select 1 from public.transaction
    where method = 'Referral deposit ' || v_tx.id::text
  ) then
    return 0;
  end if;

  v_cut := round(v_tx.amount * 0.10, 18);
  if v_cut <= 0 then return 0; end if;

  update public.user_profile
  set bdx_balance = bdx_balance + v_cut,
      referral_earnings_bdx = referral_earnings_bdx + v_cut,
      updated_at = now()
  where user_id = v_ref;

  if not found then
    raise exception 'Referrer profile not found';
  end if;

  insert into public.transaction
    (user_id, type, amount, currency, status, approval_status, method, note)
  values
    (v_ref, 'referral', v_cut, 'BDX', 'completed', 'approved',
     'Referral deposit ' || v_tx.id::text, '10% referral commission (BDX)');

  return v_cut;
end;
$function$;

-- This routine is called from the privileged settlement RPC. Authenticated
-- direct calls still require admin approval permission; anonymous/public access
-- is removed, and service_role retains the server-side path.
revoke all on function public.credit_referral_for_deposit(uuid) from public, anon;
grant execute on function public.credit_referral_for_deposit(uuid) to authenticated, service_role;

commit;
