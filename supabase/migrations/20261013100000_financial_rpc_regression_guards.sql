begin;

-- Remove the unsafe legacy overload. The six-argument currency-aware RPC has
-- p_currency defaulted, so legacy five-argument callers resolve to that
-- implementation and receive its request-ID consistency checks.
drop function if exists public.create_financial_transaction(text,numeric,text,text,uuid);
drop function if exists public.create_financial_transaction(text,numeric,text,text,uuid,text);

-- Preserve five-argument callers by making the currency-aware overload's
-- final parameter default to USD after removing the unsafe five-argument body.
create function public.create_financial_transaction(
  p_type text,
  p_amount numeric,
  p_method text,
  p_note text,
  p_request_id uuid,
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
  v_currency text := upper(coalesce(p_currency,'USD'));
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  if p_type not in ('deposit','withdraw') then raise exception 'Invalid transaction type'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be greater than zero'; end if;
  if v_currency not in ('BDX','USD') then raise exception 'Unsupported currency'; end if;
  perform public.assert_user_can_transact(v_uid);

  if p_request_id is not null then
    select * into v_tx from public.transaction where user_id=v_uid and request_id=p_request_id limit 1;
    if found then
      if v_tx.type <> p_type or v_tx.amount <> p_amount or upper(coalesce(v_tx.currency,'USD')) <> v_currency then
        raise exception 'Request ID was already used for a different transaction';
      end if;
      return v_tx;
    end if;
  end if;

  if p_type='withdraw' then
    if v_currency='BDX' then
      update public.user_profile set bdx_balance=bdx_balance-p_amount,updated_at=now()
      where user_id=v_uid and bdx_balance>=p_amount;
    else
      update public.user_profile set available_balance=available_balance-p_amount,updated_at=now()
      where user_id=v_uid and available_balance>=p_amount;
    end if;
    if not found then raise exception 'Insufficient % balance',v_currency; end if;
  end if;

  insert into public.transaction(user_id,type,amount,currency,status,approval_status,method,note,request_id)
  values(v_uid,p_type,p_amount,v_currency,'pending','awaiting',p_method,p_note,p_request_id)
  returning * into v_tx;
  return v_tx;
exception when unique_violation then
  if p_request_id is not null then
    select * into v_tx from public.transaction where user_id=v_uid and request_id=p_request_id limit 1;
    if found and v_tx.type=p_type and v_tx.amount=p_amount and upper(coalesce(v_tx.currency,'USD'))=v_currency then return v_tx; end if;
    if found then raise exception 'Request ID was already used for a different transaction'; end if;
  end if;
  raise;
end;
$function$;

revoke all on function public.create_financial_transaction(text,numeric,text,text,uuid,text) from public, anon;
grant execute on function public.create_financial_transaction(text,numeric,text,text,uuid,text) to authenticated, service_role;

-- Keep investment principal in the same denomination as its wallet. The prior
-- implementation always moved principal through the USD columns, even for BDX
-- investments. This correction does not rewrite existing financial records.
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
  v_inv public.user_investment;
  v_profile public.user_profile;
  v_admin public.admin_user;
  v_currency text;
  v_old_status text;
begin
  if auth.uid() is null or not public.is_admin()
     or not public.admin_has_permission('manage_users') then
    raise exception 'not authorized';
  end if;
  select * into v_admin from public.admin_user where user_id = auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  if p_daily_rate is null or p_daily_rate < 0 then
    raise exception 'invalid daily rate';
  end if;
  if p_status not in ('active','completed','cancelled') then
    raise exception 'invalid investment status';
  end if;
  if nullif(btrim(coalesce(p_reason,'')), '') is null then
    raise exception 'reason is required';
  end if;

  select * into v_inv
    from public.user_investment
   where id = p_investment_id
   for update;
  if not found then raise exception 'investment not found'; end if;
  v_old_status := v_inv.status;
  v_currency := coalesce(v_inv.currency,'USD');
  if v_currency not in ('USD','BDX') then
    raise exception 'unsupported investment currency';
  end if;

  select * into v_profile
    from public.user_profile
   where user_id = v_inv.user_id
   for update;
  if not found then raise exception 'user profile not found'; end if;
  if v_profile.blocked then
    raise exception 'blocked user cannot have investment managed';
  end if;

  if v_old_status = 'active' and p_status in ('completed','cancelled') then
    if v_currency = 'BDX' then
      update public.user_profile
         set locked_bdx_balance = locked_bdx_balance - v_inv.principal,
             bdx_balance = bdx_balance + v_inv.principal,
             updated_at = now()
       where user_id = v_inv.user_id
         and locked_bdx_balance >= v_inv.principal;
    else
      update public.user_profile
         set locked_balance = locked_balance - v_inv.principal,
             available_balance = available_balance + v_inv.principal,
             updated_at = now()
       where user_id = v_inv.user_id
         and locked_balance >= v_inv.principal;
    end if;
    if not found then
      raise exception 'locked balance is below investment principal';
    end if;
  elsif v_old_status in ('completed','cancelled') and p_status = 'active' then
    if v_currency = 'BDX' then
      update public.user_profile
         set bdx_balance = bdx_balance - v_inv.principal,
             locked_bdx_balance = locked_bdx_balance + v_inv.principal,
             updated_at = now()
       where user_id = v_inv.user_id
         and bdx_balance >= v_inv.principal;
    else
      update public.user_profile
         set available_balance = available_balance - v_inv.principal,
             locked_balance = locked_balance + v_inv.principal,
             updated_at = now()
       where user_id = v_inv.user_id
         and available_balance >= v_inv.principal;
    end if;
    if not found then
      raise exception 'insufficient available balance for investment currency';
    end if;
  end if;

  update public.user_investment
     set daily_rate = p_daily_rate,
         status = p_status,
         completed_at = case
           when p_status in ('completed','cancelled') then coalesce(completed_at, now())
           else null
         end,
         updated_at = now()
   where id = p_investment_id
  returning * into v_inv;

  insert into public.admin_action_audit
    (admin_id, user_id, action, target_id, old_values, new_values, reason, created_at)
  values
    (v_admin.id, v_inv.user_id, 'manage_investment', v_inv.id,
     jsonb_build_object('status', v_old_status, 'currency', v_currency),
     jsonb_build_object('status', v_inv.status, 'daily_rate', v_inv.daily_rate, 'currency', v_currency),
     btrim(p_reason), now());

  return v_inv;
end;
$function$;

revoke all on function public.admin_manage_investment(uuid,numeric,text,text) from public, anon;
grant execute on function public.admin_manage_investment(uuid,numeric,text,text) to authenticated, service_role;


-- Settlement must only complete an approved transaction from the pending state.
-- Policy: blocked accounts cannot receive new deposits, but previously approved
-- withdrawals may settle (their funds were already reserved); withdrawal refunds
-- on rejection are allowed so users are not deprived of their reserved funds.
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
  v_profile public.user_profile;
  v_currency text;
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then
    raise exception 'Permission denied';
  end if;
  select * into v_admin from public.admin_user where user_id = auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;

  select * into v_tx from public.transaction where id = p_transaction_id for update;
  if not found then raise exception 'Transaction not found'; end if;
  if v_tx.type not in ('deposit','withdraw') then
    raise exception 'Only deposit and withdrawal can be settled';
  end if;
  if v_tx.status <> 'pending' then
    raise exception 'Transaction must be pending to settle';
  end if;
  if v_tx.approval_status <> 'approved' then
    raise exception 'Transaction must be approved first';
  end if;
  v_currency := coalesce(v_tx.currency,'USD');
  if v_currency not in ('USD','BDX') then raise exception 'Unsupported transaction currency'; end if;

  select * into v_profile from public.user_profile where user_id=v_tx.user_id for update;
  if not found then raise exception 'User profile not found during settlement'; end if;
  if v_tx.type='deposit' and v_profile.blocked then
    raise exception 'Blocked account cannot receive a deposit';
  end if;

  if v_tx.type='deposit' then
    if v_currency='BDX' then
      update public.user_profile set bdx_balance=bdx_balance+v_tx.amount,
        total_deposits_bdx=total_deposits_bdx+v_tx.amount,updated_at=now()
      where user_id=v_tx.user_id;
    else
      update public.user_profile set available_balance=available_balance+v_tx.amount,
        total_deposits=total_deposits+v_tx.amount,updated_at=now()
      where user_id=v_tx.user_id;
    end if;
  elsif v_currency='BDX' then
    update public.user_profile set total_withdrawals_bdx=total_withdrawals_bdx+v_tx.amount,updated_at=now()
    where user_id=v_tx.user_id;
  else
    update public.user_profile set total_withdrawals=total_withdrawals+v_tx.amount,updated_at=now()
    where user_id=v_tx.user_id;
  end if;

  update public.transaction set status='completed',settled_at=now(),updated_at=now()
  where id=p_transaction_id returning * into v_tx;
  if v_tx.type='deposit' then perform public.credit_referral_for_deposit(v_tx.id); end if;
  insert into public.transaction_audit(transaction_id,admin_id,action,old_values,new_values,reason)
  values(v_tx.id,v_admin.id,'settled',jsonb_build_object('status','pending'),
    jsonb_build_object('status',v_tx.status,'currency',v_currency),p_reason);
  return v_tx;
end;
$function$;

revoke all on function public.admin_settle_transaction(uuid,text) from public, anon;
grant execute on function public.admin_settle_transaction(uuid,text) to authenticated, service_role;

-- An administrator may not raise an investment above its plan's published
-- catalog rate. This avoids inventing a global rate cap; the plan catalog is
-- the existing business rule. Unknown plans are rejected for rate changes.
create or replace function public.admin_update_investment(
  p_investment_id uuid,
  p_daily_rate numeric default null,
  p_daily_accrual_enabled boolean default null
)
returns public.user_investment
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin public.admin_user;
  v_old public.user_investment;
  v_new public.user_investment;
  v_max_rate numeric;
  v_blocked boolean;
begin
  if not public.is_admin() or not public.admin_has_permission('manage_users') then
    raise exception 'Permission denied';
  end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  select * into v_old from public.user_investment where id=p_investment_id for update;
  if v_old.id is null then raise exception 'Investment not found'; end if;

  select blocked into v_blocked from public.user_profile where user_id=v_old.user_id for update;
  if not found then raise exception 'User profile not found'; end if;
  if v_blocked then raise exception 'Blocked user investment cannot be updated'; end if;
  if p_daily_rate is not null and p_daily_rate < 0 then raise exception 'Daily rate cannot be negative'; end if;

  if p_daily_rate is not null then
    select daily_rate into v_max_rate from public.investment_plan_catalog where id=v_old.plan_id and active=true;
    if not found then raise exception 'No active catalog rate found for investment plan'; end if;
    if p_daily_rate > v_max_rate then raise exception 'Daily rate exceeds published plan rate'; end if;
  end if;

  update public.user_investment
  set daily_rate=coalesce(p_daily_rate,daily_rate),
      daily_accrual_enabled=coalesce(p_daily_accrual_enabled,daily_accrual_enabled),
      updated_at=now()
  where id=p_investment_id returning * into v_new;

  insert into public.admin_action_audit(admin_id,user_id,action,target_id,old_values,new_values,reason,created_at)
  values(v_admin.id,v_old.user_id,'investment_updated',p_investment_id,
    jsonb_build_object('daily_rate',v_old.daily_rate,'daily_accrual_enabled',v_old.daily_accrual_enabled),
    jsonb_build_object('daily_rate',v_new.daily_rate,'daily_accrual_enabled',v_new.daily_accrual_enabled),
    'Administrator updated investment accrual settings',now());
  return v_new;
end;
$function$;

revoke all on function public.admin_update_investment(uuid,numeric,boolean) from public, anon;
grant execute on function public.admin_update_investment(uuid,numeric,boolean) to authenticated, service_role;

commit;
