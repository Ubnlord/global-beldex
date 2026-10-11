begin;

-- BDX-native account accounting. This migration is deliberately non-destructive:
-- existing balances, investments, and historical transactions are not converted.
-- Legacy USD wallet columns remain for backward compatibility and reconciliation,
-- but all new deposits/withdrawals and future investments are BDX-denominated.
alter table public.user_profile
  add column if not exists total_deposits_bdx numeric(38,18) not null default 0,
  add column if not exists total_withdrawals_bdx numeric(38,18) not null default 0;

comment on column public.user_profile.bdx_balance is
  'Canonical available wallet balance denominated in BDX.';
comment on column public.user_profile.locked_bdx_balance is
  'Canonical reserved/locked wallet balance denominated in BDX.';
comment on column public.user_profile.total_deposits_bdx is
  'Completed deposit volume denominated in BDX; never combine with legacy USD totals.';
comment on column public.user_profile.total_withdrawals_bdx is
  'Completed withdrawal volume denominated in BDX; never combine with legacy USD totals.';

-- New deposit and withdrawal requests accept a requested denomination from older
-- clients, but normalize the ledger amount to BDX in the trusted database RPC.
-- The current platform quote is a fixed configuration value already used by the
-- existing deposit/withdraw UI: 4,000 BDX = 293.984 USD.
-- Conversion metadata is stored in note for audit; request idempotency is retained.
-- Retire the legacy five-argument overload. Existing admin functions and callers
-- must go through the currency-aware RPC; no new transaction may be booked to USD wallet.
drop function if exists public.create_financial_transaction(text,numeric,text,text,uuid);

