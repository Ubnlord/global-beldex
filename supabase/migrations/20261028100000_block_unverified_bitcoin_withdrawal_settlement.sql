begin;

-- Bitcoin payouts are not yet executed by a trusted wallet service. Prevent
-- generic admin settlement RPCs from marking a BTC withdrawal completed
-- without an on-chain payout record. This preserves existing settlement
-- behavior for other currencies and methods.
create or replace function public.admin_settle_transaction(
  p_transaction_id uuid,
  p_reason text default null
)
returns public.transaction
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_admin public.admin_user;
  v_tx public.transaction;
  v_currency text;
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then
    raise exception 'Permission denied';
  end if;

  select * into v_admin
    from public.admin_user
   where user_id = auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;

  select * into v_tx
    from public.transaction
   where id = p_transaction_id
   for update;
  if not found then raise exception 'Transaction not found'; end if;
  if v_tx.type not in ('deposit','withdraw') then
    raise exception 'Only deposit and withdrawal can be settled';
  end if;
  if v_tx.status = 'completed' then raise exception 'Transaction already completed'; end if;
  if v_tx.approval_status <> 'approved' then raise exception 'Transaction must be approved first'; end if;

  -- Fail closed: an approval is not evidence that BTC was broadcast or paid.
  -- A future payout service must verify and persist the txid before settlement.
  if v_tx.type = 'withdraw' and upper(coalesce(v_tx.method, '')) = 'BITCOIN' then
    raise exception 'Bitcoin withdrawal cannot be settled until a secure payout workflow records and verifies the on-chain transaction ID';
  end if;

  v_currency := coalesce(v_tx.currency, 'USD');
  if v_currency not in ('USD','BDX') then raise exception 'Unsupported transaction currency'; end if;

  if v_tx.type = 'deposit' then
    if v_currency = 'BDX' then
      update public.user_profile
         set bdx_balance = bdx_balance + v_tx.amount,
             total_deposits_bdx = total_deposits_bdx + v_tx.amount,
             updated_at = now()
       where user_id = v_tx.user_id;
    else
      update public.user_profile
         set available_balance = available_balance + v_tx.amount,
             total_deposits = total_deposits + v_tx.amount,
             updated_at = now()
       where user_id = v_tx.user_id;
    end if;
  elsif v_currency = 'BDX' then
    update public.user_profile
       set total_withdrawals_bdx = total_withdrawals_bdx + v_tx.amount,
           updated_at = now()
     where user_id = v_tx.user_id;
  else
    update public.user_profile
       set total_withdrawals = total_withdrawals + v_tx.amount,
           updated_at = now()
     where user_id = v_tx.user_id;
  end if;
  if not found then raise exception 'User profile not found during settlement'; end if;

  update public.transaction
     set status = 'completed', settled_at = now(), updated_at = now()
   where id = p_transaction_id
   returning * into v_tx;

  if v_tx.type = 'deposit' then
    perform public.credit_referral_for_deposit(v_tx.id);
  end if;

  insert into public.transaction_audit(
    transaction_id, admin_id, action, old_values, new_values, reason
  ) values (
    v_tx.id, v_admin.id, 'settled',
    jsonb_build_object('status', 'pending'),
    jsonb_build_object('status', v_tx.status, 'currency', v_currency),
    p_reason
  );

  return v_tx;
end;
$function$;

comment on function public.admin_settle_transaction(uuid, text) is
  'Admin settlement with fail-closed protection: Bitcoin withdrawals cannot be marked completed until a secure payout workflow records and verifies an on-chain transaction ID.';

commit;
