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

-- BDX-only, idempotent referral credit. Historical USD deposits are deliberately
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

  if not found then raise exception 'Referrer profile not found'; end if;

  insert into public.transaction
    (user_id, type, amount, currency, status, approval_status, method, note)
  values
    (v_ref, 'referral', v_cut, 'BDX', 'completed', 'approved',
     'Referral deposit ' || v_tx.id::text, '10% referral commission (BDX)');

  return v_cut;
end;
$function$;

revoke all on function public.credit_referral_for_deposit(uuid) from public, anon;
grant execute on function public.credit_referral_for_deposit(uuid) to authenticated, service_role;

-- Replace the production settlement routine with a BDX-only version. Historical
-- USD transactions remain untouched and cannot be accidentally settled into the
-- new BDX wallet; they require a separately reviewed manual reconciliation.
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
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then
    raise exception 'Permission denied';
  end if;

  select * into v_admin from public.admin_user where user_id = auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;

  select * into v_tx
  from public.transaction
  where id = p_transaction_id
  for update;

  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.type not in ('deposit', 'withdraw') then
    raise exception 'Only deposit and withdrawal can be settled';
  end if;
  if v_tx.status = 'completed' then raise exception 'Transaction already completed'; end if;
  if v_tx.approval_status <> 'approved' then
    raise exception 'Transaction must be approved first';
  end if;
  if coalesce(v_tx.currency, 'USD') <> 'BDX' then
    raise exception 'Legacy USD transaction requires manual reconciliation before settlement';
  end if;

  if v_tx.type = 'deposit' then
    update public.user_profile
    set bdx_balance = bdx_balance + v_tx.amount,
        total_deposits_bdx = total_deposits_bdx + v_tx.amount,
        updated_at = now()
    where user_id = v_tx.user_id;
  else
    update public.user_profile
    set total_withdrawals_bdx = total_withdrawals_bdx + v_tx.amount,
        updated_at = now()
    where user_id = v_tx.user_id;
  end if;

  update public.transaction
  set status = 'completed', settled_at = now(), updated_at = now()
  where id = p_transaction_id
  returning * into v_tx;

  if v_tx.type = 'deposit' then
    perform public.credit_referral_for_deposit(v_tx.id);
  end if;

  insert into public.transaction_audit
    (transaction_id, admin_id, action, old_values, new_values, reason)
  values (
    v_tx.id, v_admin.id, 'settled',
    jsonb_build_object('status', 'pending'),
    jsonb_build_object('status', v_tx.status, 'currency', 'BDX', 'amount', v_tx.amount),
    p_reason
  );

  return v_tx;
end;
$function$;

revoke all on function public.admin_settle_transaction(uuid, text) from public, anon;
grant execute on function public.admin_settle_transaction(uuid, text) to authenticated;

commit;
