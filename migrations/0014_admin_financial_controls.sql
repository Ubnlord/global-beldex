begin;

-- Secure administrative financial controls.
-- Every function checks the caller's admin role + explicit permission in PostgreSQL.
-- No client-side role check is trusted.

create or replace function public.admin_fund_user(
  p_user_id uuid,
  p_amount numeric,
  p_reason text,
  p_reference text default null
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_old public.user_profile;
  v_new public.user_profile;
  v_tx public.transaction;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
  v_reference text := nullif(trim(coalesce(p_reference,'')),'');
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then raise exception 'Permission denied'; end if;
  if p_user_id is null then raise exception 'User is required'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be greater than zero'; end if;
  if v_reason is null then raise exception 'Reason is required'; end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  select * into v_old from public.user_profile where user_id=p_user_id for update;
  if v_old.user_id is null then raise exception 'User profile not found'; end if;
  if coalesce(v_old.blocked,false) then raise exception 'User account is blocked'; end if;
  update public.user_profile set available_balance=available_balance+p_amount,total_deposits=total_deposits+p_amount,updated_at=now() where user_id=p_user_id returning * into v_new;
  insert into public.transaction(user_id,type,amount,status,approval_status,method,note,approved_by,approval_reason,approved_at,settled_at)
  values(p_user_id,'deposit',p_amount,'completed','approved','Admin funding','Admin funding: '||v_reason||case when v_reference is not null then ' | Ref: '||v_reference else '' end,v_admin.id,v_reason,now(),now())
  returning * into v_tx;
  insert into public.admin_action_audit(admin_id,user_id,action,target_id,old_values,new_values,reason)
  values(v_admin.id,p_user_id,'user_funded',v_tx.id,jsonb_build_object('available_balance',v_old.available_balance,'total_deposits',v_old.total_deposits),jsonb_build_object('available_balance',v_new.available_balance,'total_deposits',v_new.total_deposits,'amount',p_amount),v_reason);
  return v_tx;
end;
$function$;

create or replace function public.admin_adjust_balance(
  p_user_id uuid,
  p_delta numeric,
  p_reason text,
  p_reference text default null
)
returns public.transaction
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_old public.user_profile;
  v_new public.user_profile;
  v_tx public.transaction;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
  v_reference text := nullif(trim(coalesce(p_reference,'')),'');
  v_type text;
  v_amount numeric;
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then raise exception 'Permission denied'; end if;
  if p_user_id is null then raise exception 'User is required'; end if;
  if p_delta is null or p_delta = 0 then raise exception 'Adjustment cannot be zero'; end if;
  if v_reason is null then raise exception 'Reason is required'; end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  select * into v_old from public.user_profile where user_id=p_user_id for update;
  if v_old.user_id is null then raise exception 'User profile not found'; end if;
  if v_old.available_balance+p_delta < 0 then raise exception 'Adjustment would make available balance negative'; end if;
  v_type := case when p_delta > 0 then 'bonus' else 'withdraw' end;
  v_amount := abs(p_delta);
  update public.user_profile set available_balance=available_balance+p_delta,updated_at=now() where user_id=p_user_id returning * into v_new;
  insert into public.transaction(user_id,type,amount,status,approval_status,method,note,approved_by,approval_reason,approved_at,settled_at)
  values(p_user_id,v_type,v_amount,'completed','approved','Admin adjustment',v_reason||case when v_reference is not null then ' | Ref: '||v_reference else '' end,v_admin.id,v_reason,now(),now())
  returning * into v_tx;
  insert into public.admin_action_audit(admin_id,user_id,action,target_id,old_values,new_values,reason)
  values(v_admin.id,p_user_id,'balance_adjusted',v_tx.id,jsonb_build_object('available_balance',v_old.available_balance),jsonb_build_object('available_balance',v_new.available_balance,'delta',p_delta),v_reason);
  return v_tx;
end;
$function$;

create or replace function public.admin_approve_deposit(p_transaction_id uuid,p_reason text default null)
returns public.transaction
language plpgsql security definer set search_path=pg_catalog,public,pg_temp
as $function$
declare v_tx public.transaction;
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then raise exception 'Permission denied'; end if;
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.type<>'deposit' then raise exception 'Transaction is not a deposit'; end if;
  return public.admin_approve_transaction(p_transaction_id,p_reason);
end;
$function$;

create or replace function public.admin_reject_deposit(p_transaction_id uuid,p_reason text)
returns public.transaction
language plpgsql security definer set search_path=pg_catalog,public,pg_temp
as $function$
declare v_tx public.transaction;
begin
  if not public.is_admin() or not public.admin_has_permission('reject_transactions') then raise exception 'Permission denied'; end if;
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.type<>'deposit' then raise exception 'Transaction is not a deposit'; end if;
  return public.admin_reject_transaction(p_transaction_id,p_reason);
end;
$function$;

create or replace function public.admin_approve_withdrawal(p_transaction_id uuid,p_reason text default null)
returns public.transaction
language plpgsql security definer set search_path=pg_catalog,public,pg_temp
as $function$
declare v_tx public.transaction;
begin
  if not public.is_admin() or not public.admin_has_permission('approve_transactions') then raise exception 'Permission denied'; end if;
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.type<>'withdraw' then raise exception 'Transaction is not a withdrawal'; end if;
  return public.admin_approve_transaction(p_transaction_id,p_reason);
end;
$function$;

create or replace function public.admin_reject_withdrawal(p_transaction_id uuid,p_reason text)
returns public.transaction
language plpgsql security definer set search_path=pg_catalog,public,pg_temp
as $function$
declare v_tx public.transaction;
begin
  if not public.is_admin() or not public.admin_has_permission('reject_transactions') then raise exception 'Permission denied'; end if;
  select * into v_tx from public.transaction where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Transaction not found'; end if;
  if v_tx.type<>'withdraw' then raise exception 'Transaction is not a withdrawal'; end if;
  return public.admin_reject_transaction(p_transaction_id,p_reason);
end;
$function$;

create or replace function public.admin_manage_investment(
  p_investment_id uuid,
  p_daily_rate numeric default null,
  p_daily_accrual_enabled boolean default null,
  p_status text default null,
  p_reason text default null
)
returns public.user_investment
language plpgsql security definer set search_path=pg_catalog,public,pg_temp
as $function$
declare
  v_admin public.admin_user;
  v_old public.user_investment;
  v_new public.user_investment;
  v_profile public.user_profile;
  v_status text := nullif(lower(trim(coalesce(p_status,''))), '');
  v_reason text := nullif(trim(coalesce(p_reason,'')), '');
begin
  if not public.is_admin() or not public.admin_has_permission('manage_users') then raise exception 'Permission denied'; end if;
  if p_investment_id is null then raise exception 'Investment is required'; end if;
  if p_daily_rate is not null and p_daily_rate<0 then raise exception 'Daily rate cannot be negative'; end if;
  if v_status is not null and v_status not in ('active','completed','cancelled') then raise exception 'Invalid investment status'; end if;
  if v_status in ('completed','cancelled') and v_reason is null then raise exception 'Reason is required when changing investment status'; end if;
  select * into v_admin from public.admin_user where user_id=auth.uid();
  if v_admin.id is null then raise exception 'Admin access required'; end if;
  select * into v_old from public.user_investment where id=p_investment_id for update;
  if v_old.id is null then raise exception 'Investment not found'; end if;
  select * into v_profile from public.user_profile where user_id=v_old.user_id for update;
  if v_profile.user_id is null then raise exception 'User profile not found'; end if;

  if v_status in ('completed','cancelled') and v_old.status='active' then
    update public.user_profile set locked_balance=greatest(0,locked_balance-v_old.principal),updated_at=now() where user_id=v_old.user_id;
  elsif v_status='active' and v_old.status in ('completed','cancelled') then
    if v_profile.available_balance<v_old.principal then raise exception 'Insufficient available balance to reactivate investment'; end if;
    update public.user_profile set available_balance=available_balance-v_old.principal,locked_balance=locked_balance+v_old.principal,updated_at=now() where user_id=v_old.user_id;
  end if;

  update public.user_investment
  set daily_rate=coalesce(p_daily_rate,daily_rate),
      daily_accrual_enabled=coalesce(p_daily_accrual_enabled,daily_accrual_enabled),
      status=coalesce(v_status,status),
      completed_at=case when v_status in ('completed','cancelled') then coalesce(completed_at,now()) when v_status='active' then null else completed_at end,
      updated_at=now()
  where id=p_investment_id
  returning * into v_new;

  insert into public.admin_action_audit(admin_id,user_id,action,target_id,old_values,new_values,reason)
  values(v_admin.id,v_old.user_id,'investment_managed',p_investment_id,
    jsonb_build_object('daily_rate',v_old.daily_rate,'daily_accrual_enabled',v_old.daily_accrual_enabled,'status',v_old.status),
    jsonb_build_object('daily_rate',v_new.daily_rate,'daily_accrual_enabled',v_new.daily_accrual_enabled,'status',v_new.status),
    coalesce(v_reason,'Administrator updated investment'));

  return v_new;
end;
$function$;

revoke all on function public.admin_fund_user(uuid,numeric,text,text) from public,anon;
revoke all on function public.admin_adjust_balance(uuid,numeric,text,text) from public,anon;
revoke all on function public.admin_approve_deposit(uuid,text) from public,anon;
revoke all on function public.admin_reject_deposit(uuid,text) from public,anon;
revoke all on function public.admin_approve_withdrawal(uuid,text) from public,anon;
revoke all on function public.admin_reject_withdrawal(uuid,text) from public,anon;
revoke all on function public.admin_manage_investment(uuid,numeric,boolean,text,text) from public,anon;

grant execute on function public.admin_fund_user(uuid,numeric,text,text) to authenticated;
grant execute on function public.admin_adjust_balance(uuid,numeric,text,text) to authenticated;
grant execute on function public.admin_approve_deposit(uuid,text) to authenticated;
grant execute on function public.admin_reject_deposit(uuid,text) to authenticated;
grant execute on function public.admin_approve_withdrawal(uuid,text) to authenticated;
grant execute on function public.admin_reject_withdrawal(uuid,text) to authenticated;
grant execute on function public.admin_manage_investment(uuid,numeric,boolean,text,text) to authenticated;

commit;