begin;

-- Security hardening v1.
-- Final authorization must be enforced by PostgreSQL, not only by the UI/server route.

create or replace function public.admin_has_permission(p_permission text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
  select exists (
    select 1
    from public.admin_user a
    where a.user_id = auth.uid()
      and (a.role = 'admin' or p_permission = any(a.permissions))
  );
$function$;

revoke all on function public.admin_has_permission(text) from public, anon;
grant execute on function public.admin_has_permission(text) to authenticated;

-- Blocked accounts must never be able to create or execute financial activity.
create or replace function public.assert_user_can_transact(p_user_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_blocked boolean;
begin
  if p_user_id is null then
    raise exception 'Unauthorized';
  end if;

  select blocked into v_blocked
  from public.user_profile
  where user_id = p_user_id;

  if not found then
    raise exception 'Profile not found';
  end if;

  if coalesce(v_blocked, false) then
    raise exception 'User account is blocked';
  end if;
end;
$function$;

revoke all on function public.assert_user_can_transact(uuid) from public, anon, authenticated;
grant execute on function public.assert_user_can_transact(uuid) to authenticated;

-- Idempotency key for client-originated deposit/withdrawal requests.
alter table public.transaction
  add column if not exists request_id uuid;

create unique index if not exists transaction_user_request_id_uq
  on public.transaction(user_id, request_id)
  where request_id is not null;

-- Replace the browser-callable financial request function with an idempotent version.
drop function if exists public.create_financial_transaction(text,numeric,text,text);

create or replace function public.create_financial_transaction(
  p_type text,
  p_amount numeric,
  p_method text default null,
  p_note text default null,
  p_request_id uuid default null
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
  v_tx public.transaction;
begin
  if v_uid is null then
    raise exception 'Unauthorized';
  end if;

  if p_type not in ('deposit','withdraw') then
    raise exception 'Invalid transaction type';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;

  perform public.assert_user_can_transact(v_uid);

  if p_request_id is not null then
    select * into v_tx
    from public.transaction
    where user_id = v_uid and request_id = p_request_id
    limit 1;

    if found then
      return v_tx;
    end if;
  end if;

  if p_type = 'withdraw' then
    update public.user_profile
    set available_balance = available_balance - p_amount,
        updated_at = now()
    where user_id = v_uid
      and available_balance >= p_amount;

    if not found then
      raise exception 'Insufficient balance';
    end if;
  end if;

  insert into public.transaction(
    user_id,type,amount,status,approval_status,method,note,request_id
  )
  values (
    v_uid,p_type,p_amount,'pending','awaiting',p_method,p_note,p_request_id
  )
  returning * into v_tx;

  return v_tx;
exception
  when unique_violation then
    if p_request_id is not null then
      select * into v_tx
      from public.transaction
      where user_id = v_uid and request_id = p_request_id
      limit 1;
      if found then
        return v_tx;
      end if;
    end if;
    raise;
end;
$function$;

revoke all on function public.create_financial_transaction(text,numeric,text,text,uuid) from public, anon;
grant execute on function public.create_financial_transaction(text,numeric,text,text,uuid) to authenticated;

-- Investment purchases are also blocked at the database boundary.
create or replace function public.buy_investment_plan(p_plan_id text,p_amount numeric)
returns public.user_investment
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
  v_plan public.investment_plan_catalog;
  v_profile public.user_profile;
  v_inv public.user_investment;
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;
  perform public.assert_user_can_transact(v_uid);

  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be greater than zero'; end if;

  select * into v_plan
  from public.investment_plan_catalog
  where id = p_plan_id and active;

  if v_plan.id is null then raise exception 'Investment plan not found'; end if;
  if p_amount < v_plan.min_amount then raise exception 'Minimum investment is %',v_plan.min_amount; end if;
  if v_plan.max_amount is not null and p_amount > v_plan.max_amount then
    raise exception 'Maximum investment is %',v_plan.max_amount;
  end if;

  select * into v_profile
  from public.user_profile
  where user_id = v_uid
  for update;

  if v_profile.user_id is null then raise exception 'Profile not found'; end if;
  if v_profile.available_balance < p_amount then raise exception 'Insufficient balance'; end if;

  update public.user_profile
  set available_balance = available_balance - p_amount,
      locked_balance = locked_balance + p_amount,
      updated_at = now()
  where user_id = v_uid;

  insert into public.user_investment(
    user_id,plan_id,principal,daily_rate,duration_days
  )
  values(
    v_uid,v_plan.id,p_amount,v_plan.daily_rate,v_plan.duration_days
  )
  returning * into v_inv;

  insert into public.transaction(
    user_id,type,amount,status,approval_status,method,note
  )
  values(
    v_uid,'plan',p_amount,'completed','approved',
    v_plan.name,'Investment plan purchase'
  );

  return v_inv;
end;
$function$;

revoke all on function public.buy_investment_plan(text,numeric) from public, anon;
grant execute on function public.buy_investment_plan(text,numeric) to authenticated;

-- Only an admin with manage_users may manually accrue a user's investment.
create or replace function public.accrue_user_investments(p_user_id uuid default auth.uid())
returns numeric
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_uid uuid := coalesce(p_user_id,auth.uid());
  v_inv public.user_investment;
  v_now timestamptz := now();
  v_elapsed_days integer;
  v_previous_days integer;
  v_days integer;
  v_profit numeric;
  v_total numeric := 0;
  v_done boolean;
  v_admin boolean := public.is_admin();
begin
  if v_uid is null then raise exception 'Unauthorized'; end if;

  if v_uid <> auth.uid() then
    if not v_admin or not public.admin_has_permission('manage_users') then
      raise exception 'Permission denied';
    end if;
  end if;

  perform public.assert_user_can_transact(v_uid);

  for v_inv in
    select *
    from public.user_investment
    where user_id = v_uid
      and status = 'active'
      and daily_accrual_enabled = true
    order by created_at
    for update
  loop
    v_elapsed_days := least(
      v_inv.duration_days,
      greatest(
        0,
        floor(extract(epoch from(v_now-v_inv.started_at))/86400)::integer
      )
    );
    v_previous_days := least(
      v_inv.duration_days,
      greatest(
        0,
        floor(extract(epoch from(v_inv.last_accrual_at-v_inv.started_at))/86400)::integer
      )
    );
    v_days := greatest(0,v_elapsed_days-v_previous_days);

    if v_days > 0 then
      v_profit := v_inv.principal*v_inv.daily_rate*v_days;
      v_total := v_total+v_profit;
      v_done := v_elapsed_days >= v_inv.duration_days;

      update public.user_profile
      set available_balance = available_balance + v_profit,
          locked_balance = case
            when v_done then greatest(0,locked_balance-v_inv.principal)
            else locked_balance
          end,
          updated_at = now()
      where user_id = v_uid;

      update public.user_investment
      set credited_profit = credited_profit + v_profit,
          last_accrual_at = least(
            v_inv.started_at+make_interval(days=>v_inv.duration_days),
            v_now
          ),
          status = case when v_done then 'completed' else 'active' end,
          completed_at = case when v_done then v_now else completed_at end,
          updated_at = now()
      where id = v_inv.id;

      insert into public.transaction(
        user_id,type,amount,status,approval_status,method,note
      )
      values(
        v_uid,'bonus',v_profit,'completed','approved',
        case when v_done then 'Plan maturity' else 'Daily interest' end,
        'Server-side investment profit'
      );
    end if;
  end loop;

  return v_total;
end;
$function$;

revoke all on function public.accrue_user_investments(uuid) from public, anon;
grant execute on function public.accrue_user_investments(uuid) to authenticated;

-- Admin search requires the user-management permission.
create or replace function public.admin_search_users(
  p_query text default '',
  p_limit integer default 50
)
returns table (
  user_id uuid,
  email text,
  username text,
  fullname text,
  phone text,
  country text,
  kyc_status text,
  available_balance numeric,
  locked_balance numeric,
  total_deposits numeric,
  total_withdrawals numeric,
  referral_earnings numeric,
  blocked boolean,
  blocked_reason text,
  blocked_at timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_query text := lower(trim(coalesce(p_query,'')));
  v_limit integer := greatest(1, least(coalesce(p_limit,50),100));
begin
  if not public.is_admin() or not public.admin_has_permission('manage_users') then
    raise exception 'Permission denied';
  end if;

  return query
  select
    p.user_id,u.email::text,p.username,p.fullname,p.phone,p.country,p.kyc_status,
    p.available_balance,p.locked_balance,p.total_deposits,p.total_withdrawals,
    p.referral_earnings,p.blocked,p.blocked_reason,p.blocked_at,p.created_at
  from public.user_profile p
  join auth.users u on u.id=p.user_id
  where v_query=''
     or lower(coalesce(u.email,'')) like '%'||v_query||'%'
     or lower(coalesce(p.username,'')) like '%'||v_query||'%'
     or lower(coalesce(p.fullname,'')) like '%'||v_query||'%'
     or lower(coalesce(p.country,'')) like '%'||v_query||'%'
     or p.user_id::text like '%'||v_query||'%'
  order by p.created_at desc
  limit v_limit;
end;
$function$;

-- User blocking requires manage_users.
create or replace function public.admin_set_user_block(
  p_user_id uuid,p_blocked boolean,p_reason text default null
)
returns public.user_profile
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin public.admin_user;
  v_old public.user_profile;
  v_new public.user_profile;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
begin
  if not public.is_admin() or not public.admin_has_permission('manage_users') then
    raise exception 'Permission denied';
  end if;

  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  if p_user_id=auth.uid() then raise exception 'Administrators cannot block their own account'; end if;

  select * into v_old from public.user_profile where user_id=p_user_id for update;
  if v_old.user_id is null then raise exception 'User profile not found'; end if;

  update public.user_profile
  set blocked=p_blocked,
      blocked_reason=case when p_blocked then v_reason else null end,
      blocked_at=case when p_blocked then now() else null end,
      updated_at=now()
  where user_id=p_user_id
  returning * into v_new;

  insert into public.admin_action_audit(
    admin_id,user_id,action,target_id,old_values,new_values,reason
  )
  values(
    v_admin.id,p_user_id,
    case when p_blocked then 'user_blocked' else 'user_unblocked' end,
    p_user_id,
    jsonb_build_object('blocked',v_old.blocked,'blocked_reason',v_old.blocked_reason),
    jsonb_build_object('blocked',v_new.blocked,'blocked_reason',v_new.blocked_reason),
    v_reason
  );

  return v_new;
end;
$function$;

-- Investment regulation requires manage_users.
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
begin
  if not public.is_admin() or not public.admin_has_permission('manage_users') then
    raise exception 'Permission denied';
  end if;

  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;

  select * into v_old from public.user_investment where id=p_investment_id for update;
  if v_old.id is null then raise exception 'Investment not found'; end if;

  if p_daily_rate is not null and p_daily_rate < 0 then
    raise exception 'Daily rate cannot be negative';
  end if;

  update public.user_investment
  set daily_rate=coalesce(p_daily_rate,daily_rate),
      daily_accrual_enabled=coalesce(p_daily_accrual_enabled,daily_accrual_enabled),
      updated_at=now()
  where id=p_investment_id
  returning * into v_new;

  insert into public.admin_action_audit(
    admin_id,user_id,action,target_id,old_values,new_values,reason
  )
  values(
    v_admin.id,v_old.user_id,'investment_updated',p_investment_id,
    jsonb_build_object('daily_rate',v_old.daily_rate,'daily_accrual_enabled',v_old.daily_accrual_enabled),
    jsonb_build_object('daily_rate',v_new.daily_rate,'daily_accrual_enabled',v_new.daily_accrual_enabled),
    'Administrator updated investment accrual settings'
  );

  return v_new;
end;
$function$;

-- Admin transaction approval/rejection/settlement now enforce explicit permissions.
create or replace function public.admin_approve_transaction(
  p_transaction_id uuid,p_reason text default null
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare v_admin public.admin_user; v_tx public.transaction;
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then
    raise exception 'Permission denied';
  end if;

  select * into v_admin from public.admin_user where user_id=auth.uid();
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.approval_status<>'awaiting' then raise exception 'Transaction is not awaiting approval'; end if;

  update public.transaction
  set approval_status='approved',
      status=case when type in ('deposit','withdraw') then 'pending' else 'approved' end,
      approved_by=v_admin.id,approval_reason=p_reason,approved_at=now(),updated_at=now()
  where id=p_transaction_id
  returning * into v_tx;

  insert into public.transaction_audit(
    transaction_id,admin_id,action,old_values,new_values,reason
  )
  values(
    v_tx.id,v_admin.id,'approved',
    jsonb_build_object('approval_status','awaiting'),
    jsonb_build_object('approval_status',v_tx.approval_status,'status',v_tx.status),
    p_reason
  );

  return v_tx;
end;
$function$;

create or replace function public.admin_reject_transaction(
  p_transaction_id uuid,p_reason text
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare v_admin public.admin_user; v_tx public.transaction;
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
    update public.user_profile
    set available_balance=available_balance+v_tx.amount,updated_at=now()
    where user_id=v_tx.user_id;
  end if;

  update public.transaction
  set approval_status='rejected',status='failed',approved_by=v_admin.id,
      approval_reason=p_reason,approved_at=now(),updated_at=now()
  where id=p_transaction_id
  returning * into v_tx;

  insert into public.transaction_audit(
    transaction_id,admin_id,action,old_values,new_values,reason
  )
  values(
    v_tx.id,v_admin.id,'rejected',
    jsonb_build_object('approval_status','awaiting'),
    jsonb_build_object('approval_status',v_tx.approval_status,'status',v_tx.status),
    p_reason
  );

  return v_tx;
end;
$function$;

create or replace function public.admin_settle_transaction(
  p_transaction_id uuid,p_reason text default null
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare v_admin public.admin_user; v_tx public.transaction;
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then
    raise exception 'Permission denied';
  end if;

  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;

  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.type not in('deposit','withdraw') then raise exception 'Only deposit and withdrawal can be settled'; end if;
  if v_tx.status='completed' then raise exception 'Transaction already completed'; end if;
  if v_tx.approval_status<>'approved' then raise exception 'Transaction must be approved first'; end if;

  perform public.assert_user_can_transact(v_tx.user_id);

  if v_tx.type='deposit' then
    update public.user_profile
    set available_balance=available_balance+v_tx.amount,
        total_deposits=total_deposits+v_tx.amount,
        updated_at=now()
    where user_id=v_tx.user_id;
  else
    update public.user_profile
    set total_withdrawals=total_withdrawals+v_tx.amount,
        updated_at=now()
    where user_id=v_tx.user_id;
  end if;

  update public.transaction
  set status='completed',settled_at=now(),updated_at=now()
  where id=p_transaction_id
  returning * into v_tx;

  if v_tx.type='deposit' then
    perform public.credit_referral_for_deposit(v_tx.id);
  end if;

  insert into public.transaction_audit(
    transaction_id,admin_id,action,old_values,new_values,reason
  )
  values(
    v_tx.id,v_admin.id,'settled',
    jsonb_build_object('status','pending'),
    jsonb_build_object('status',v_tx.status),
    p_reason
  );

  return v_tx;
end;
$function$;

revoke all on function public.admin_search_users(text,integer) from public, anon;
revoke all on function public.admin_set_user_block(uuid,boolean,text) from public, anon;
revoke all on function public.admin_update_investment(uuid,numeric,boolean) from public, anon;
revoke all on function public.admin_approve_transaction(uuid,text) from public, anon;
revoke all on function public.admin_reject_transaction(uuid,text) from public, anon;
revoke all on function public.admin_settle_transaction(uuid,text) from public, anon;

grant execute on function public.admin_search_users(text,integer) to authenticated;
grant execute on function public.admin_set_user_block(uuid,boolean,text) to authenticated;
grant execute on function public.admin_update_investment(uuid,numeric,boolean) to authenticated;
grant execute on function public.admin_approve_transaction(uuid,text) to authenticated;
grant execute on function public.admin_reject_transaction(uuid,text) to authenticated;
grant execute on function public.admin_settle_transaction(uuid,text) to authenticated;

-- Swap is intentionally NOT callable from the browser. Only the Edge Function
-- may call the 5-argument service-side function after authenticating the user
-- and obtaining a fresh market quote.
drop function if exists public.swap_assets(text,text,numeric,numeric);

create or replace function public.swap_assets(
  p_user_id uuid,
  p_from text,
  p_to text,
  p_amount numeric,
  p_rate numeric
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_profile public.user_profile;
  v_out numeric;
  v_tx public.transaction;
begin
  if p_user_id is null then raise exception 'Unauthorized'; end if;
  perform public.assert_user_can_transact(p_user_id);

  if p_from not in('USD','BDX') or p_to not in('USD','BDX') or p_from=p_to then
    raise exception 'Invalid swap pair';
  end if;
  if p_amount is null or p_amount<=0 then
    raise exception 'Amount must be greater than zero';
  end if;
  if p_rate is null or p_rate<=0 then
    raise exception 'Invalid rate';
  end if;

  select * into v_profile
  from public.user_profile
  where user_id=p_user_id
  for update;

  if v_profile.user_id is null then raise exception 'Profile not found'; end if;

  if p_from='USD' then
    if v_profile.available_balance<p_amount then raise exception 'Insufficient USD balance'; end if;
    v_out:=p_amount/p_rate;

    update public.user_profile
    set available_balance=available_balance-p_amount,
        bdx_balance=bdx_balance+v_out,
        updated_at=now()
    where user_id=p_user_id;

    insert into public.transaction(
      user_id,type,amount,status,approval_status,method,note
    )
    values(
      p_user_id,'swap',p_amount,'completed','approved','USD → BDX',
      p_amount::text||' USD → '||round(v_out,4)::text||' BDX @ '||p_rate::text
    )
    returning * into v_tx;
  else
    if v_profile.bdx_balance<p_amount then raise exception 'Insufficient BDX balance'; end if;
    v_out:=p_amount*p_rate;

    update public.user_profile
    set bdx_balance=bdx_balance-p_amount,
        available_balance=available_balance+v_out,
        updated_at=now()
    where user_id=p_user_id;

    insert into public.transaction(
      user_id,type,amount,status,approval_status,method,note
    )
    values(
      p_user_id,'swap',v_out,'completed','approved','BDX → USD',
      p_amount::text||' BDX → '||round(v_out,2)::text||' USD @ '||p_rate::text
    )
    returning * into v_tx;
  end if;

  return v_tx;
end;
$function$;

revoke all on function public.swap_assets(uuid,text,text,numeric,numeric) from public, anon, authenticated;
grant execute on function public.swap_assets(uuid,text,text,numeric,numeric) to service_role;

commit;