create or replace function public.create_financial_transaction(
  p_type text,
  p_amount numeric,
  p_method text default null,
  p_note text default null,
  p_request_id uuid default null,
  p_currency text default 'USD'
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
  v_tx public.transaction;
  v_profile public.user_profile;
  v_input_currency text := upper(coalesce(p_currency,'USD'));
  v_ledger_amount numeric(38,18);
  v_rate numeric(38,18) := 293.984 / 4000;
  v_note jsonb;
  v_destination text;
  v_existing_note jsonb;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  if p_type not in ('deposit','withdraw') then raise exception 'Invalid transaction type'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be greater than zero'; end if;
  if v_input_currency not in ('BDX','USD') then raise exception 'Unsupported input currency'; end if;
  perform public.assert_user_can_transact(v_uid);

  if p_request_id is not null then
    select * into v_tx from public.transaction
      where user_id=v_uid and request_id=p_request_id limit 1;
    if found then
      -- For retries, compare the submitted values/metadata, not the normalized
      -- BDX ledger amount, to avoid accidental duplicate wallet requests.
      v_existing_note := case
        when coalesce(v_tx.note,'') like '{%' then v_tx.note::jsonb
        else '{}'::jsonb
      end;
      if v_tx.type <> p_type
        or coalesce(v_existing_note->>'input_amount','') <> p_amount::text
        or upper(coalesce(v_existing_note->>'input_currency','USD')) <> v_input_currency then
        raise exception 'Request ID was already used for a different transaction';
      end if;
      return v_tx;
    end if;
  end if;

  v_ledger_amount := case when v_input_currency='BDX'
    then p_amount else p_amount / v_rate end;
  v_destination := btrim(coalesce(p_note,''));
  v_note := jsonb_build_object(
    'version', 1,
    'input_amount', p_amount,
    'input_currency', v_input_currency,
    'ledger_currency', 'BDX',
    'usd_per_bdx', v_rate,
    'converted_bdx', v_ledger_amount,
    'user_note', case when p_type='deposit' then p_note else null end
  );

  if v_ledger_amount < 4000 then
    raise exception 'Minimum % is 4,000 BDX (equivalent to USD at the platform rate)', p_type;
  end if;

  if p_type='withdraw' then
    if v_destination='' then raise exception 'Please enter a destination address'; end if;
    if p_method not in ('Bitcoin','Ethereum','Beldex') then raise exception 'Invalid withdrawal method'; end if;
    if p_method='Ethereum' and v_destination !~ '^0x[0-9A-Fa-f]{40}$' then
      raise exception 'Invalid Ethereum destination address';
    end if;
    if p_method='Bitcoin'
      and v_destination !~* '^bc1[ac-hj-np-z02-9]{11,71}$'
      and v_destination !~ '^[13][1-9A-HJ-NP-Za-km-z]{25,34}$'
    then raise exception 'Invalid Bitcoin destination address'; end if;
    if p_method='Beldex' and (
      v_destination !~ '^[1-9A-HJ-NP-Za-km-z]+$'
      or length(v_destination)<90 or length(v_destination)>110
    ) then raise exception 'Invalid Beldex destination address'; end if;
  end if;

  select * into v_profile from public.user_profile where user_id=v_uid for update;
  if v_profile.user_id is null then raise exception 'Profile not found'; end if;

  if p_request_id is not null then
    select * into v_tx from public.transaction where user_id=v_uid and request_id=p_request_id limit 1;
    if found then return v_tx; end if;
  end if;

  if p_type='withdraw' then
    update public.user_profile
      set bdx_balance=bdx_balance-v_ledger_amount,updated_at=now()
      where user_id=v_uid and bdx_balance>=v_ledger_amount;
    if not found then raise exception 'Insufficient BDX balance'; end if;
  end if;

  insert into public.transaction(
    user_id,type,amount,currency,status,approval_status,method,note,request_id
  ) values (
    v_uid,p_type,v_ledger_amount,'BDX','pending','awaiting',p_method,
    case when p_type='withdraw' then v_note || jsonb_build_object('destination_hash_hint', right(v_destination,6))
         else v_note end::text,
    p_request_id
  ) returning * into v_tx;

  return v_tx;
exception when unique_violation then
  if p_request_id is not null then
    select * into v_tx from public.transaction where user_id=v_uid and request_id=p_request_id limit 1;
    if found then return v_tx; end if;
  end if;
  raise;
end;
$function$;

revoke all on function public.create_financial_transaction(text,numeric,text,text,uuid,text) from public,anon;
grant execute on function public.create_financial_transaction(text,numeric,text,text,uuid,text) to authenticated;

-- Settlement credits only the BDX wallet and BDX-denominated running totals.
create or replace function public.admin_settle_transaction(p_transaction_id uuid,p_reason text default null)
returns public.transaction
language plpgsql security definer
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
  if v_tx.type not in ('deposit','withdraw') then raise exception 'Only deposit and withdrawal can be settled'; end if;
  if v_tx.status='completed' then raise exception 'Transaction already completed'; end if;
  if v_tx.approval_status<>'approved' then raise exception 'Transaction must be approved first'; end if;
  if coalesce(v_tx.currency,'USD') <> 'BDX' then
    -- Historical USD requests are not converted implicitly; prevent them from
    -- being miscredited under the new BDX-only ledger. Admin must reconcile them.
    raise exception 'Legacy USD transaction requires manual reconciliation before settlement';
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

  update public.transaction set status='completed',settled_at=now(),updated_at=now()
    where id=p_transaction_id returning * into v_tx;
  insert into public.transaction_audit(transaction_id,admin_id,action,old_values,new_values,reason)
  values(v_tx.id,v_admin.id,'settled',
    jsonb_build_object('status','pending'),
    jsonb_build_object('status',v_tx.status,'currency','BDX','amount',v_tx.amount),p_reason);
  return v_tx;
end;
$function$;

revoke all on function public.admin_settle_transaction(uuid,text) from public,anon;
grant execute on function public.admin_settle_transaction(uuid,text) to authenticated;

-- A rejected withdrawal returns the reserved amount to the same BDX wallet.
create or replace function public.admin_reject_transaction(p_transaction_id uuid,p_reason text)
returns public.transaction
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_tx public.transaction;
begin
  if not public.is_admin() or not public.admin_has_permission('reject_transactions') then
    raise exception 'Permission denied';
  end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'Rejection reason is required'; end if;
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.approval_status<>'awaiting' then raise exception 'Transaction is not awaiting approval'; end if;

  if v_tx.type='withdraw' then
    if coalesce(v_tx.currency,'USD')='BDX' then
      update public.user_profile set bdx_balance=bdx_balance+v_tx.amount,updated_at=now()
        where user_id=v_tx.user_id;
    else
      update public.user_profile set available_balance=available_balance+v_tx.amount,updated_at=now()
        where user_id=v_tx.user_id;
    end if;
  end if;

  update public.transaction set approval_status='rejected',status='failed',approved_by=v_admin.id,
    approval_reason=p_reason,approved_at=now(),updated_at=now()
    where id=p_transaction_id returning * into v_tx;
  insert into public.transaction_audit(transaction_id,admin_id,action,old_values,new_values,reason)
  values(v_tx.id,v_admin.id,'rejected',
    jsonb_build_object('approval_status','awaiting'),
    jsonb_build_object('approval_status',v_tx.approval_status,'status',v_tx.status,'currency',v_tx.currency),p_reason);
  return v_tx;
end;
$function$;

revoke all on function public.admin_reject_transaction(uuid,text) from public,anon;
grant execute on function public.admin_reject_transaction(uuid,text) to authenticated;

-- Enforce the new accounting unit on internal categories. Existing USD records
-- remain historical; future BDX transaction creation is the app's only path.
create or replace function public.admin_adjust_balance(p_user_id uuid,p_delta numeric,p_reason text)
returns public.user_profile
language plpgsql security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_profile public.user_profile;
begin
  if not public.is_admin() or not public.admin_has_permission('manage_users') then
    raise exception 'Permission denied';
  end if;
  if p_delta is null or p_delta=0 then raise exception 'Adjustment must be non-zero'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'Reason is required'; end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  select * into v_profile from public.user_profile where user_id=p_user_id for update;
  if v_profile.user_id is null then raise exception 'Profile not found'; end if;
  if v_profile.blocked then raise exception 'Blocked users cannot have balances adjusted'; end if;
  if v_profile.bdx_balance+p_delta<0 then raise exception 'Adjustment would make BDX balance negative'; end if;

  update public.user_profile set bdx_balance=bdx_balance+p_delta,updated_at=now()
    where user_id=p_user_id returning * into v_profile;
  insert into public.admin_action_audit(admin_id,user_id,action,target_id,old_values,new_values,reason)
  values(v_admin.id,p_user_id,'adjust_bdx_balance',p_user_id,
    jsonb_build_object('bdx_balance',v_profile.bdx_balance-p_delta),
    jsonb_build_object('bdx_balance',v_profile.bdx_balance),p_reason);
  return v_profile;
end;
$function$;
revoke all on function public.admin_adjust_balance(uuid,numeric,text) from public,anon;
grant execute on function public.admin_adjust_balance(uuid,numeric,text) to authenticated;

commit;
